import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Buttery, web-first scrolling.
///
/// - Mouse / trackpad / touch drag all work (Flutter web default only allows
///   touch).
/// - [SmoothScrollPhysics] clamps at the edges (no bounce) and caps the fling
///   speed so fast scrolling can never overshoot and spring back.
/// - [RevealOnScroll] + [HoverLift] give every list a staggered, smooth
///   entrance and tactile hover feedback.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const SmoothScrollPhysics();
  }

  // Clamping physics never overscrolls, so the stretch/glow indicator would
  // only flash on touch devices; skip it entirely.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return RawScrollbar(
      controller: details.controller,
      thickness: 8,
      radius: const Radius.circular(999),
      thumbVisibility: false,
      child: child,
    );
  }
}

/// Scroll physics used by every scrollable in the app.
///
/// This is deliberately **clamping** (no overscroll, no bounce-back spring).
///
/// The previous implementation extended [BouncingScrollPhysics] with a
/// near-zero friction factor and a barely-damped spring. On the web, a fast
/// wheel/trackpad fling or a quick touch swipe therefore overshot the edge by
/// a long way and the spring then oscillated back and forth ("over
/// exceeding"), on both vertical pages and horizontal strips (calendar day
/// chips, rails). Clamping stops cleanly at the edge instead.
///
/// The fling velocity is capped so one hard swipe cannot launch the list
/// across a whole page; everything else keeps Flutter's tuned defaults.
class SmoothScrollPhysics extends ClampingScrollPhysics {
  const SmoothScrollPhysics({super.parent});

  @override
  SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SmoothScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => 40;

  @override
  double get maxFlingVelocity => 6000;
}

/// Staggered fade + slide entrance. Wrap rail/grid children with an
/// increasing [index] to get a cascading reveal while scrolling.
///
/// Optimized: uses implicit animations (no per-item [AnimationController] /
/// [Ticker]), so hundreds of grid items cost ~zero tickers. The stagger
/// timer is guarded against use-after-dispose.
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({
    required this.child,
    this.index = 0,
    this.slide = 18.0,
    super.key,
  });

  final Widget child;
  final int index;
  final double slide;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> {
  bool _visible = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // Stagger start so items cascade in. Capped at 8 steps to bound
    // total delay on long grids.
    final delay = Duration(milliseconds: (widget.index % 8) * 45);
    if (delay == Duration.zero) {
      _visible = true;
    } else {
      Future.delayed(delay, () {
        if (!_disposed && mounted) setState(() => _visible = true);
      });
    }
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
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.slide / 100),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Subtle lift + scale + glow on hover (desktop) with smooth animation.
///
/// Optimized: hover state lives in this tiny wrapper so the heavy [child]
/// element instance is reused (no image re-decode); only the transform
/// animates. The child is isolated behind a [RepaintBoundary] so the
/// hover transform does not repaint the image layer.
class HoverLift extends StatefulWidget {
  const HoverLift({
    required this.child,
    this.lift = 6.0,
    this.scale = 1.025,
    this.glow = false,
    super.key,
  });

  final Widget child;
  final double lift;
  final double scale;

  /// When true, also fades in a soft brand glow shadow on hover.
  final bool glow;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: Offset(0, _hovering ? -widget.lift / 100 : 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              // Transparent decoration purely to animate the shadow.
              // The child paints its own background; this wrapper only
              // contributes the hover glow without an extra repaint.
              boxShadow: _hovering && widget.glow
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    );
  }
}

extension SmoothScrollExtension on ScrollController {
  /// Animated, eased scroll-to — use for "back to top" / anchor jumps.
  Future<void> smoothTo(double offset) {
    return animateTo(
      offset,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }
}
