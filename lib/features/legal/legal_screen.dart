import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';

enum LegalDoc { cgs, privacy, mentions }

class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.legalScreenTitle),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.legalDocCgs),
              Tab(text: l10n.legalDocPrivacy),
              Tab(text: l10n.legalDocMentions),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LegalDocView(doc: LegalDoc.cgs),
            _LegalDocView(doc: LegalDoc.privacy),
            _LegalDocView(doc: LegalDoc.mentions),
          ],
        ),
      ),
    );
  }
}

class _LegalDocView extends StatelessWidget {
  const _LegalDocView({required this.doc});
  final LegalDoc doc;

  String _assetPath(Locale locale) {
    final lang = locale.languageCode == 'fr' ? 'fr' : 'en';
    final base = switch (doc) {
      LegalDoc.cgs => 'cgs',
      LegalDoc.privacy => 'privacy',
      LegalDoc.mentions => 'mentions_legales',
    };
    return 'assets/legal/${base}_$lang.md';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(_assetPath(Localizations.localeOf(context))),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorView(error: snap.error!);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _MarkdownView(source: snap.data ?? ''),
        );
      },
    );
  }
}

/// Minimal markdown renderer covering only the syntax used in
/// `assets/legal/*.md`: ATX headings (# ## ###), paragraphs, blockquotes
/// (`> `), bullets (`- `), inline `**bold**`, `_italic_`, and `[text](url)`
/// links. Anything else is rendered as plain text. Selectable so users can
/// copy clauses verbatim.
class _MarkdownView extends StatelessWidget {
  const _MarkdownView({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = <Widget>[];
    final lines = source.split('\n');

    final paragraph = StringBuffer();
    void flushParagraph() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText.rich(
            _inline(text, theme.textTheme.bodyMedium!),
          ),
        ),
      );
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }
      if (line.startsWith('### ')) {
        flushParagraph();
        blocks.add(_heading(line.substring(4), theme.textTheme.titleSmall!));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        blocks.add(_heading(line.substring(3), theme.textTheme.titleMedium!));
      } else if (line.startsWith('# ')) {
        flushParagraph();
        blocks.add(_heading(line.substring(2), theme.textTheme.headlineSmall!));
      } else if (line.startsWith('> ')) {
        flushParagraph();
        blocks.add(_blockquote(context, line.substring(2)));
      } else if (line.startsWith('- ')) {
        flushParagraph();
        blocks.add(_bullet(line.substring(2), theme.textTheme.bodyMedium!));
      } else {
        if (paragraph.isNotEmpty) paragraph.write(' ');
        paragraph.write(line);
      }
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget _heading(String text, TextStyle style) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: SelectableText.rich(_inline(text, style)),
  );

  Widget _bullet(String text, TextStyle style) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: style),
        Expanded(child: SelectableText.rich(_inline(text, style))),
      ],
    ),
  );

  Widget _blockquote(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText.rich(
        _inline(text, Theme.of(context).textTheme.bodyMedium!),
      ),
    );
  }

  /// Tokenises a single inline run for `**bold**`, `_italic_`, `[t](u)`.
  /// Order matters: links first (greediest), then bold, then italic.
  TextSpan _inline(String text, TextStyle base) {
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'\*\*([^*]+)\*\*|_([^_\n]+)_|\[([^\]]+)\]\(([^)]+)\)',
    );
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
        );
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return TextSpan(children: spans);
  }
}
