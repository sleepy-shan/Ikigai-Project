import 'package:intl/intl.dart';

/// Presentation helpers shared by the UI layer.
abstract final class Formatters {
  static final DateFormat _clockFormat = DateFormat('h:mm a');

  /// Local wall-clock time on a 12-hour clock: "8:30 PM" (never 20:30).
  static String clockTime(DateTime time) => _clockFormat.format(time);

  /// "2026-10-10" -> "Oct 10, 2026"; falls back to [fallback] when absent.
  static String date(String? isoDate, {String fallback = 'Unknown'}) {
    if (isoDate == null || isoDate.isEmpty) return fallback;
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final date = DateTime.tryParse(isoDate);
    if (date == null) return fallback;
    return DateFormat('MMM d, y').format(date);
  }

  /// "Oct 10" — used in the calendar strip.
  static String shortDate(String? isoDate) {
    final date = isoDate == null ? null : DateTime.tryParse(isoDate);
    if (date == null) return 'TBA';
    return DateFormat('MMM d').format(date);
  }

  /// Epoch seconds -> "in 3 days" / "2 hours ago".
  static String timeUntil(int? epochSeconds) {
    if (epochSeconds == null) return '';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = epochSeconds - now;
    if (diff <= 0) return 'now';
    final days = diff ~/ 86400;
    if (days >= 1) return 'in $days ${days == 1 ? 'day' : 'days'}';
    final hours = diff ~/ 3600;
    if (hours >= 1) return 'in $hours ${hours == 1 ? 'hour' : 'hours'}';
    final minutes = diff ~/ 60;
    return 'in $minutes ${minutes == 1 ? 'min' : 'mins'}';
  }

  /// 7.86 -> "7.9" for AniList average scores (0-100 scale shown as-is).
  static String score(int? averageScore) =>
      averageScore == null || averageScore == 0
      ? '—'
      : (averageScore / 10).toStringAsFixed(1);

  /// "3h ago" / "just now" for a past [DateTime].
  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    final months = diff.inDays ~/ 30;
    if (months < 12) return '${months}mo ago';
    return '${diff.inDays ~/ 365}y ago';
  }

  /// 123456 -> "123K".
  static String compactNumber(int? value) {
    if (value == null) return '—';
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toString();
  }

  /// Strips AniList's HTML-ish description markup for plain display.
  static String cleanDescription(String? html) {
    if (html == null || html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        // Collapse repeated spaces left behind by removed markup.
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }
}
