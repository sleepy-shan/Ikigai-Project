import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_scroll.dart';
import 'core/theme/app_theme.dart';
import 'state/settings_controller.dart';
import 'ui/router/app_router.dart';

/// Root widget: wires theming and routing together.
class IkigaiApp extends ConsumerWidget {
  const IkigaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Rebuild themes only when the accent changes.
    final accent = ref.watch(accentControllerProvider);

    return MaterialApp.router(
      title: 'Ikigai',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
      themeMode: themeMode,
      scrollBehavior: const AppScrollBehavior(),
    );
  }
}
