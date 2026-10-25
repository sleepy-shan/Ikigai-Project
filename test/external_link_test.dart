import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/core/utils/external_link.dart';

void main() {
  group('safeExternalUri', () {
    test('accepts https and http links', () {
      expect(safeExternalUri('https://anilist.co/anime/1')?.host, 'anilist.co');
      expect(safeExternalUri('http://example.test/x'), isNotNull);
    });

    test('rejects script, data and relative schemes', () {
      expect(safeExternalUri('javascript:alert(1)'), isNull);
      expect(safeExternalUri('data:text/html,hi'), isNull);
      expect(safeExternalUri('/relative/path'), isNull);
    });

    test('rejects null, empty and unparseable input', () {
      expect(safeExternalUri(null), isNull);
      expect(safeExternalUri('   '), isNull);
      expect(safeExternalUri('https://'), isNull);
    });
  });
}
