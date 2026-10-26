import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../state/settings_controller.dart';

/// Light/dark switch: an outlined pill with a round knob that slides between
/// the two ends.
///
/// Dark mode: knob on the right, holding a yellow crescent moon.
/// Light mode: knob on the left, holding a sun.
///
/// Tapping flips between light and dark. If the saved preference is
/// "System", the first tap picks the opposite of what the system currently
/// shows, so the switch always responds visibly.
class ThemeSwitch extends ConsumerWidget {
  const ThemeSwitch({this.compact = false, super.key});

  /// Smaller pill for phone app bars.
  final bool compact;

  // Dark palette: translucent white tints, so the pill blends into the
  // app bar instead of sitting on it as a separate color.
  static const _darkTrack = Color(0x0AFFFFFF);
  static const _darkBorder = Color(0x2EFFFFFF);
  static const _darkKnob = Color(0x1AFFFFFF);
  static const _moon = Color(0xFFFFD25F);

  // Light palette.
  static const _lightTrack = Color(0xFFEAF1EF);
  static const _lightBorder = Color(0xFFC3D2CE);
  static const _lightKnob = Colors.white;
  static const _sun = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    final height = compact ? 28.0 : 34.0;
    final width = compact ? 52.0 : 62.0;
    const borderWidth = 1.5;
    const inset = 4.0;
    final knob = height - 2 * (borderWidth + inset);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
      child: Tooltip(
        message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        child: Semantics(
          button: true,
          toggled: isDark,
          label: 'Dark mode',
          child: AnimatedContainer(
            duration: Tokens.durationMedium,
            curve: Tokens.curveSmooth,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: isDark ? _darkTrack : _lightTrack,
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              border: Border.all(
                color: isDark ? _darkBorder : _lightBorder,
                width: borderWidth,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => ref
                    .read(settingsControllerProvider.notifier)
                    .toggleDark(!isDark),
                child: Padding(
                  padding: const EdgeInsets.all(inset),
                  child: AnimatedAlign(
                    duration: Tokens.durationMedium,
                    curve: Tokens.curveSmooth,
                    alignment: isDark
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: Tokens.durationMedium,
                      curve: Tokens.curveSmooth,
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? _darkKnob : _lightKnob,
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                      child: AnimatedSwitcher(
                        duration: Tokens.durationMedium,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(scale: animation, child: child),
                        ),
                        child: Icon(
                          isDark
                              ? Icons.nightlight_round
                              : Icons.wb_sunny_rounded,
                          key: ValueKey(isDark),
                          size: knob * 0.64,
                          color: isDark ? _moon : _sun,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
