import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/report_template.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/snack_utils.dart';
import 'report_template_form_screen.dart';
import 'templates_l10n.dart';

/// Liste des modèles de comptes rendus (Réglages → Modèles).
///
/// Tap = édition. Long-press / menu kebab = dupliquer / supprimer (avec
/// confirmation). Un badge « Système » s'affiche sur les canevas livrés
/// par l'app — l'utilisateur peut les supprimer ou les dupliquer pour
/// les modifier sans perdre l'original.
class ReportTemplatesScreen extends ConsumerWidget {
  const ReportTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final templates = ref.watch(allReportTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.templatesScreenTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        tooltip: l10n.actionAdd,
        child: const Icon(Icons.add),
      ),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: l10n.templatesEmpty,
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _TemplateTile(
              template: list[i],
              onEdit: () => _openForm(context, initial: list[i]),
              onDuplicate: () => _duplicate(context, ref, list[i]),
              onDelete: () => _delete(context, ref, list[i]),
            ),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, {ReportTemplate? initial}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReportTemplateFormScreen(initial: initial),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    ReportTemplate t,
  ) async {
    final l10n = AppL10n.of(context);
    final repo = ref.read(reportTemplateRepositoryProvider);
    final copy = t.copyWith(
      id: '',
      name: '${t.name} ${l10n.templatesDuplicateSuffix}',
      isSystem: false,
    );
    try {
      await repo.create(copy);
      if (context.mounted) {
        showSuccessSnack(context, l10n.templatesDuplicated);
      }
    } on Object catch (e) {
      if (context.mounted) showLocalisedErrorSnack(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ReportTemplate t,
  ) async {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.templatesDeleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.templatesDeleteBody),
            if (t.isSystem) ...[
              const SizedBox(height: 12),
              Text(
                l10n.templatesDeleteSystemHint,
                style: Theme.of(
                  ctx,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(reportTemplateRepositoryProvider);
    try {
      await repo.delete(t.id);
      if (context.mounted) {
        showSuccessSnack(context, l10n.templatesDeleted);
      }
    } on Object catch (e) {
      if (context.mounted) showLocalisedErrorSnack(context, e);
    }
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ReportTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Row(
        children: [
          Expanded(child: Text(template.name)),
          if (template.isSystem) ...[
            const SizedBox(width: 8),
            _SystemBadge(label: l10n.templatesSystemBadge, scheme: cs),
          ],
        ],
      ),
      subtitle: Text(reportTemplateKindLabel(l10n, template.kind)),
      trailing: PopupMenuButton<_TemplateAction>(
        tooltip: l10n.actionEdit,
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _TemplateAction.edit:
              onEdit();
            case _TemplateAction.duplicate:
              onDuplicate();
            case _TemplateAction.delete:
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _TemplateAction.edit,
            child: Row(
              children: [
                const Icon(Icons.edit_outlined),
                const SizedBox(width: 8),
                Text(l10n.actionEdit),
              ],
            ),
          ),
          PopupMenuItem(
            value: _TemplateAction.duplicate,
            child: Row(
              children: [
                const Icon(Icons.copy_outlined),
                const SizedBox(width: 8),
                Text(l10n.templatesActionDuplicate),
              ],
            ),
          ),
          PopupMenuItem(
            value: _TemplateAction.delete,
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: cs.error),
                const SizedBox(width: 8),
                Text(
                  l10n.templatesActionDelete,
                  style: TextStyle(color: cs.error),
                ),
              ],
            ),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}

enum _TemplateAction { edit, duplicate, delete }

class _SystemBadge extends StatelessWidget {
  const _SystemBadge({required this.label, required this.scheme});
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
    ),
  );
}
