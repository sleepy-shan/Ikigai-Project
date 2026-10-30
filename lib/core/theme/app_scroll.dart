import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'bouncy_scroll.dart';

export 'bouncy_scroll.dart';

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

/// Drop-in page-level scroll view: smooth + slightly bouncy for mouse wheel,
/// trackpad, touch drag and fling, with the custom [BouncyScrollbar].
/// See `bouncy_scroll.dart`. Pass a [BouncyScrollController] when the screen
/// needs the scroll position (back-to-top, infinite scroll).
class SmoothCustomScrollView extends StatelessWidget {
  const SmoothCustomScrollView({
    required this.slivers,
    this.controller,
    super.key,
  });

  final List<Widget> slivers;
  final BouncyScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return BouncySmoothScrollView(controller: controller, slivers: slivers);
  }
}

/// Staggered fade + slide entrance. Wrap rail/grid children with an
/// increasing [index] to get a cascading reveal while scrolling.
///
/// Optimized: uses implicit animations (no per-item [AnimationController] /
/// [Ticker]), so hundreds of grid items cost ~zero tickers. The stagger
/// timer is guarded against use-after-dispose.
///
/// Pass a [revealKey] (e.g. the title id) so an item only animates the first
/// time it appears. Virtualized grids rebuild items as they scroll back into
/// view, and replaying the fade-in each time makes fast scrolling flicker.
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({
    required this.child,
    this.index = 0,
    this.slide = 18.0,
    this.revealKey,
    super.key,
  });

  final Widget child;
  final int index;
  final double slide;

  /// Identity used to remember that this item has already been revealed.
  final Object? revealKey;

  /// Keys already revealed (insertion ordered, bounded).
  static final Set<Object> _seen = <Object>{};
  static const int _maxSeen = 4000;

  static void _remember(Object? key) {
    if (key == null) return;
    _seen.remove(key);
    _seen.add(key);
    if (_seen.length > _maxSeen) _seen.remove(_seen.first);
  }

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> {
  bool _visible = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final key = widget.revealKey;
    // Already seen, or arriving while the page is scrolling: show at once.
    // Fading in every tile of a fast scroll is dozens of opacity layers per
    // frame; the entrance is only worth it for a still page.
    if ((key != null && RevealOnScroll._seen.contains(key)) ||
        ScrollBusy.isScrolling) {
      _visible = true;
      RevealOnScroll._remember(key);
      return;
    }
    // Stagger start so items cascade in. Capped at 8 steps to bound
    // total delay on long grids.
    final delay = Duration(milliseconds: (widget.index % 8) * 40);
    if (delay == Duration.zero) {
      _visible = true;
      RevealOnScroll._remember(key);
    } else {
      Future.delayed(delay, () {
        if (_disposed || !mounted) return;
        RevealOnScroll._remember(key);
        setState(() => _visible = true);
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.slide / 100),
        duration: const Duration(milliseconds: 320),
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
      // Cards sliding under a stationary pointer while scrolling must not each
      // run a lift / scale / glow animation.
      onEnter: (_) {
        if (!ScrollBusy.isScrolling) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
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
