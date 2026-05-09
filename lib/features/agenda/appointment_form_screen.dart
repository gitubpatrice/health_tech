import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/services/system_calendar_bridge.dart';
import '../../domain/animal.dart';
import '../../domain/appointment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../animals/animal_providers.dart';
import '../clients/client_providers.dart';
import '../sessions/session_l10n.dart';

class AppointmentFormScreen extends ConsumerStatefulWidget {
  const AppointmentFormScreen({
    super.key,
    this.initial,
    this.defaultClientId,
    this.defaultStart,
  });

  final Appointment? initial;
  final String? defaultClientId;
  final DateTime? defaultStart;

  @override
  ConsumerState<AppointmentFormScreen> createState() =>
      _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends ConsumerState<AppointmentFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _reminder;
  late final TextEditingController _notes;

  String? _clientId;
  String? _animalId;
  late DateTime _start;
  late DateTime _end;
  String _status = AppointmentStatus.planned;
  bool _addToSystemCalendar = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _title = TextEditingController(text: a?.title ?? '');
    _location = TextEditingController(text: a?.location ?? '');
    _reminder = TextEditingController(
      text: a?.reminderMinutesBefore?.toString() ?? '',
    );
    _notes = TextEditingController(text: a?.notes ?? '');
    _clientId = a?.clientId ?? widget.defaultClientId;
    _animalId = a?.animalId;
    _start =
        a?.startAt ??
        widget.defaultStart ??
        _roundToNextHalfHour(DateTime.now());
    _end = a?.endAt ?? _start.add(const Duration(hours: 1));
    _status = a?.status ?? AppointmentStatus.planned;
    _addToSystemCalendar = a?.externalCalendarEventId != null;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _reminder.dispose();
    _notes.dispose();
    super.dispose();
  }

  static DateTime _roundToNextHalfHour(DateTime now) {
    final minutes = (now.minute < 30 ? 30 : 60);
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(Duration(minutes: minutes));
  }

  Future<void> _pickDateTime({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sessionFormDurationInvalid)));
      return;
    }
    setState(() => _busy = true);

    final draft = Appointment(
      id: widget.initial?.id ?? '',
      clientId: _clientId,
      animalId: _animalId,
      startAt: _start,
      endAt: _end,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      status: _status,
      reminderMinutesBefore: int.tryParse(_reminder.text.trim()),
      notes: _notes.text,
    );

    final repo = ref.read(appointmentRepositoryProvider);
    final bridge = ref.read(systemCalendarBridgeProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      Appointment saved;
      if (widget.initial == null) {
        saved = await repo.create(draft);
      } else {
        saved = await repo.update(draft);
      }
      // Opt-in: push to system calendar AFTER the row is durable, then
      // persist the returned event ids on the row so a future edit knows
      // it can update / remove the system event.
      if (_addToSystemCalendar && saved.externalCalendarEventId == null) {
        try {
          final pushed = await bridge.push(saved);
          if (pushed != null) {
            await repo.update(
              saved.copyWith(
                externalCalendarId: pushed.calendarId,
                externalCalendarEventId: pushed.eventId,
              ),
            );
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.appointmentFormSyncedToCalendar)),
            );
          }
        } on CalendarPermissionDenied {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.appointmentFormCalendarPermissionDenied),
            ),
          );
        } on CalendarUnavailable {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.appointmentFormCalendarMissing)),
          );
        }
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
        title: Text(
          isEdit ? l10n.appointmentFormTitleEdit : l10n.appointmentFormTitleNew,
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
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.appointmentFormTitle,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.appointmentFormStartAt),
                subtitle: Text(formatDateTime(_start)),
                trailing: const Icon(Icons.schedule),
                onTap: () => _pickDateTime(
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
                title: Text(l10n.appointmentFormEndAt),
                subtitle: Text(formatDateTime(_end)),
                trailing: const Icon(Icons.schedule),
                onTap: () => _pickDateTime(
                  current: _end,
                  onPicked: (d) => setState(() => _end = d),
                ),
              ),
              const SizedBox(height: 12),
              clients.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (list) => DropdownButtonFormField<String?>(
                  initialValue: _clientId,
                  decoration: InputDecoration(labelText: l10n.animalFormClient),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('—'),
                    ),
                    for (final c in list)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.fullName),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _clientId = v;
                    _animalId = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              if (_clientId != null)
                animals.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text('$e'),
                  data: (list) => DropdownButtonFormField<String?>(
                    initialValue: _animalId,
                    decoration: InputDecoration(labelText: l10n.navAnimals),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('—'),
                      ),
                      for (final a in list)
                        DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(a.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _animalId = v),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: InputDecoration(
                  labelText: l10n.appointmentFormLocation,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.sessionFormStatus),
                items: [
                  for (final s in AppointmentStatus.all)
                    DropdownMenuItem(
                      value: s,
                      child: Text(statusLabel(l10n, s)),
                    ),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reminder,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.appointmentFormReminder,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.appointmentFormNotes,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _addToSystemCalendar,
                onChanged: widget.initial?.externalCalendarEventId != null
                    ? null // already synced — read-only for this iteration
                    : (v) => setState(() => _addToSystemCalendar = v ?? false),
                title: Text(l10n.appointmentFormAddToCalendar),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
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
