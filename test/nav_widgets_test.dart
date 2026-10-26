import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/state/providers.dart';
import 'package:ikigai_project/state/settings_controller.dart';
import 'package:ikigai_project/ui/components/theme_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> seed = const {},
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ),
  );
  return container;
}

void main() {
  testWidgets('ThemeSwitch shows a moon in dark mode and flips to a sun', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const ThemeSwitch(),
      seed: {'ikigai.theme': 'dark'},
    );
    expect(find.byIcon(Icons.nightlight_round), findsOne);

    await tester.tap(find.byType(ThemeSwitch));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.wb_sunny_rounded), findsOne);
    expect(container.read(settingsControllerProvider), ThemePreference.light);
  });

  testWidgets('ThemeSwitch flips back from light to dark', (tester) async {
    final container = await _pump(
      tester,
      const ThemeSwitch(compact: true),
      seed: {'ikigai.theme': 'light'},
    );
    expect(find.byIcon(Icons.wb_sunny_rounded), findsOne);

    await tester.tap(find.byType(ThemeSwitch));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.nightlight_round), findsOne);
    expect(container.read(settingsControllerProvider), ThemePreference.dark);
  });

  test('sidebar starts collapsed and the choice persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(sidebarCollapsedProvider), isTrue);
    await container.read(sidebarCollapsedProvider.notifier).toggle();
    expect(container.read(sidebarCollapsedProvider), isFalse);
    expect(prefs.getBool('ikigai.sidebar.collapsed'), isFalse);
  });
}
