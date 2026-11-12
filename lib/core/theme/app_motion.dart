import 'package:material_ui/material_ui.dart';

import 'design_tokens.dart';

/// Central motion system: toggles, press states, scroll reveals, shimmer.
///
/// Design goals:
/// - Implicit animations only (no per-item [AnimationController]) except for
///   the single shared shimmer ticker in [ShimmerGrid].
/// - Cheap rebuilds: hover/press state lives in a tiny wrapper so heavy
///   children (images) are not rebuilt — the same element instance is reused
///   and only the transform wrapper animates.
/// - Consistent durations/curves from [Tokens].
abstract final class AppMotion {
  static const Duration toggle = Duration(milliseconds: 220);
  static const Duration press = Duration(milliseconds: 120);
  static const Duration reveal = Duration(milliseconds: 380);
  static const Duration shimmer = Duration(milliseconds: 1300);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve snap = Curves.easeOutBack;
}

/// Animated on/off toggle switch with sliding thumb and glow.
///
/// Use for settings, filters, "show only" switches — anywhere a boolean
/// needs tactile animated feedback.
class AnimatedToggle extends StatelessWidget {
  const AnimatedToggle({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbColor = value ? Colors.white : scheme.onSurfaceVariant;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: AnimatedContainer(
            duration: AppMotion.toggle,
            curve: AppMotion.ease,
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              gradient: value ? Tokens.brandGradient : null,
              color: value
                  ? null
                  : scheme.surfaceContainerHighest.withValues(
                      alpha: enabled ? 1.0 : 0.5,
                    ),
              border: Border.all(
                color: value
                    ? Colors.transparent
                    : scheme.outline.withValues(alpha: 0.4),
              ),
              boxShadow: value ? Tokens.glowShadow(scheme.primary) : null,
            ),
            child: AnimatedAlign(
              duration: AppMotion.toggle,
              curve: AppMotion.ease,
              alignment: value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: AppMotion.toggle,
                curve: AppMotion.ease,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value
                      ? Colors.white
                      : scheme.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: AnimatedScale(
                  scale: value ? 1.0 : 0.85,
                  duration: AppMotion.toggle,
                  curve: AppMotion.ease,
                  child: Icon(
                    value ? Icons.check_rounded : Icons.close_rounded,
                    size: 13,
                    color: thumbColor == Colors.white && value
                        ? Tokens.brand
                        : thumbColor,
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

/// Scale-down on press (tap down) with spring-back on release.
///
/// Wrap buttons, cards, chips for tactile feedback without rebuilding
/// the child subtree — only the transform animates.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.scale = 0.96,
    this.onTap,
    super.key,
  });

  final Widget child;
  final double scale;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1.0,
          duration: AppMotion.press,
          curve: AppMotion.ease,
          // RepaintBoundary isolates the transform so the child layer
          // is cached and not repainted during the scale.
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

/// Cheap staggered entrance: fade + slide with delayed start.
///
/// Unlike a per-item [AnimationController], this uses implicit animations
/// (no [Ticker]) so hundreds of grid items cost ~zero tickers. The delay
/// timer is cancelled on dispose to avoid use-after-dispose.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.child,
    this.index = 0,
    this.slide = 14.0,
    this.delayStep = 35,
    this.maxStagger = 8,
    super.key,
  });

  final Widget child;
  final int index;
  final double slide;
  final int delayStep;
  final int maxStagger;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _visible = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final delay =
        Duration(milliseconds: (widget.index % widget.maxStagger) * widget.delayStep);
    Future.delayed(delay, () {
      if (!_disposed && mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: AppMotion.reveal,
      curve: AppMotion.ease,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.slide / 100),
        duration: AppMotion.reveal,
        curve: AppMotion.ease,
        child: widget.child,
      ),
    );
  }
}

/// Animated back-to-top floating button: fades + scales in when [visible].
class BackToTopButton extends StatelessWidget {
  const BackToTopButton({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: Tokens.durationMedium,
      curve: Tokens.curveSmooth,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.7,
        duration: Tokens.durationMedium,
        curve: Tokens.curveSnap,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              gradient: Tokens.brandGradient,
              shape: BoxShape.circle,
              boxShadow: Tokens.glowShadow(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            child: IconButton(
              tooltip: 'Back to top',
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated theme-mode segmented control: sliding gradient pill.
///
/// Replaces a static [SegmentedButton] where motion matters (settings).
class AnimatedThemeSegmented<T> extends StatelessWidget {
  const AnimatedThemeSegmented({
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelFor,
    required this.iconFor,
    super.key,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelFor;
  final IconData Function(T) iconFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = values.length;
        final selectedIndex = values.indexOf(selected);
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: AppMotion.toggle,
                        curve: AppMotion.ease,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: i == selectedIndex
                              ? Tokens.brandGradient
                              : null,
                          borderRadius:
                              BorderRadius.circular(Tokens.radiusPill),
                          boxShadow: i == selectedIndex
                              ? Tokens.glowShadow(scheme.primary)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onSelected(values[i]),
                        child: SizedBox(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                iconFor(values[i]),
                                size: 17,
                                color: i == selectedIndex
                                    ? Colors.white
                                    : scheme.onSurfaceVariant,
                              ),
                              // Icons only on very narrow phones (320px).
                              if (constraints.maxWidth >= 380) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    labelFor(values[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: i == selectedIndex
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: i == selectedIndex
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
