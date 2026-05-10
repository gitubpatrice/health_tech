import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/address.dart';
import '../../domain/client.dart';
import '../../domain/consent.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/busy_helpers.dart';
import '../../widgets/section_title.dart';

/// Create / edit form for a client. Uses one [Form] with a [GlobalKey] for
/// validation, no per-field controller leak (controllers disposed in dispose).
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.initial});

  final Client? initial;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _lastName;
  late final TextEditingController _firstName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _profession;
  late final TextEditingController _street;
  late final TextEditingController _complement;
  late final TextEditingController _zip;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _country;
  late final TextEditingController _healthNotes;
  late final TextEditingController _freeNotes;
  late final TextEditingController _companyName;
  late final TextEditingController _siret;
  late final TextEditingController _siren;

  String _kind = ClientKind.individual;
  String _civility = Civility.unspecified;
  DateTime? _birthDate;

  bool _geobiology = false;
  bool _emWaves = false;
  bool _consentRgpd = false;
  bool _consentDisclaimer = false;
  bool _consentReminder = false;
  bool _consentNewsletter = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _lastName = TextEditingController(text: c?.lastName ?? '');
    _firstName = TextEditingController(text: c?.firstName ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _profession = TextEditingController(text: c?.profession ?? '');
    _street = TextEditingController(text: c?.address.street ?? '');
    _complement = TextEditingController(text: c?.address.complement ?? '');
    _zip = TextEditingController(text: c?.address.zipCode ?? '');
    _city = TextEditingController(text: c?.address.city ?? '');
    _region = TextEditingController(text: c?.address.region ?? '');
    _country = TextEditingController(text: c?.address.country ?? 'FR');
    _healthNotes = TextEditingController(text: c?.healthNotes ?? '');
    _freeNotes = TextEditingController(text: c?.notes ?? '');
    _companyName = TextEditingController(
      text: (c?.business['company'] as String?) ?? '',
    );
    _siret = TextEditingController(
      text: (c?.business['siret'] as String?) ?? '',
    );
    _siren = TextEditingController(
      text: (c?.business['siren'] as String?) ?? '',
    );
    _kind = c?.kind ?? ClientKind.individual;
    _civility = c?.civility ?? Civility.unspecified;
    _birthDate = c?.birthDate;
    _geobiology = (c?.profile['geobiology'] as bool?) ?? false;
    _emWaves = (c?.profile['em_waves'] as bool?) ?? false;
    _consentRgpd = c?.consents.rgpdAt != null;
    _consentDisclaimer = c?.consents.disclaimerAt != null;
    _consentReminder = c?.consents.reminderAt != null;
    _consentNewsletter = c?.consents.newsletterAt != null;
  }

  @override
  void dispose() {
    for (final ctrl in [
      _lastName,
      _firstName,
      _phone,
      _email,
      _profession,
      _street,
      _complement,
      _zip,
      _city,
      _region,
      _country,
      _healthNotes,
      _freeNotes,
      _companyName,
      _siret,
      _siren,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_consentRgpd || !_consentDisclaimer) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.clientFormConsentRequired)));
      return;
    }
    setState(() => _busy = true);

    final now = DateTime.now();
    final isBusiness = _kind == ClientKind.business;
    final business = <String, dynamic>{
      if (isBusiness && _companyName.text.trim().isNotEmpty)
        'company': _companyName.text.trim(),
      if (isBusiness && _siret.text.trim().isNotEmpty)
        'siret': _siret.text.trim(),
      if (isBusiness && _siren.text.trim().isNotEmpty)
        'siren': _siren.text.trim(),
    };
    final profile = <String, dynamic>{
      ...?widget.initial?.profile,
      if (isBusiness) 'geobiology': _geobiology,
      if (isBusiness) 'em_waves': _emWaves,
    };

    final draft = Client(
      id: widget.initial?.id ?? '',
      kind: _kind,
      civility: isBusiness ? null : _civility,
      // For a business client, lastName carries the company name and
      // firstName stays empty; this keeps the search index (FTS5 on
      // last/first/phone/email) functional without a dedicated column.
      lastName: isBusiness ? _companyName.text.trim() : _lastName.text.trim(),
      firstName: isBusiness ? '' : _firstName.text.trim(),
      birthDate: isBusiness ? null : _birthDate,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      profession: _profession.text.trim().isEmpty
          ? null
          : _profession.text.trim(),
      address: Address(
        street: _street.text.trim(),
        complement: _complement.text.trim(),
        zipCode: _zip.text.trim(),
        city: _city.text.trim(),
        region: _region.text.trim(),
        country: _country.text.trim().isEmpty ? 'FR' : _country.text.trim(),
      ),
      consents: ConsentSet(
        rgpdAt: _consentRgpd ? (widget.initial?.consents.rgpdAt ?? now) : null,
        disclaimerAt: _consentDisclaimer
            ? (widget.initial?.consents.disclaimerAt ?? now)
            : null,
        reminderAt: _consentReminder
            ? (widget.initial?.consents.reminderAt ?? now)
            : null,
        newsletterAt: _consentNewsletter
            ? (widget.initial?.consents.newsletterAt ?? now)
            : null,
      ),
      profile: profile,
      business: business,
      healthNotes: _healthNotes.text,
      notes: _freeNotes.text,
    );

    final repo = ref.read(clientRepositoryProvider);
    await runWithBusy(
      context: context,
      setBusy: (v) => setState(() => _busy = v),
      action: () async {
        if (widget.initial == null) {
          await repo.create(draft);
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
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? l10n.clientFormTitleEdit : l10n.clientFormTitleNew,
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
              // Kind selector — drives which sections render below.
              // Switching to "business" replaces civility/birthdate with
              // company name + SIRET + SIREN + geobiology / EM checkboxes.
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: ClientKind.individual,
                    icon: const Icon(Icons.person_outline),
                    label: Text(l10n.clientKindIndividual),
                  ),
                  ButtonSegment(
                    value: ClientKind.business,
                    icon: const Icon(Icons.business_outlined),
                    label: Text(l10n.clientKindBusiness),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),
              if (_kind == ClientKind.individual) ...[
                SectionTitle(l10n.clientFormSectionIdentity),
                DropdownButtonFormField<String>(
                  initialValue: _civility,
                  decoration: InputDecoration(
                    labelText: l10n.clientFormCivility,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: Civility.mr,
                      child: Text(l10n.civilityMr),
                    ),
                    DropdownMenuItem(
                      value: Civility.mrs,
                      child: Text(l10n.civilityMrs),
                    ),
                    DropdownMenuItem(
                      value: Civility.unspecified,
                      child: Text(l10n.civilityUnspecified),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _civility = v ?? Civility.unspecified),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.clientFormLastName,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.clientFormFirstName,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.clientFormBirthDate),
                  subtitle: Text(
                    _birthDate == null
                        ? '—'
                        : '${_birthDate!.day.toString().padLeft(2, '0')}/'
                              '${_birthDate!.month.toString().padLeft(2, '0')}/'
                              '${_birthDate!.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: _pickBirthDate,
                ),
              ] else ...[
                SectionTitle(l10n.clientFormSectionBusiness),
                TextFormField(
                  controller: _companyName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.clientFormCompanyName,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siret,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.clientFormSiret),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siren,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.clientFormSiren),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _geobiology,
                  onChanged: (v) => setState(() => _geobiology = v ?? false),
                  title: Text(l10n.clientFormGeobiology),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _emWaves,
                  onChanged: (v) => setState(() => _emWaves = v ?? false),
                  title: Text(l10n.clientFormEmWaves),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const Divider(height: 32),
              SectionTitle(l10n.clientFormSectionContact),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l10n.clientFormPhone),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.clientFormEmail),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  return _emailRe.hasMatch(s) ? null : l10n.fieldInvalidEmail;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _profession,
                decoration: InputDecoration(
                  labelText: l10n.clientFormProfession,
                ),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.clientFormSectionAddress),
              TextFormField(
                controller: _street,
                decoration: InputDecoration(labelText: l10n.clientFormStreet),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _complement,
                decoration: InputDecoration(
                  labelText: l10n.clientFormComplement,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _zip,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.clientFormZip,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: l10n.clientFormCity,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _region,
                decoration: InputDecoration(labelText: l10n.clientFormRegion),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _country,
                decoration: InputDecoration(labelText: l10n.clientFormCountry),
              ),
              const Divider(height: 32),
              SectionTitle(
                _kind == ClientKind.business
                    ? l10n.clientFormSectionBusiness
                    : l10n.clientFormSectionHealth,
              ),
              TextFormField(
                controller: _healthNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _kind == ClientKind.business
                      ? l10n.clientFormSurveyNotes
                      : l10n.clientFormHealthNotes,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _freeNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _kind == ClientKind.business
                      ? l10n.clientFormRecommendations
                      : l10n.clientFormFreeNotes,
                ),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.clientFormSectionConsent),
              CheckboxListTile(
                value: _consentRgpd,
                onChanged: (v) => setState(() => _consentRgpd = v ?? false),
                title: Text(l10n.clientFormConsentRgpd),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _consentDisclaimer,
                onChanged: (v) =>
                    setState(() => _consentDisclaimer = v ?? false),
                title: Text(l10n.clientFormConsentDisclaimer),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _consentReminder,
                onChanged: (v) => setState(() => _consentReminder = v ?? false),
                title: Text(l10n.clientFormConsentReminder),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _consentNewsletter,
                onChanged: (v) =>
                    setState(() => _consentNewsletter = v ?? false),
                title: Text(l10n.clientFormConsentNewsletter),
                controlAffinity: ListTileControlAffinity.leading,
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

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
