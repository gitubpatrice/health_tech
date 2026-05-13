import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../domain/appointment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../sessions/session_l10n.dart';
import 'appointment_form_screen.dart';
import 'appointment_providers.dart';

/// Agenda v0.6: dual-mode (list grouped by day OR monthly calendar grid).
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  bool _monthMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.view_list),
                    label: Text(l10n.agendaViewList),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(l10n.agendaViewMonth),
                  ),
                ],
                selected: {_monthMode},
                onSelectionChanged: (s) => setState(() => _monthMode = s.first),
              ),
            ),
            Expanded(
              child: _monthMode ? const _MonthView() : const _ListView(),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-appointment',
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => const AppointmentFormScreen(),
                fullscreenDialog: true,
              ),
            ),
            icon: const Icon(Icons.event_available),
            label: Text(l10n.actionAdd),
          ),
        ),
      ],
    );
  }
}

class _ListView extends ConsumerWidget {
  const _ListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final upcoming = ref.watch(upcomingAppointmentsProvider);
    return upcoming.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.event_busy_outlined,
              title: l10n.agendaEmpty,
            )
          : _GroupedByDay(appointments: list),
    );
  }
}

class _MonthView extends ConsumerStatefulWidget {
  const _MonthView();

  @override
  ConsumerState<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<_MonthView> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  /// Cache des regroupements par jour. Recalculé uniquement quand la
  /// référence de la liste source change (Drift renvoie une nouvelle
  /// instance à chaque émission). Évite le O(N×42) lorsque
  /// `TableCalendar.eventLoader` est appelé une fois par case visible
  /// (audit perf C1).
  List<Appointment>? _cacheSource;
  Map<DateTime, List<Appointment>> _cacheGroups = const {};

  Map<DateTime, List<Appointment>> _groupsFor(List<Appointment> all) {
    if (identical(_cacheSource, all)) return _cacheGroups;
    final groups = <DateTime, List<Appointment>>{};
    for (final a in all) {
      // Un RDV peut chevaucher plusieurs jours : on l'indexe sur chaque
      // jour qu'il touche, du jour de début (00:00) jusqu'au jour de
      // fin exclusif. Sécurise un futur RDV qui couvrirait une nuit.
      final dayStart = DateTime(a.startAt.year, a.startAt.month, a.startAt.day);
      final dayEnd = DateTime(a.endAt.year, a.endAt.month, a.endAt.day);
      var cursor = dayStart;
      while (!cursor.isAfter(dayEnd)) {
        groups.putIfAbsent(cursor, () => <Appointment>[]).add(a);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    _cacheSource = all;
    _cacheGroups = groups;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // Wide window (-6 → +12 months) so the dot markers are populated.
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 6, 1);
    final to = DateTime(now.year, now.month + 12, 1);
    final stream = ref.watch(appointmentsRangeProvider((from: from, to: to)));
    return stream.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (all) {
        final groups = _groupsFor(all);
        final selectedKey = DateTime(
          _selected.year,
          _selected.month,
          _selected.day,
        );
        final dayItems = groups[selectedKey] ?? const <Appointment>[];
        List<Appointment> eventsFor(DateTime d) =>
            groups[DateTime(d.year, d.month, d.day)] ?? const <Appointment>[];
        return Column(
          children: [
            TableCalendar<Appointment>(
              firstDay: DateTime(now.year - 5, 1, 1),
              lastDay: DateTime(now.year + 5, 12, 31),
              focusedDay: _focused,
              selectedDayPredicate: (d) => isSameDay(d, _selected),
              eventLoader: eventsFor,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: {
                CalendarFormat.month: l10n.agendaViewMonth,
              },
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: CalendarStyle(
                markersMaxCount: 4,
                // markerDecoration sert de fallback pour les vues qui ne
                // passent pas par `calendarBuilders.markerBuilder`.
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders<Appointment>(
                // (audit UI M7) Couleur du marker par AppointmentStatus :
                // l'utilisateur perçoit d'un coup d'œil l'état de chaque
                // RDV de la grille mensuelle. Annulé / no_show = teinte
                // erreur, planned = primary, confirmed = tertiary,
                // done = outlineVariant atténué.
                markerBuilder: (ctx, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  final cs = Theme.of(ctx).colorScheme;
                  final dots = events.take(4).map((a) {
                    final color = _markerColorFor(a.status, cs);
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    );
                  }).toList();
                  return Positioned(
                    bottom: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: dots,
                    ),
                  );
                },
              ),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selected = selected;
                  _focused = focused;
                });
              },
              onPageChanged: (f) => _focused = f,
            ),
            const Divider(height: 1),
            Expanded(
              child: dayItems.isEmpty
                  ? EmptyState(
                      icon: Icons.event_note_outlined,
                      title: l10n.agendaSelectedDayEmpty,
                    )
                  : ListView.separated(
                      itemCount: dayItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) =>
                          _AppointmentTile(appointment: dayItems[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Mapping (status → couleur du marker) — concentré ici pour rester
/// cohérent avec `sessions_screen._statusColor` (même palette
/// sémantique cross-app). Si on ajoute un nouveau status dans
/// `AppointmentStatus.all`, il tombera ici en `primary` par défaut.
Color _markerColorFor(String status, ColorScheme cs) {
  switch (status) {
    case AppointmentStatus.cancelled:
    case AppointmentStatus.noShow:
      return cs.error;
    case AppointmentStatus.confirmed:
      return cs.tertiary;
    case AppointmentStatus.done:
      return cs.outline;
    case AppointmentStatus.planned:
    default:
      return cs.primary;
  }
}

class _GroupedByDay extends StatelessWidget {
  const _GroupedByDay({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<Appointment>>{};
    for (final a in appointments) {
      final key = DateTime(a.startAt.year, a.startAt.month, a.startAt.day);
      groups.putIfAbsent(key, () => <Appointment>[]).add(a);
    }
    final orderedKeys = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: orderedKeys.length,
      itemBuilder: (_, i) {
        final day = orderedKeys[i];
        return _DaySection(day: day, items: groups[day]!);
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.items});
  final DateTime day;
  final List<Appointment> items;

  bool get _isToday {
    final now = DateTime.now();
    return now.year == day.year && now.month == day.month && now.day == day.day;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                _isToday ? l10n.agendaToday : _formatDay(day, context),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_isToday) ...[
                const SizedBox(width: 8),
                Icon(Icons.today, size: 16, color: scheme.primary),
              ],
            ],
          ),
        ),
        for (final a in items) _AppointmentTile(appointment: a),
        const Divider(height: 1),
      ],
    );
  }

  static String _formatDay(DateTime d, BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final weekday = DateFormat.E(locale).format(d).toLowerCase();
    return '$weekday ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _AppointmentTile extends ConsumerWidget {
  const _AppointmentTile({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return ListTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatTime(appointment.startAt),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            formatTime(appointment.endAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
      title: Text(appointment.title ?? '—'),
      subtitle: Text(
        [
          if (appointment.location != null && appointment.location!.isNotEmpty)
            appointment.location,
          statusLabel(l10n, appointment.status),
        ].whereType<String>().join(' · '),
      ),
      onTap: () => Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AppointmentFormScreen(initial: appointment),
          fullscreenDialog: true,
        ),
      ),
    );
  }
}
