import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/core/theme/app_scroll.dart';

void main() {
  Widget item(Object key) => Directionality(
        textDirection: TextDirection.ltr,
        child: RevealOnScroll(
          index: 3, // staggered: starts hidden, then fades in
          revealKey: key,
          child: const SizedBox(width: 10, height: 10),
        ),
      );

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('first appearance fades in', (tester) async {
    await tester.pumpWidget(item('reveal-test-first'));
    expect(opacity(tester), 0.0);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1.0);
  });

  testWidgets('an item that was already revealed does not replay', (
    tester,
  ) async {
    await tester.pumpWidget(item('reveal-test-again'));
    await tester.pumpAndSettle();

    // Scrolled out of view (disposed), then back in.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(item('reveal-test-again'));
    expect(opacity(tester), 1.0);
  });
}
