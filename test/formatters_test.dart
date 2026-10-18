import 'package:ikigai_project/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters', () {
    test('score divides the AniList 0-100 scale', () {
      expect(Formatters.score(86), '8.6');
      expect(Formatters.score(0), '—');
      expect(Formatters.score(null), '—');
    });

    test('clockTime uses a 12-hour clock', () {
      final evening = Formatters.clockTime(DateTime(2026, 10, 18, 20, 5));
      final morning = Formatters.clockTime(DateTime(2026, 10, 18, 0, 30));
      expect(evening, contains('8:05'));
      expect(evening, contains('PM'));
      expect(morning, contains('12:30'));
      expect(morning, contains('AM'));
    });

    test('compactNumber abbreviates large values', () {
      expect(Formatters.compactNumber(999), '999');
      expect(Formatters.compactNumber(1500), '2K');
      expect(Formatters.compactNumber(2500000), '2.5M');
    });

    test('date handles ISO strings and garbage', () {
      expect(Formatters.date('2026-10-01'), 'Oct 1, 2026');
      expect(Formatters.date(null), 'Unknown');
      expect(Formatters.date(''), 'Unknown');
      expect(Formatters.date('soon'), 'soon');
    });

    test('cleanDescription strips simple HTML', () {
      expect(
        Formatters.cleanDescription('Hi<br>there <b>bold</b> &amp; done'),
        'Hi\nthere bold & done',
      );
      expect(Formatters.cleanDescription(null), '');
    });

    test('timeAgo reports human-friendly durations', () {
      final now = DateTime.now();
      expect(Formatters.timeAgo(now), 'just now');
      expect(
        Formatters.timeAgo(now.subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        Formatters.timeAgo(now.subtract(const Duration(days: 2))),
        '2d ago',
      );
    });

    test('timeUntil reports future durations', () {
      final soon = DateTime.now().add(const Duration(minutes: 5));
      expect(
        Formatters.timeUntil(soon.millisecondsSinceEpoch ~/ 1000),
        'in 5 mins',
      );
      final later = DateTime.now().add(const Duration(days: 2));
      expect(
        Formatters.timeUntil(later.millisecondsSinceEpoch ~/ 1000),
        'in 2 days',
      );
      expect(Formatters.timeUntil(null), '');
    });
  });
}

