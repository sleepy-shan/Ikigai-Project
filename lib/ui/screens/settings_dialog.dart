import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/design_tokens.dart';
import '../../state/settings_controller.dart';

/// Opens Settings as a floating dialog over the current page.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => const _SettingsDialog(),
  );
}

/// Floating settings panel: single Appearance section (theme only).
class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: theme.cardColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(Tokens.space16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: size.height < 600 ? size.height - 32 : 340,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space24,
                Tokens.space16,
                Tokens.space12,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Appearance',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  Tokens.space24,
                  Tokens.space8,
                  Tokens.space24,
                  Tokens.space24,
                ),
                child: _AppearanceBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Theme mode only (accent color removed).
class _AppearanceBody extends ConsumerWidget {
  const _AppearanceBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final preference = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Tokens.space4),
        Text('Choose a theme. "System" follows your device setting.', style: muted),
        const SizedBox(height: Tokens.space12),
        AnimatedThemeSegmented<ThemePreference>(
          values: ThemePreference.values,
          selected: preference,
          onSelected: controller.setThemePreference,
          labelFor: (p) => switch (p) {
            ThemePreference.system => 'System',
            ThemePreference.light => 'Light',
            ThemePreference.dark => 'Dark',
          },
          iconFor: (p) => switch (p) {
            ThemePreference.system => Icons.brightness_auto_outlined,
            ThemePreference.light => Icons.light_mode_outlined,
            ThemePreference.dark => Icons.dark_mode_outlined,
          },
        ),
      ],
    );
  }
}
