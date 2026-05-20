import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/system_calendar_bridge.dart';
import '../../domain/animal.dart';
import '../../domain/appointment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/busy_helpers.dart';
import '../../widgets/confirm_delete_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/sensitive_text_field.dart';
import '../../widgets/snack_utils.dart';
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
  late final TextEditingController _notes;

  /// Reminder presets in minutes. `null` is "no reminder".
  static const List<int?> _reminderPresets = [
    null,
    15,
    30,
    60,
    120,
    1440, // 1 day
  ];
  int? _reminderMinutes;

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
    _reminderMinutes = a?.reminderMinutesBefore;
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
    _notes.dispose();
    super.dispose();
  }

  /// Localised label for a reminder preset. `null` is "no reminder",
  /// `1440` is shown as "1 jour" rather than "1440 min" for readability.
  static String _reminderLabel(AppL10n l10n, int? minutes) {
    if (minutes == null) return l10n.appointmentFormReminderNone;
    if (minutes >= 1440 && minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return l10n.appointmentFormReminderDays(days);
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return l10n.appointmentFormReminderHours(hours);
    }
    return l10n.appointmentFormReminderMinutes(minutes);
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
      // v1.7.2 (M5) — snackbar canonique floating + tone erreur.
      showFloatingSnack(
        context,
        l10n.sessionFormDurationInvalid,
        tone: SnackTone.error,
      );
      return;
    }
    // (audit code M1) le passage à _busy=true est entièrement délégué
    // au `runWithBusy` plus bas, qui le met à true puis le restaure en
    // finally même en cas d'erreur. Le doublon précédent laissait
    // _busy=true si la validation échouait tard.

    final draft = Appointment(
      id: widget.initial?.id ?? '',
      clientId: _clientId,
      animalId: _animalId,
      startAt: _start,
      endAt: _end,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      status: _status,
      reminderMinutesBefore: _reminderMinutes,
      notes: _notes.text,
    );

    final repo = ref.read(appointmentRepositoryProvider);
    final bridge = ref.read(systemCalendarBridgeProvider);
    // v1.7.2 (M5) — capture messenger + scheme avant await pour
    // `buildFloatingSnack` canonique.
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    await runWithBusy(
      context: context,
      setBusy: (bool v) => setState(() => _busy = v),
      action: () async {
        Appointment saved;
        if (widget.initial == null) {
          saved = await repo.create(draft);
        } else {
          saved = await repo.update(draft);
        }
        // Replanifie le rappel local. scheduleFor cancel l'ancienne alarm
        // avant d'en poser une nouvelle.
        try {
          final strings = NotificationStrings.fromL10n(
            channelName: l10n.notifChannelName,
            channelDescription: l10n.notifChannelDescription,
            defaultTitle: l10n.notifDefaultTitle,
            body: l10n.notifBody,
            bodyWithLocation: l10n.notifBodyWithLocation,
          );
          final outcome = await ref
              .read(notificationServiceProvider)
              .scheduleFor(saved, strings);
          // Si le rappel tombait dans le passé, on le dit explicitement à
          // l'utilisateur — sinon il aurait pensé que la notif arriverait
          // et se serait plaint que "le rappel n'a pas marché".
          if (outcome == ScheduleOutcome.skippedPastDue) {
            messenger.showSnackBar(
              buildFloatingSnack(
                l10n.appointmentFormReminderPastDue,
                scheme,
                tone: SnackTone.info,
              ),
            );
          }
        } on Object {
          // Best-effort — un échec de rappel ne doit pas bloquer la sauvegarde.
        }
        // Opt-in: push to (or update in) the system calendar APRÈS que
        // la row soit durable. Le bridge réutilise externalCalendarEventId
        // pour ne pas dupliquer.
        if (_addToSystemCalendar) {
          try {
            final pushed = await bridge.push(saved);
            if (pushed != null) {
              // S'aligne sur le comportement session_form : toujours
              // resynchroniser les IDs si le bridge a (re)résolu un
              // calendarId/eventId différent — sinon un event perdu côté
              // Calendar ne serait jamais ré-épinglé en DB.
              if (saved.externalCalendarId != pushed.calendarId ||
                  saved.externalCalendarEventId != pushed.eventId) {
                await repo.update(
                  saved.copyWith(
                    externalCalendarId: pushed.calendarId,
                    externalCalendarEventId: pushed.eventId,
                  ),
                );
              }
              messenger.showSnackBar(
                buildFloatingSnack(
                  l10n.appointmentFormSyncedToCalendar,
                  scheme,
                  tone: SnackTone.success,
                ),
              );
            }
          } on CalendarPermissionDenied {
            messenger.showSnackBar(
              buildFloatingSnack(
                l10n.appointmentFormCalendarPermissionDenied,
                scheme,
                tone: SnackTone.error,
              ),
            );
          } on CalendarUnavailable {
            messenger.showSnackBar(
              buildFloatingSnack(
                l10n.appointmentFormCalendarMissing,
                scheme,
                tone: SnackTone.error,
              ),
            );
          } on Object {
            // Tout autre échec calendrier ne doit pas bloquer la navigation.
          }
        } else if (saved.externalCalendarId != null &&
            saved.externalCalendarEventId != null) {
          // Case décochée sur un RDV déjà lié : on retire l'event du
          // Calendar Android et on efface les IDs en base (audit code H2,
          // asymétrie session ↔ appointment corrigée).
          await bridge.remove(
            calendarId: saved.externalCalendarId!,
            eventId: saved.externalCalendarEventId!,
          );
          await repo.clearCalendarIds(saved.id);
        }
        if (!mounted) return;
        Navigator.of(context).pop(true);
      },
    );
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final l10n = AppL10n.of(context);
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: l10n.sessionDetailDeleteTitle,
      body: l10n.sessionDetailDeleteBody,
    );
    if (!confirmed || !mounted) return;
    await runWithBusy(
      context: context,
      setBusy: (bool v) => setState(() => _busy = v),
      action: () async {
        // Cascades through PurgeService so the calendar event (if any) is
        // also removed in one go.
        await ref.read(purgeServiceProvider).softDeleteAppointment(initial.id);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      },
    );
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
          if (isEdit)
            IconButton(
              // (audit UI H1) Couleur cs.error pour cohérence sémantique
              // avec les autres écrans détail (action destructive).
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: l10n.actionDelete,
              onPressed: _busy ? null : _delete,
            ),
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
                error: (e, _) => Text(localiseError(context, e)),
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
                  error: (e, _) => Text(localiseError(context, e)),
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
              DropdownButtonFormField<int?>(
                initialValue: _reminderMinutes,
                decoration: InputDecoration(
                  labelText: l10n.appointmentFormReminder,
                  helperText: l10n.appointmentFormReminderHelper,
                ),
                items: [
                  for (final m in _reminderPresets)
                    DropdownMenuItem<int?>(
                      value: m,
                      child: Text(_reminderLabel(l10n, m)),
                    ),
                ],
                onChanged: (v) => setState(() => _reminderMinutes = v),
              ),
              const SizedBox(height: 12),
              SensitiveTextField(
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
                onChanged: (v) =>
                    setState(() => _addToSystemCalendar = v ?? false),
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
