import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/services/system_calendar_bridge.dart';
import '../../domain/animal.dart';
import '../../domain/report_template.dart';
import '../../domain/session.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/date_format.dart';
import '../../widgets/busy_helpers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sensitive_text_field.dart';
import '../../widgets/snack_utils.dart';
import '../animals/animal_providers.dart';
import '../clients/client_providers.dart';
import '../templates/templates_l10n.dart';
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
  bool _addToCalendar = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _location = TextEditingController(text: s?.location ?? '');
    _price = TextEditingController(
      text: s?.priceCents == null
          ? ''
          : (s!.priceCents! / 100).toStringAsFixed(2),
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
    // (audit code H1) En création, la case est cochée par défaut pour
    // proposer la sync système. En édition, elle reflète l'état réel :
    // décochée si la séance n'a jamais été liée, cochée sinon. Évite de
    // re-pousser silencieusement un event Calendar non désiré.
    _addToCalendar = s == null ? true : s.externalCalendarEventId != null;
  }

  @override
  void dispose() {
    for (final c in [
      _location,
      _price,
      _before,
      _client,
      _observations,
      _flow,
      _zones,
      _energetic,
      _after,
      _advice,
      _next,
      _privateNote,
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
    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_clientId == null) {
      // v1.7.2 (M5) — snackbar canonique floating + tone erreur.
      showFloatingSnack(
        context,
        l10n.sessionFormSelectClient,
        tone: SnackTone.error,
      );
      return;
    }
    if (!_end.isAfter(_start)) {
      // v1.7.2 (M5) — snackbar canonique floating + tone erreur.
      showFloatingSnack(
        context,
        l10n.sessionFormDurationInvalid,
        tone: SnackTone.error,
      );
      return;
    }

    int? cents;
    final p = _price.text.replaceAll(',', '.').trim();
    if (p.isNotEmpty) {
      final v = double.tryParse(p);
      if (v != null && v >= 0) cents = (v * 100).round();
    }

    // Préserver les IDs calendrier existants pour que le bridge mette à jour
    // l'événement déjà créé plutôt qu'en créer un doublon.
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
      externalCalendarId: widget.initial?.externalCalendarId,
      externalCalendarEventId: widget.initial?.externalCalendarEventId,
    );

    final repo = ref.read(sessionRepositoryProvider);
    final bridge = ref.read(systemCalendarBridgeProvider);
    // Capture avant le premier await pour éviter l'accès à context après gap.
    // v1.7.2 (M5) — capture aussi le ColorScheme pour `buildFloatingSnack`
    // (snackbars canonique floating + couleurs Material 3 tone).
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    await runWithBusy(
      context: context,
      setBusy: (bool v) => setState(() => _busy = v),
      action: () async {
        final Session saved;
        if (widget.initial == null) {
          saved = await repo.create(draft);
        } else {
          saved = await repo.update(draft);
        }

        // Synchronisation agenda — best-effort, ne bloque jamais la sauvegarde.
        if (_addToCalendar) {
          try {
            final title = '${kindLabel(l10n, saved.kind)} – Health Tech';
            final pushed = await bridge.pushSession(
              saved,
              calendarTitle: title,
            );
            if (pushed != null) {
              if (saved.externalCalendarId != pushed.calendarId ||
                  saved.externalCalendarEventId != pushed.eventId) {
                await repo.update(
                  saved.copyWith(
                    externalCalendarId: pushed.calendarId,
                    externalCalendarEventId: pushed.eventId,
                  ),
                );
              }
              // v1.7.2 (M5) — snackbar canonique floating + tone success.
              messenger.showSnackBar(
                buildFloatingSnack(
                  l10n.sessionFormSyncedToCalendar,
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
            // Tout autre échec calendrier (PlatformException du
            // ContentProvider, OEM quirks Samsung, etc.) ne bloque pas
            // la navigation mais on prévient l'utilisateur — sinon il
            // croit que la sync a réussi alors que rien n'est dans
            // l'agenda Android.
            messenger.showSnackBar(
              buildFloatingSnack(
                l10n.sessionDetailAddToCalendarFailed,
                scheme,
                tone: SnackTone.error,
              ),
            );
          }
        } else if (saved.externalCalendarId != null &&
            saved.externalCalendarEventId != null) {
          // Case décochée sur une séance déjà liée : supprime l'événement
          // du calendrier et efface les IDs en base.
          try {
            await bridge.remove(
              calendarId: saved.externalCalendarId!,
              eventId: saved.externalCalendarEventId!,
            );
          } on Object {
            // best-effort : l'événement a peut-être déjà été supprimé manuellement
          }
          await repo.clearCalendarIds(saved.id);
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
    final animals = _clientId == null
        ? const AsyncValue<List<Animal>>.data(<Animal>[])
        : ref.watch(animalsByClientProvider(_clientId!));
    final isEdit = widget.initial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? l10n.sessionFormTitleEdit : l10n.sessionFormTitleNew,
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
              SectionTitle(l10n.sessionFormSectionWho),
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
                  onChanged: (v) => setState(() {
                    _clientId = v;
                    _animalId = null;
                  }),
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.fieldRequired : null,
                ),
              ),
              const SizedBox(height: 12),
              // Dropdown animal : toujours rendue (avant : SizedBox.shrink
              // pendant le loading post-client-change → impression que
              // l'animal "n'apparaît pas"). On utilise valueOrNull pour
              // afficher la dropdown même pendant le loading bref de
              // Drift. Cas vide géré explicitement avec un message
              // d'invitation à créer un animal.
              Builder(
                builder: (context) {
                  final list = animals.valueOrNull ?? const <Animal>[];
                  if (_clientId == null) {
                    return DropdownButtonFormField<String?>(
                      decoration: InputDecoration(
                        labelText: l10n.navAnimals,
                        helperText: l10n.sessionFormPickClientFirst,
                      ),
                      items: const [],
                      onChanged: null,
                    );
                  }
                  if (animals.hasError) {
                    return Text(localiseError(context, animals.error!));
                  }
                  if (animals.isLoading && list.isEmpty) {
                    return DropdownButtonFormField<String?>(
                      decoration: InputDecoration(labelText: l10n.navAnimals),
                      items: const [],
                      onChanged: null,
                    );
                  }
                  return DropdownButtonFormField<String?>(
                    initialValue: _animalId,
                    decoration: InputDecoration(
                      labelText: l10n.navAnimals,
                      helperText: list.isEmpty
                          ? l10n.sessionFormNoAnimalForClient
                          : null,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(l10n.sessionFormNoAnimal),
                      ),
                      for (final a in list)
                        DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(a.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _animalId = v),
                  );
                },
              ),
              const Divider(height: 32),
              SectionTitle(l10n.sessionFormSectionWhen),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.sessionFormStartAt),
                subtitle: Text(formatDateTime(_start)),
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
                subtitle: Text(formatDateTime(_end)),
                trailing: const Icon(Icons.schedule),
                onTap: () => _pickDateTime(
                  context,
                  current: _end,
                  onPicked: (d) => setState(() => _end = d),
                ),
              ),
              const SizedBox(height: 12),
              // (UX v1.5) Toggle agenda promu en Card juste sous le créneau
              // horaire — c'est l'endroit naturel : « ce RDV à telle heure,
              // je le mets dans mon agenda Android pour être averti ? ».
              _CalendarSyncCard(
                value: _addToCalendar,
                onChanged: (v) => setState(() => _addToCalendar = v),
                alreadyLinked: widget.initial?.externalCalendarEventId != null,
              ),
              const Divider(height: 32),
              SectionTitle(l10n.sessionFormSectionType),
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
                decoration: InputDecoration(
                  labelText: l10n.sessionFormLocation,
                ),
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
              SectionTitle(l10n.sessionFormSectionPayment),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.sessionFormPrice,
                      ),
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
              SectionTitle(l10n.sessionFormSectionReport),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _openTemplatePicker,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(l10n.templatesInsertButton),
                ),
              ),
              const SizedBox(height: 12),
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
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  DropdownMenuItem(
                    value: 0,
                    child: Text(l10n.sessionFormImprovement0),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(l10n.sessionFormImprovement1),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(l10n.sessionFormImprovement2),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text(l10n.sessionFormImprovement3),
                  ),
                  DropdownMenuItem(
                    value: 4,
                    child: Text(l10n.sessionFormImprovement4),
                  ),
                ],
                onChanged: (v) => setState(() => _improvement = v),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.sessionFormSectionPrivate),
              SensitiveTextField(
                controller: _privateNote,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.sessionFormPrivateNote,
                ),
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

  /// `true` si au moins un des 9 champs du compte rendu contient déjà du
  /// texte non vide. Sert à décider d'afficher la confirmation de remplace
  /// ment avant d'appliquer un modèle.
  bool _reportHasContent() {
    for (final c in [
      _before,
      _client,
      _observations,
      _flow,
      _zones,
      _energetic,
      _after,
      _advice,
      _next,
    ]) {
      if (c.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Applique un [ReportTemplate] : remplace tous les controllers report
  /// par les valeurs du canevas (les champs absents du canevas sont
  /// vidés — on insère un canevas complet, pas un patch).
  void _applyTemplate(ReportTemplate t) {
    final report = t.toSessionReport();
    setState(() {
      _before.text = report.beforeState;
      _client.text = report.clientPerception;
      _observations.text = report.observations;
      _flow.text = report.flow;
      _zones.text = report.zonesWorked;
      _energetic.text = report.energetic;
      _after.text = report.afterState;
      _advice.text = report.advice;
      _next.text = report.nextRecommendation;
    });
  }

  /// Ouvre le `BottomSheet` de sélection d'un modèle filtré par la séance
  /// courante (`_kind`). Si le compte rendu contient déjà du texte, demande
  /// confirmation avant remplacement.
  Future<void> _openTemplatePicker() async {
    final l10n = AppL10n.of(context);
    final picked = await showModalBottomSheet<ReportTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TemplatePickerSheet(kind: _kind),
    );
    if (picked == null || !mounted) return;
    if (_reportHasContent()) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.templatesInsertConfirmTitle),
          content: Text(l10n.templatesInsertConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.templatesInsertConfirmAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _applyTemplate(picked);
    if (mounted) showSuccessSnack(context, l10n.templatesInserted);
  }

  /// Champs de rapport de séance — données sensibles → SensitiveTextField
  /// pour bloquer le cloud autocomplete des claviers tiers (audit M8).
  Widget _reportField(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SensitiveTextField(
      controller: c,
      maxLines: 3,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

/// BottomSheet de sélection d'un modèle de compte rendu, filtré par
/// `kind` (les templates `other` / `distance` sont toujours inclus côté
/// repository pour rester polyvalents). Affiche un état vide explicite
/// si aucun modèle ne matche.
///
/// Utilise `DraggableScrollableSheet` pour qu'avec 20+ templates la liste
/// soit scrollable proprement sur petit téléphone (audit v1.6.0 U4 — avant :
/// `Flexible + ListView shrinkWrap` ne montait pas plein écran).
class _TemplatePickerSheet extends ConsumerWidget {
  const _TemplatePickerSheet({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final templates = ref.watch(reportTemplatesByKindProvider(kind));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.templatesInsertSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: templates.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(localiseError(context, e)),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return EmptyState(
                          icon: Icons.description_outlined,
                          title: l10n.templatesInsertSheetEmpty,
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = list[i];
                          return ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(t.name),
                            subtitle: Text(
                              reportTemplateKindLabel(l10n, t.kind),
                            ),
                            trailing: t.isSystem
                                ? Icon(
                                    Icons.verified_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(t),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card de promotion claire pour la synchronisation agenda Android.
/// Visuellement plus présente qu'une `CheckboxListTile` au fond de la
/// page : l'utilisateur perçoit l'option dès qu'il a fini de choisir
/// le créneau. Helper text dynamique selon l'état.
class _CalendarSyncCard extends StatelessWidget {
  const _CalendarSyncCard({
    required this.value,
    required this.onChanged,
    required this.alreadyLinked,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool alreadyLinked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final helper = value
        ? (alreadyLinked
              ? l10n.sessionFormCalendarHelperLinked
              : l10n.sessionFormCalendarHelperOn)
        : (alreadyLinked
              ? l10n.sessionFormCalendarHelperWillRemove
              : l10n.sessionFormCalendarHelperOff);
    return Card(
      margin: EdgeInsets.zero,
      color: value ? cs.tertiaryContainer : cs.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: value,
              onChanged: onChanged,
              secondary: Icon(
                value ? Icons.event_available : Icons.event_available_outlined,
                color: value ? cs.onTertiaryContainer : cs.onSurfaceVariant,
              ),
              title: Text(
                l10n.sessionFormCalendarTitle,
                style: textTheme.titleSmall?.copyWith(
                  color: value ? cs.onTertiaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                helper,
                style: textTheme.bodySmall?.copyWith(
                  color: value ? cs.onTertiaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
