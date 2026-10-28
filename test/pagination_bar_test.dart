import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/ui/components/pagination_bar.dart';

void main() {
  group('paginationItems', () {
    test('shows every page when there are only a few', () {
      expect(paginationItems(page: 1, pageCount: 1), [1]);
      expect(paginationItems(page: 3, pageCount: 5), [1, 2, 3, 4, 5]);
      expect(
        paginationItems(page: 4, pageCount: 7),
        [1, 2, 3, 4, 5, 6, 7],
      );
    });

    test('collapses the far end near the start', () {
      expect(
        paginationItems(page: 1, pageCount: 120),
        [1, 2, 3, 4, 5, null],
      );
      expect(
        paginationItems(page: 3, pageCount: 120),
        [1, 2, 3, 4, 5, null],
      );
    });

    test('collapses both ends in the middle', () {
      expect(
        paginationItems(page: 60, pageCount: 120),
        [1, null, 59, 60, 61, null],
      );
      expect(
        paginationItems(page: 4, pageCount: 120),
        [1, null, 3, 4, 5, null],
      );
    });

    test('collapses the near end near the last page', () {
      expect(
        paginationItems(page: 120, pageCount: 120),
        [1, null, 116, 117, 118, 119, 120],
      );
      expect(
        paginationItems(page: 119, pageCount: 120),
        [1, null, 116, 117, 118, 119, 120],
      );
      // One more step back and the last page hides behind a gap again.
      expect(
        paginationItems(page: 118, pageCount: 120),
        [1, null, 117, 118, 119, null],
      );
    });

    test('stays compact, includes the current page, hides far last page', () {
      for (var page = 1; page <= 40; page++) {
        final items = paginationItems(page: page, pageCount: 40);
        expect(items.length, inInclusiveRange(6, 7), reason: 'page $page');
        expect(items.contains(page), isTrue, reason: 'page $page');
        expect(items.first, 1);
        if (page < 39) expect(items.contains(40), isFalse, reason: 'page $page');
      }
    });

    test('clamps out-of-range input', () {
      expect(paginationItems(page: 0, pageCount: 0), [1]);
      expect(
        paginationItems(page: 999, pageCount: 10),
        [1, null, 6, 7, 8, 9, 10],
      );
    });
  });

  group('PaginationBar', () {
    Widget host({
      required double width,
      required int page,
      int pageCount = 20,
      bool hasNext = true,
      bool busy = false,
      required ValueChanged<int> onPage,
    }) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PaginationBar(
              page: page,
              pageCount: pageCount,
              hasNext: hasNext,
              busy: busy,
              onPageSelected: onPage,
            ),
          ),
        ),
      ),
    );

    testWidgets('previous, next and numbered pages report the page', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        host(width: 640, page: 5, onPage: (p) => picked = p),
      );

      await tester.tap(find.byTooltip('Next page'));
      expect(picked, 6);
      await tester.tap(find.byTooltip('Previous page'));
      expect(picked, 4);
      await tester.tap(find.text('1'));
      expect(picked, 1);
      // The last page number is not shown while far away from it.
      expect(find.text('20'), findsNothing);
    });

    testWidgets('previous is disabled on page 1, next on the last page', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        host(width: 640, page: 1, onPage: (p) => picked = p),
      );
      await tester.tap(find.byTooltip('Previous page'), warnIfMissed: false);
      expect(picked, isNull);

      await tester.pumpWidget(
        host(
          width: 640,
          page: 20,
          hasNext: false,
          onPage: (p) => picked = p,
        ),
      );
      await tester.tap(find.byTooltip('Next page'), warnIfMissed: false);
      expect(picked, isNull);
    });

    testWidgets('every control is inert while a page is loading', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        host(width: 640, page: 5, busy: true, onPage: (p) => picked = p),
      );
      await tester.tap(find.byTooltip('Next page'), warnIfMissed: false);
      await tester.tap(find.text('1'), warnIfMissed: false);
      expect(picked, isNull);
    });

    testWidgets('phones get the compact pill instead of page numbers', (
      tester,
    ) async {
      await tester.pumpWidget(host(width: 360, page: 5, onPage: (_) {}));
      expect(find.text('4'), findsNothing);
      expect(find.text('6'), findsNothing);
      expect(find.byTooltip('Next page'), findsOneWidget);

      await tester.pumpWidget(host(width: 640, page: 5, onPage: (_) {}));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('a gap opens "Go to page" and jumps there', (tester) async {
      int? picked;
      await tester.pumpWidget(
        host(width: 640, page: 5, onPage: (p) => picked = p),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Go to page'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(picked, 12);
      expect(find.text('Go to page'), findsNothing);
    });

    testWidgets('the jump dialog rejects pages that do not exist', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        host(width: 640, page: 5, onPage: (p) => picked = p),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '99');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid page number'), findsOneWidget);
      expect(picked, isNull);
    });
  });
}
