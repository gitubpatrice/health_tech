import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/providers.dart';
import '../../data/services/session_pdf_exporter.dart';
import '../../domain/attachment.dart';
import '../../domain/session.dart';
import '../../domain/tag.dart';
import '../../l10n/generated/app_localizations.dart';
import '../attachments/attachments_section.dart';
import '../tags/tag_editor.dart';
import 'session_form_screen.dart';
import 'session_l10n.dart';
import 'session_providers.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final selected = ref.watch(selectedSessionProvider);
    return selected.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (s) => s == null
          ? Center(child: Text(l10n.sessionDetailNoSelection))
          : _SessionBody(session: s),
    );
  }
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({required this.session});
  final Session session;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SessionFormScreen(initial: session),
        fullscreenDialog: true,
      ),
    );
    if (updated == true) ref.invalidate(selectedSessionProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sessionDetailDeleteTitle),
        content: Text(l10n.sessionDetailDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(sessionRepositoryProvider).softDelete(session.id);
    ref.read(selectedSessionIdProvider.notifier).state = null;
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final repo = ref.read(clientRepositoryProvider);
    final client = await repo.getById(session.clientId);
    if (client == null || !context.mounted) return;
    final strings = PdfStrings(
      title: l10n.exportPdfHeader,
      clientLine: l10n.exportPdfClientLine,
      dateLine: l10n.exportPdfDateLine,
      durationLine: l10n.exportPdfDurationLine,
      motivesLine: l10n.exportPdfMotivesLine,
      disclaimer: l10n.exportPdfDisclaimer,
      sectionReport: l10n.sessionFormSectionReport,
      before: l10n.sessionFormReportBefore,
      client: l10n.sessionFormReportClient,
      observations: l10n.sessionFormReportObservations,
      flow: l10n.sessionFormReportFlow,
      zones: l10n.sessionFormReportZones,
      energetic: l10n.sessionFormReportEnergetic,
      after: l10n.sessionFormReportAfter,
      advice: l10n.sessionFormReportAdvice,
      next: l10n.sessionFormReportNext,
      motivesByKey: {
        for (final m in session.motives) m: motiveLabel(l10n, m),
      },
    );
    final bytes = await const SessionPdfExporter()
        .render(session: session, client: client, s: strings);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'session-${session.id}.pdf',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_formatDate(session.startAt)),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: l10n.exportPdfButton,
              onPressed: () => _exportPdf(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.info_outline), text: l10n.tabInfo),
              Tab(
                icon: const Icon(Icons.attach_file),
                text: l10n.tabAttachments,
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInfoTab(context, l10n),
            AttachmentsSection(
              ownerType: AttachmentOwner.session,
              ownerId: session.id,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab(BuildContext context, AppL10n l10n) {
    final r = session.report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
          TagEditor(
            ownerType: TagOwner.session,
            ownerId: session.id,
          ),
          const SizedBox(height: 12),
          _row(Icons.schedule,
              '${_formatTime(session.startAt)} – ${_formatTime(session.endAt)}'),
          _row(Icons.category_outlined, kindLabel(l10n, session.kind)),
          _row(Icons.flag_outlined, statusLabel(l10n, session.status)),
          if (session.location != null && session.location!.isNotEmpty)
            _row(Icons.place_outlined, session.location!),
          if (session.priceCents != null)
            _row(
              Icons.euro,
              '${(session.priceCents! / 100).toStringAsFixed(2)} € · '
              '${paymentStatusLabel(l10n, session.paymentStatus)}',
            ),
          if (session.motives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in session.motives)
                  Chip(label: Text(motiveLabel(l10n, m))),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (!r.isEmpty)
            _Section(
              title: l10n.sessionFormSectionReport,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.beforeState.isNotEmpty)
                    _block(l10n.sessionFormReportBefore, r.beforeState),
                  if (r.clientPerception.isNotEmpty)
                    _block(l10n.sessionFormReportClient, r.clientPerception),
                  if (r.observations.isNotEmpty)
                    _block(
                        l10n.sessionFormReportObservations, r.observations),
                  if (r.flow.isNotEmpty)
                    _block(l10n.sessionFormReportFlow, r.flow),
                  if (r.zonesWorked.isNotEmpty)
                    _block(l10n.sessionFormReportZones, r.zonesWorked),
                  if (r.energetic.isNotEmpty)
                    _block(l10n.sessionFormReportEnergetic, r.energetic),
                  if (r.afterState.isNotEmpty)
                    _block(l10n.sessionFormReportAfter, r.afterState),
                  if (r.advice.isNotEmpty)
                    _block(l10n.sessionFormReportAdvice, r.advice),
                  if (r.nextRecommendation.isNotEmpty)
                    _block(l10n.sessionFormReportNext, r.nextRecommendation),
                ],
              ),
            ),
          if (session.privateNote.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: l10n.sessionFormSectionPrivate,
              child: Text(session.privateNote),
            ),
          ],
        ],
      );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _block(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      );

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
}
