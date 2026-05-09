import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/address.dart';
import '../../domain/client.dart';
import '../../domain/consent.dart';
import '../../l10n/generated/app_localizations.dart';
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

  String _civility = Civility.unspecified;
  DateTime? _birthDate;

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
    _civility = c?.civility ?? Civility.unspecified;
    _birthDate = c?.birthDate;
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
    final draft = Client(
      id: widget.initial?.id ?? '',
      civility: _civility,
      lastName: _lastName.text.trim(),
      firstName: _firstName.text.trim(),
      birthDate: _birthDate,
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
      healthNotes: _healthNotes.text,
      notes: _freeNotes.text,
    );

    final repo = ref.read(clientRepositoryProvider);
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
              SectionTitle(l10n.clientFormSectionIdentity),
              DropdownButtonFormField<String>(
                initialValue: _civility,
                decoration: InputDecoration(labelText: l10n.clientFormCivility),
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
                decoration: InputDecoration(labelText: l10n.clientFormLastName),
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
              SectionTitle(l10n.clientFormSectionHealth),
              TextFormField(
                controller: _healthNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.clientFormHealthNotes,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _freeNotes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.clientFormFreeNotes,
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
