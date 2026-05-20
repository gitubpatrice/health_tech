import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../domain/attachment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../utils/validators.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/busy_helpers.dart';
import '../../widgets/error_view.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sensitive_text_field.dart';
import '../../widgets/snack_utils.dart';
import '../clients/client_providers.dart';
import 'animal_l10n.dart';

class AnimalFormScreen extends ConsumerStatefulWidget {
  const AnimalFormScreen({super.key, this.initial, this.defaultClientId});

  final Animal? initial;

  /// Pre-selected client when opened from a client detail "+ animal" button.
  final String? defaultClientId;

  @override
  ConsumerState<AnimalFormScreen> createState() => _AnimalFormScreenState();
}

class _AnimalFormScreenState extends ConsumerState<AnimalFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _color;
  late final TextEditingController _weightKg;
  late final TextEditingController _chip;
  late final TextEditingController _tattoo;
  late final TextEditingController _pedigree;
  late final TextEditingController _vetName;
  late final TextEditingController _vetClinic;
  late final TextEditingController _vetPhone;
  late final TextEditingController _vetEmail;
  late final TextEditingController _vaccinationNotes;
  late final TextEditingController _healthNotes;
  late final TextEditingController _behaviorNotes;

  String _species = Species.dog;
  String _sex = AnimalSex.unknown;
  DateTime? _birthDate;
  DateTime? _lastVaccin;
  DateTime? _nextVaccin;
  String? _clientId;
  bool _busy = false;

  /// Controller `AvatarPicker` — utilisé uniquement en création (l'ID DB
  /// n'existe pas encore). En édition, le picker écrit directement via
  /// `setAvatar(ownerType, ownerId)` et le controller reste inerte.
  late final AvatarPickerController _avatarController;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _avatarController = AvatarPickerController();
    _name = TextEditingController(text: a?.name ?? '');
    _breed = TextEditingController(text: a?.breed ?? '');
    _color = TextEditingController(text: a?.color ?? '');
    _weightKg = TextEditingController(
      text: a?.weightKg == null ? '' : a!.weightKg!.toStringAsFixed(2),
    );
    _chip = TextEditingController(text: a?.identifiers.chipNumber ?? '');
    _tattoo = TextEditingController(text: a?.identifiers.tattooNumber ?? '');
    _pedigree = TextEditingController(
      text: a?.identifiers.pedigreeNumber ?? '',
    );
    _vetName = TextEditingController(text: a?.identifiers.vetName ?? '');
    _vetClinic = TextEditingController(text: a?.identifiers.vetClinic ?? '');
    _vetPhone = TextEditingController(text: a?.identifiers.vetPhone ?? '');
    _vetEmail = TextEditingController(text: a?.identifiers.vetEmail ?? '');
    _vaccinationNotes = TextEditingController(
      text: a?.identifiers.vaccinationNotes ?? '',
    );
    _healthNotes = TextEditingController(text: a?.healthNotes ?? '');
    _behaviorNotes = TextEditingController(text: a?.behaviorNotes ?? '');
    _species = a?.species ?? Species.dog;
    _sex = a?.sex ?? AnimalSex.unknown;
    _birthDate = a?.birthDate;
    _lastVaccin = a?.identifiers.lastVaccinationAt;
    _nextVaccin = a?.identifiers.nextVaccinationAt;
    _clientId = a?.clientId ?? widget.defaultClientId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _breed,
      _color,
      _weightKg,
      _chip,
      _tattoo,
      _pedigree,
      _vetName,
      _vetClinic,
      _vetPhone,
      _vetEmail,
      _vaccinationNotes,
      _healthNotes,
      _behaviorNotes,
    ]) {
      c.dispose();
    }
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
    DateTime? firstDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: firstDate ?? DateTime(now.year - 80),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (_clientId == null) {
      // v1.7.1 (H2) — snackbar canonique floating + couleur erreur M3.
      // Avant : SnackBar brut sans `behavior: floating` ni `backgroundColor`
      // → fixed en bas, contraste blanc-sur-blanc potentiel en light mode.
      showFloatingSnack(
        context,
        l10n.sessionFormSelectClient,
        tone: SnackTone.error,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    int? grams;
    final w = _weightKg.text.replaceAll(',', '.').trim();
    if (w.isNotEmpty) {
      final kg = double.tryParse(w);
      if (kg != null && kg >= 0) grams = (kg * 1000).round();
    }

    // (audit M7) `runWithBusy` plus bas gère seul la transition
    // _busy=true/finally. Doublon retiré pour éviter un état zombie
    // si une exception échappait entre cet appel et le runWithBusy.
    //
    // (audit v1.6.0 F9 / F10) Strip-RTL au save sur les libellés vet :
    // un `.htbk` forgé pourrait injecter des caractères de contrôle
    // bidirectionnel pour inverser le rendu visuel. On les retire à la
    // source, pas seulement à l'affichage. Le cap longueur côté UI
    // (`maxLength`) tronque déjà la saisie utilisateur ; ici on couvre
    // aussi le cas où la saisie viendrait d'un import.
    String cleanShort(String raw, int max) {
      final cleaned = HealthValidators.cleanShortLabel(raw, max: max);
      return cleaned ?? '';
    }

    final identifiers = AnimalIdentifiers(
      chipNumber: cleanShort(_chip.text, 64),
      tattooNumber: cleanShort(_tattoo.text, 64),
      pedigreeNumber: cleanShort(_pedigree.text, 64),
      lastVaccinationAt: _lastVaccin,
      nextVaccinationAt: _nextVaccin,
      vaccinationNotes: HealthValidators.stripBidiOverrides(
        _vaccinationNotes.text.trim(),
      ),
      vetName: cleanShort(_vetName.text, 120),
      vetClinic: cleanShort(_vetClinic.text, 120),
      vetPhone: cleanShort(_vetPhone.text, 32),
      vetEmail: cleanShort(_vetEmail.text, 254),
    );
    final draft = Animal(
      id: widget.initial?.id ?? '',
      clientId: _clientId!,
      name: _name.text.trim(),
      species: _species,
      breed: _breed.text.trim().isEmpty ? null : _breed.text.trim(),
      sex: _sex,
      birthDate: _birthDate,
      weightGrams: grams,
      color: _color.text.trim().isEmpty ? null : _color.text.trim(),
      identifiers: identifiers,
      healthNotes: _healthNotes.text,
      behaviorNotes: _behaviorNotes.text,
    );

    final repo = ref.read(animalRepositoryProvider);
    await runWithBusy(
      context: context,
      setBusy: (bool v) => setState(() => _busy = v),
      action: () async {
        if (widget.initial == null) {
          final created = await repo.create(draft);
          // En création : commit l'avatar pris AVANT que l'ID DB n'existe.
          // No-op si rien en attente. L'éventuelle erreur d'attachement
          // est capturée par `runWithBusy` (l'animal lui-même est déjà
          // persisté).
          await _avatarController.commit(
            ref: ref,
            ownerType: AttachmentOwner.animal,
            ownerId: created.id,
          );
        } else {
          await repo.update(draft);
        }
        if (!mounted) return;
        Navigator.of(context).pop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final clients = ref.watch(clientsStreamProvider);
    final isEdit = widget.initial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? l10n.animalFormTitleEdit : l10n.animalFormTitleNew,
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Photo-avatar (point 7 v1.6.x). Mode draft via controller en
              // création, mode immédiat en édition.
              AvatarPicker(
                ownerType: AttachmentOwner.animal,
                ownerId: widget.initial?.id ?? '',
                placeholder: const Icon(Icons.pets_outlined),
                controller: widget.initial == null ? _avatarController : null,
              ),
              const SizedBox(height: 16),
              SectionTitle(l10n.animalFormSectionIdentity),
              clients.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(localiseError(context, e)),
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _clientId,
                  decoration: InputDecoration(labelText: l10n.animalFormClient),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(value: c.id, child: Text(c.fullName)),
                  ],
                  onChanged: (v) => setState(() => _clientId = v),
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.fieldRequired : null,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.animalFormName),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _species,
                decoration: InputDecoration(labelText: l10n.animalFormSpecies),
                items: [
                  for (final s in Species.all)
                    DropdownMenuItem(
                      value: s,
                      child: Text(speciesLabel(l10n, s)),
                    ),
                ],
                onChanged: (v) => setState(() => _species = v ?? Species.dog),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _breed,
                decoration: InputDecoration(labelText: l10n.animalFormBreed),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: InputDecoration(labelText: l10n.animalFormSex),
                items: [
                  DropdownMenuItem(
                    value: AnimalSex.male,
                    child: Text(l10n.sexMale),
                  ),
                  DropdownMenuItem(
                    value: AnimalSex.female,
                    child: Text(l10n.sexFemale),
                  ),
                  DropdownMenuItem(
                    value: AnimalSex.maleNeutered,
                    child: Text(l10n.sexMaleNeutered),
                  ),
                  DropdownMenuItem(
                    value: AnimalSex.femaleSpayed,
                    child: Text(l10n.sexFemaleSpayed),
                  ),
                  DropdownMenuItem(
                    value: AnimalSex.unknown,
                    child: Text(l10n.sexUnknown),
                  ),
                ],
                onChanged: (v) => setState(() => _sex = v ?? AnimalSex.unknown),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.animalFormBirthDate),
                subtitle: Text(
                  _birthDate == null ? '—' : formatDate(_birthDate!),
                ),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () => _pickDate(
                  context,
                  current: _birthDate,
                  onPicked: (d) => setState(() => _birthDate = d),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightKg,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.animalFormWeightKg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _color,
                      decoration: InputDecoration(
                        labelText: l10n.animalFormColor,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionIdentifiers),
              TextFormField(
                controller: _chip,
                decoration: InputDecoration(labelText: l10n.animalFormChip),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tattoo,
                decoration: InputDecoration(labelText: l10n.animalFormTattoo),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pedigree,
                decoration: InputDecoration(labelText: l10n.animalFormPedigree),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionVet),
              // Tous les champs vétérinaires sont cappés à 120 chars et
              // strip-RTL au save (cf. `_save()` plus haut) — pas de
              // gonflement possible via un `.htbk` forgé. L'email est
              // validé via `HealthValidators.optionalEmail`
              // (audit v1.6.0 F9).
              TextFormField(
                controller: _vetName,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: l10n.animalFormVetName,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vetClinic,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: l10n.animalFormVetClinic,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vetPhone,
                keyboardType: TextInputType.phone,
                maxLength: 32,
                decoration: InputDecoration(
                  labelText: l10n.animalFormVetPhone,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vetEmail,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                decoration: InputDecoration(
                  labelText: l10n.animalFormVetEmail,
                  counterText: '',
                ),
                validator: (v) => HealthValidators.optionalEmail(
                  v,
                  errorMessage: l10n.fieldInvalidEmail,
                ),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionVaccination),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.animalFormLastVaccination),
                subtitle: Text(
                  _lastVaccin == null ? '—' : formatDate(_lastVaccin!),
                ),
                trailing: const Icon(Icons.vaccines_outlined),
                onTap: () => _pickDate(
                  context,
                  current: _lastVaccin,
                  onPicked: (d) => setState(() => _lastVaccin = d),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.animalFormNextVaccination),
                subtitle: Text(
                  _nextVaccin == null ? '—' : formatDate(_nextVaccin!),
                ),
                trailing: const Icon(Icons.event_outlined),
                onTap: () => _pickDate(
                  context,
                  current: _nextVaccin,
                  onPicked: (d) => setState(() => _nextVaccin = d),
                ),
              ),
              const SizedBox(height: 12),
              SensitiveTextField(
                controller: _vaccinationNotes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.animalFormVaccinationNotes,
                ),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionHealth),
              SensitiveTextField(
                controller: _healthNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.animalFormHealthNotes,
                ),
              ),
              const SizedBox(height: 12),
              SensitiveTextField(
                controller: _behaviorNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.animalFormBehaviorNotes,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(l10n.actionSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
