import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/report_template.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/validators.dart';
import '../../widgets/busy_helpers.dart';
import '../../widgets/section_title.dart';
import '../../widgets/snack_utils.dart';
import 'templates_l10n.dart';

/// Crée ou édite un modèle de compte rendu.
///
/// **9 champs** alignés sur `SessionReport` (avant / ressenti client /
/// observations / déroulé / zones / énergétique / après / conseils /
/// prochaine étape) — chacun stocké sous la clé canonique `before`,
/// `client`, ..., `next` dans `sections`.
class ReportTemplateFormScreen extends ConsumerStatefulWidget {
  const ReportTemplateFormScreen({super.key, this.initial});

  final ReportTemplate? initial;

  @override
  ConsumerState<ReportTemplateFormScreen> createState() =>
      _ReportTemplateFormScreenState();
}

class _ReportTemplateFormScreenState
    extends ConsumerState<ReportTemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final Map<String, TextEditingController> _sectionControllers;
  String _kind = ReportTemplateKind.human;
  bool _busy = false;

  /// Ordre canonique des sections + libellé l10n associé. On lit les
  /// libellés directement depuis `sessionFormReport*` pour rester aligné
  /// avec le formulaire de séance — un canevas et la séance qu'il pré-
  /// remplit doivent montrer EXACTEMENT les mêmes étiquettes.
  static const List<String> _sectionKeys = [
    'before',
    'client',
    'observations',
    'flow',
    'zones',
    'energetic',
    'after',
    'advice',
    'next',
  ];

  String _sectionLabel(AppL10n l10n, String key) {
    switch (key) {
      case 'before':
        return l10n.sessionFormReportBefore;
      case 'client':
        return l10n.sessionFormReportClient;
      case 'observations':
        return l10n.sessionFormReportObservations;
      case 'flow':
        return l10n.sessionFormReportFlow;
      case 'zones':
        return l10n.sessionFormReportZones;
      case 'energetic':
        return l10n.sessionFormReportEnergetic;
      case 'after':
        return l10n.sessionFormReportAfter;
      case 'advice':
        return l10n.sessionFormReportAdvice;
      case 'next':
        return l10n.sessionFormReportNext;
      default:
        return key;
    }
  }

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name ?? '');
    _kind = t?.kind ?? ReportTemplateKind.human;
    _sectionControllers = {
      for (final key in _sectionKeys)
        key: TextEditingController(text: t?.sections[key] ?? ''),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _sectionControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(reportTemplateRepositoryProvider);
    // (audit v1.6.0 F10) Le nom du template est cappé à 80 caractères et
    // strip-RTL au save — défense en profondeur contre un `.htbk` forgé
    // ou un copier-coller depuis une source piégée. Les sections sont
    // strip-RTL également (un canevas exporté en PDF doit avoir un rendu
    // visuel non manipulable).
    final cleanedName = HealthValidators.cleanShortLabel(_name.text, max: 80);
    if (cleanedName == null) {
      // En théorie attrapé par le validator du form, mais belt + braces.
      return;
    }
    final sections = <String, String>{
      for (final entry in _sectionControllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: HealthValidators.stripBidiOverrides(entry.value.text),
    };
    final draft = ReportTemplate(
      id: widget.initial?.id ?? '',
      name: cleanedName,
      kind: _kind,
      sections: sections,
      isSystem: widget.initial?.isSystem ?? false,
    );
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
        showSuccessSnack(context, l10n.templatesSaved);
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
          isEdit ? l10n.templatesFormTitleEdit : l10n.templatesFormTitleNew,
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
              SectionTitle(l10n.templatesFormSectionInfo),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                // Cap à 80 caractères : au-delà, le rendu liste + bottom-
                // sheet devient illisible. `HealthValidators.cleanShortLabel`
                // tronque côté save par sécurité même si la saisie remplit
                // exactement 80 chars sans `maxLength` (audit v1.6.0 F10).
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.templatesFormName,
                  counterText: '',
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? l10n.templatesNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(labelText: l10n.templatesFormKind),
                items: [
                  for (final k in ReportTemplateKind.all)
                    DropdownMenuItem(
                      value: k,
                      child: Text(reportTemplateKindLabel(l10n, k)),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const Divider(height: 32),
              SectionTitle(l10n.templatesFormSectionContent),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.templatesFormContentHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final key in _sectionKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _sectionControllers[key],
                    maxLines: 6,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: _sectionLabel(l10n, key),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
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
