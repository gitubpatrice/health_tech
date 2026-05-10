import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/error_view.dart';
import '../../widgets/section_title.dart';
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
  late final TextEditingController _vetPhone;
  late final TextEditingController _vetEmail;
  late final TextEditingController _healthNotes;
  late final TextEditingController _behaviorNotes;

  String _species = Species.dog;
  String _sex = AnimalSex.unknown;
  DateTime? _birthDate;
  DateTime? _lastVaccin;
  String? _clientId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
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
    _vetPhone = TextEditingController(text: a?.identifiers.vetPhone ?? '');
    _vetEmail = TextEditingController(text: a?.identifiers.vetEmail ?? '');
    _healthNotes = TextEditingController(text: a?.healthNotes ?? '');
    _behaviorNotes = TextEditingController(text: a?.behaviorNotes ?? '');
    _species = a?.species ?? Species.dog;
    _sex = a?.sex ?? AnimalSex.unknown;
    _birthDate = a?.birthDate;
    _lastVaccin = a?.identifiers.lastVaccinationAt;
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
      _vetPhone,
      _vetEmail,
      _healthNotes,
      _behaviorNotes,
    ]) {
      c.dispose();
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sessionFormSelectClient)));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    int? grams;
    final w = _weightKg.text.replaceAll(',', '.').trim();
    if (w.isNotEmpty) {
      final kg = double.tryParse(w);
      if (kg != null && kg >= 0) grams = (kg * 1000).round();
    }

    setState(() => _busy = true);
    final identifiers = AnimalIdentifiers(
      chipNumber: _chip.text.trim(),
      tattooNumber: _tattoo.text.trim(),
      pedigreeNumber: _pedigree.text.trim(),
      lastVaccinationAt: _lastVaccin,
      vetName: _vetName.text.trim(),
      vetPhone: _vetPhone.text.trim(),
      vetEmail: _vetEmail.text.trim(),
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
    try {
      if (widget.initial == null) {
        await repo.create(draft);
      } else {
        await repo.update(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              const SizedBox(height: 12),
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
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionVet),
              TextFormField(
                controller: _vetName,
                decoration: InputDecoration(labelText: l10n.animalFormVetName),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vetPhone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l10n.animalFormVetPhone),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vetEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.animalFormVetEmail),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.animalFormSectionHealth),
              TextFormField(
                controller: _healthNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.animalFormHealthNotes,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
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
