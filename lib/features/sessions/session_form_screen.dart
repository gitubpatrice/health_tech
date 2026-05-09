import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/animal.dart';
import '../../domain/session.dart';
import '../../l10n/generated/app_localizations.dart';
import '../animals/animal_providers.dart';
import '../clients/client_providers.dart';
import 'session_l10n.dart';

class SessionFormScreen extends ConsumerStatefulWidget {
  const SessionFormScreen({
    super.key,
    this.initial,
    this.defaultClientId,
    this.defaultAnimalId,
  });

  final Session? initial;
  final String? defaultClientId;
  final String? defaultAnimalId;

  @override
  ConsumerState<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends ConsumerState<SessionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _location;
  late final TextEditingController _price;
  late final TextEditingController _before;
  late final TextEditingController _client;
  late final TextEditingController _observations;
  late final TextEditingController _flow;
  late final TextEditingController _zones;
  late final TextEditingController _energetic;
  late final TextEditingController _after;
  late final TextEditingController _advice;
  late final TextEditingController _next;
  late final TextEditingController _privateNote;

  String? _clientId;
  String? _animalId;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(hours: 1));
  String _kind = SessionKind.human;
  String _status = SessionStatus.planned;
  String? _paymentStatus;
  String? _paymentMethod;
  final Set<String> _motives = <String>{};
  int? _improvement;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _location = TextEditingController(text: s?.location ?? '');
    _price = TextEditingController(
      text: s?.priceCents == null ? '' : (s!.priceCents! / 100).toStringAsFixed(2),
    );
    _before = TextEditingController(text: s?.report.beforeState ?? '');
    _client = TextEditingController(text: s?.report.clientPerception ?? '');
    _observations = TextEditingController(text: s?.report.observations ?? '');
    _flow = TextEditingController(text: s?.report.flow ?? '');
    _zones = TextEditingController(text: s?.report.zonesWorked ?? '');
    _energetic = TextEditingController(text: s?.report.energetic ?? '');
    _after = TextEditingController(text: s?.report.afterState ?? '');
    _advice = TextEditingController(text: s?.report.advice ?? '');
    _next = TextEditingController(text: s?.report.nextRecommendation ?? '');
    _privateNote = TextEditingController(text: s?.privateNote ?? '');

    _clientId = s?.clientId ?? widget.defaultClientId;
    _animalId = s?.animalId ?? widget.defaultAnimalId;
    _start = s?.startAt ?? _start;
    _end = s?.endAt ?? _end;
    _kind = s?.kind ?? SessionKind.human;
    _status = s?.status ?? SessionStatus.planned;
    _paymentStatus = s?.paymentStatus;
    _paymentMethod = s?.paymentMethod;
    _motives.addAll(s?.motives ?? const []);
    _improvement = s?.improvementLevel;
  }

  @override
  void dispose() {
    for (final c in [
      _location, _price, _before, _client, _observations,
      _flow, _zones, _energetic, _after, _advice, _next, _privateNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDateTime(
    BuildContext context, {
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    onPicked(DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ));
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sessionFormSelectClient)),
      );
      return;
    }
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sessionFormDurationInvalid)),
      );
      return;
    }
    setState(() => _busy = true);

    int? cents;
    final p = _price.text.replaceAll(',', '.').trim();
    if (p.isNotEmpty) {
      final v = double.tryParse(p);
      if (v != null && v >= 0) cents = (v * 100).round();
    }

    final draft = Session(
      id: widget.initial?.id ?? '',
      clientId: _clientId!,
      animalId: _animalId,
      startAt: _start,
      endAt: _end,
      kind: _kind,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      status: _status,
      motives: _motives.toList(),
      priceCents: cents,
      paymentStatus: _paymentStatus,
      paymentMethod: _paymentMethod,
      report: SessionReport(
        beforeState: _before.text,
        clientPerception: _client.text,
        observations: _observations.text,
        flow: _flow.text,
        zonesWorked: _zones.text,
        energetic: _energetic.text,
        afterState: _after.text,
        advice: _advice.text,
        nextRecommendation: _next.text,
      ),
      privateNote: _privateNote.text,
      improvementLevel: _improvement,
    );

    final repo = ref.read(sessionRepositoryProvider);
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
    final animals = _clientId == null
        ? const AsyncValue<List<Animal>>.data(<Animal>[])
        : ref.watch(animalsByClientProvider(_clientId!));
    final isEdit = widget.initial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l10n.sessionFormTitleEdit : l10n.sessionFormTitleNew),
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
              _SectionTitle(l10n.sessionFormSectionWho),
              clients.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _clientId,
                  decoration:
                      InputDecoration(labelText: l10n.animalFormClient),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.fullName),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _clientId = v;
                    _animalId = null;
                  }),
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.fieldRequired : null,
                ),
              ),
              const SizedBox(height: 12),
              animals.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('$e'),
                data: (list) => DropdownButtonFormField<String?>(
                  initialValue: _animalId,
                  decoration: InputDecoration(labelText: l10n.navAnimals),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final a in list)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(a.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _animalId = v),
                ),
              ),
              const Divider(height: 32),
              _SectionTitle(l10n.sessionFormSectionWhen),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.sessionFormStartAt),
                subtitle: Text(_formatDateTime(_start)),
                trailing: const Icon(Icons.schedule),
                onTap: () => _pickDateTime(
                  context,
                  current: _start,
                  onPicked: (d) => setState(() {
                    _start = d;
                    if (!_end.isAfter(_start)) {
                      _end = _start.add(const Duration(hours: 1));
                    }
                  }),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.sessionFormEndAt),
                subtitle: Text(_formatDateTime(_end)),
                trailing: const Icon(Icons.schedule),
                onTap: () => _pickDateTime(
                  context,
                  current: _end,
                  onPicked: (d) => setState(() => _end = d),
                ),
              ),
              const Divider(height: 32),
              _SectionTitle(l10n.sessionFormSectionType),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(labelText: l10n.sessionFormKind),
                items: [
                  for (final k in SessionKind.all)
                    DropdownMenuItem(value: k, child: Text(kindLabel(l10n, k))),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.sessionFormStatus),
                items: [
                  for (final s in SessionStatus.all)
                    DropdownMenuItem(
                      value: s,
                      child: Text(statusLabel(l10n, s)),
                    ),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration:
                    InputDecoration(labelText: l10n.sessionFormLocation),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in SessionMotives.all)
                    FilterChip(
                      label: Text(motiveLabel(l10n, m)),
                      selected: _motives.contains(m),
                      onSelected: (s) => setState(() {
                        if (s) {
                          _motives.add(m);
                        } else {
                          _motives.remove(m);
                        }
                      }),
                    ),
                ],
              ),
              const Divider(height: 32),
              _SectionTitle(l10n.sessionFormSectionPayment),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          InputDecoration(labelText: l10n.sessionFormPrice),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _paymentStatus,
                      decoration: InputDecoration(
                        labelText: l10n.sessionFormPaymentStatus,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        DropdownMenuItem(
                          value: PaymentStatus.unpaid,
                          child: Text(l10n.paymentUnpaid),
                        ),
                        DropdownMenuItem(
                          value: PaymentStatus.paid,
                          child: Text(l10n.paymentPaid),
                        ),
                        DropdownMenuItem(
                          value: PaymentStatus.deposit,
                          child: Text(l10n.paymentDeposit),
                        ),
                        DropdownMenuItem(
                          value: PaymentStatus.free,
                          child: Text(l10n.paymentFree),
                        ),
                      ],
                      onChanged: (v) => setState(() => _paymentStatus = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _paymentMethod,
                decoration: InputDecoration(
                  labelText: l10n.sessionFormPaymentMethod,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  DropdownMenuItem(
                    value: PaymentMethod.cash,
                    child: Text(l10n.methodCash),
                  ),
                  DropdownMenuItem(
                    value: PaymentMethod.card,
                    child: Text(l10n.methodCard),
                  ),
                  DropdownMenuItem(
                    value: PaymentMethod.transfer,
                    child: Text(l10n.methodTransfer),
                  ),
                  DropdownMenuItem(
                    value: PaymentMethod.check,
                    child: Text(l10n.methodCheck),
                  ),
                  DropdownMenuItem(
                    value: PaymentMethod.other,
                    child: Text(l10n.methodOther),
                  ),
                ],
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
              const Divider(height: 32),
              _SectionTitle(l10n.sessionFormSectionReport),
              _reportField(_before, l10n.sessionFormReportBefore),
              _reportField(_client, l10n.sessionFormReportClient),
              _reportField(_observations, l10n.sessionFormReportObservations),
              _reportField(_flow, l10n.sessionFormReportFlow),
              _reportField(_zones, l10n.sessionFormReportZones),
              _reportField(_energetic, l10n.sessionFormReportEnergetic),
              _reportField(_after, l10n.sessionFormReportAfter),
              _reportField(_advice, l10n.sessionFormReportAdvice),
              _reportField(_next, l10n.sessionFormReportNext),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _improvement,
                decoration: InputDecoration(
                  labelText: l10n.sessionFormImprovementLevel,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('—')),
                  DropdownMenuItem(value: 0, child: Text('0 — aucune')),
                  DropdownMenuItem(value: 1, child: Text('1 — légère')),
                  DropdownMenuItem(value: 2, child: Text('2 — moyenne')),
                  DropdownMenuItem(value: 3, child: Text('3 — importante')),
                  DropdownMenuItem(value: 4, child: Text('4 — à suivre')),
                ],
                onChanged: (v) => setState(() => _improvement = v),
              ),
              const Divider(height: 32),
              _SectionTitle(l10n.sessionFormSectionPrivate),
              TextFormField(
                controller: _privateNote,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.sessionFormPrivateNote,
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

  Widget _reportField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
      );

  static String _formatDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
}
