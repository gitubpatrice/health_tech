import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/client.dart';
import '../../domain/session.dart';
import '../../utils/date_format.dart';

/// Strings injected by the caller (UI layer) so the exporter stays
/// independent from Flutter / l10n.
class PdfStrings {
  const PdfStrings({
    required this.title,
    required this.clientLine,
    required this.dateLine,
    required this.durationLine,
    required this.motivesLine,
    required this.disclaimer,
    required this.sectionReport,
    required this.before,
    required this.client,
    required this.observations,
    required this.flow,
    required this.zones,
    required this.energetic,
    required this.after,
    required this.advice,
    required this.next,
    required this.motivesByKey,
  });

  final String title;
  final String clientLine;
  final String dateLine;
  final String durationLine;
  final String motivesLine;
  final String disclaimer;
  final String sectionReport;
  final String before;
  final String client;
  final String observations;
  final String flow;
  final String zones;
  final String energetic;
  final String after;
  final String advice;
  final String next;
  final Map<String, String> motivesByKey;
}

/// Renders a one-pager PDF for a session. Excludes the practitioner private
/// note by design (never exported).
class SessionPdfExporter {
  const SessionPdfExporter();

  Future<Uint8List> render({
    required Session session,
    required Client client,
    required PdfStrings s,
  }) async {
    final doc = pw.Document(
      title: s.title,
      author: 'Health Tech',
      creator: 'Health Tech',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _header(s.title),
          pw.SizedBox(height: 16),
          _meta(s, session, client),
          pw.SizedBox(height: 16),
          if (session.motives.isNotEmpty) ...[
            _line(s.motivesLine,
                session.motives.map((k) => s.motivesByKey[k] ?? k).join(' · ')),
            pw.SizedBox(height: 12),
          ],
          if (!session.report.isEmpty)
            _reportBlock(session, s),
          pw.Spacer(),
          pw.Divider(),
          pw.Text(
            s.disclaimer,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _header(String title) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400),
          ),
        ),
        child: pw.Text(
          title,
          style:
              pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget _meta(PdfStrings s, Session session, Client client) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _line(s.clientLine, client.fullName),
        _line(s.dateLine, formatDateTime(session.startAt)),
        _line(s.durationLine, _formatDuration(session.duration)),
      ],
    );
  }

  pw.Widget _reportBlock(Session session, PdfStrings s) {
    final r = session.report;
    final entries = <(String, String)>[
      if (r.beforeState.isNotEmpty) (s.before, r.beforeState),
      if (r.clientPerception.isNotEmpty) (s.client, r.clientPerception),
      if (r.observations.isNotEmpty) (s.observations, r.observations),
      if (r.flow.isNotEmpty) (s.flow, r.flow),
      if (r.zonesWorked.isNotEmpty) (s.zones, r.zonesWorked),
      if (r.energetic.isNotEmpty) (s.energetic, r.energetic),
      if (r.afterState.isNotEmpty) (s.after, r.afterState),
      if (r.advice.isNotEmpty) (s.advice, r.advice),
      if (r.nextRecommendation.isNotEmpty) (s.next, r.nextRecommendation),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          s.sectionReport,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        for (final e in entries) ...[
          pw.Text(
            e.$1,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(e.$2, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
        ],
      ],
    );
  }

  pw.Widget _line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label : ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(text: value),
            ],
          ),
        ),
      );

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    return '${m}min';
  }
}
