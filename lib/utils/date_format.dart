/// Stable, locale-agnostic formatters for the UI.
///
/// We deliberately avoid `intl.DateFormat` for these short strings so they
/// stay identical across the FR and EN UIs (a date in a list isn't a
/// translatable string — only the surrounding labels are).
library;

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

String formatDateTime(DateTime d) => '${formatDate(d)} ${formatTime(d)}';

/// Compact day+month form (e.g. for list rows where the year is implicit).
String formatDayMonth(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}';

/// Bytes → "12 B" / "12 KB" / "12.3 MB". Locale-independent.
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
