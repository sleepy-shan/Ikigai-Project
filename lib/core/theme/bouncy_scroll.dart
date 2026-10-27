import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';

/// Smooth + bouncy scrolling for **every** input (wheel, trackpad, touch drag,
/// fling, scrollbar drag), plus a matching custom scrollbar.
///
/// Why this exists: `web_smooth_scroll` only animates the mouse wheel, and to
/// do that it requires `NeverScrollableScrollPhysics` on the inner view, which
/// turns off touch / drag / fling physics entirely. Here the wheel is smoothed
/// *inside the scroll position itself*, so the normal [ScrollPhysics] keep
/// working for drag and fling.
///
/// Pieces:
/// - [BouncyScrollController]  – wheel/trackpad → spring-smoothed scrolling,
///   with a small velocity-dependent bounce when it hits an edge.
/// - [BouncySmoothPhysics]     – touch/drag/fling physics: soft, short,
///   well-damped overscroll (no endless oscillation).
/// - [BouncyScrollbar]         – draggable thumb, click-to-page track, hover
///   grow, auto fade, and a squash animation while the list is overscrolled.
/// - [BouncySmoothScrollView]  – drop-in `CustomScrollView` that wires all of
///   the above together.

// ───────────────────────────── controller ─────────────────────────────

class BouncyScrollController extends ScrollController {
  BouncyScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.wheelSpeed = 1.8,
    this.stiffness = 170,
    this.enableBounce = true,
    this.bounceDamping = 0.5,
    this.maxOverscroll = 56,
    this.preciseThreshold = 40,
  });

  /// Multiplier for mouse-wheel notches (a notch is ~100px in browsers).
  final double wheelSpeed;

  /// Spring stiffness of the wheel animation. Higher = snappier.
  final double stiffness;

  /// Whether a fast wheel flick bounces slightly at the edges.
  final bool enableBounce;

  /// Damping ratio used while overscrolled. 1 = no bounce, ~0.5 = slight.
  final double bounceDamping;

  /// Hard cap (px) for how far the wheel bounce can overshoot an edge.
  final double maxOverscroll;

  /// Wheel deltas smaller than this are treated as a trackpad (precise input)
  /// and follow the finger more tightly instead of being smoothed heavily.
  final double preciseThreshold;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BouncyScrollPosition(
      controller: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _BouncyScrollPosition extends ScrollPositionWithSingleContext {
  _BouncyScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final BouncyScrollController controller;

  Ticker? _ticker;
  bool _animating = false;
  bool _internal = false;
  Duration _last = Duration.zero;
  double _target = 0;
  double _velocity = 0;
  double _stiffness = 170;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;
    final precise = delta.abs() < controller.preciseThreshold;
    final scaled = delta * (precise ? 1.0 : controller.wheelSpeed);
    _stiffness = controller.stiffness * (precise ? 2.6 : 1.0);

    if (!_animating) {
      _internal = true;
      goIdle();
      _internal = false;
      _target = pixels;
      _velocity = 0;
      _animating = true;
      _last = Duration.zero;
      didStartScroll();
      _ticker ??= context.vsync.createTicker(_tick);
      _ticker!.start();
    }
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
    _target = (_target + scaled)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt <= 0) return;
    _last = elapsed;
    dt = math.min(dt, 1 / 30);

    final lo = minScrollExtent;
    final hi = maxScrollExtent;
    final wn = math.sqrt(_stiffness);
    final zetaBounce = controller.bounceDamping.clamp(0.2, 0.99).toDouble();
    // Peak overshoot of an underdamped spring launched from the edge with
    // velocity v is v / wn * peakFactor, so we can cap v to cap the overshoot.
    final root = math.sqrt(1 - zetaBounce * zetaBounce);
    final peakFactor = math.exp(-zetaBounce / root * math.acos(zetaBounce));
    final vCap = controller.maxOverscroll * wn / peakFactor;

    const steps = 2;
    final h = dt / steps;
    var x = pixels;
    var v = _velocity;
    for (var i = 0; i < steps; i++) {
      final wasInside = x >= lo && x <= hi;
      final outside = !wasInside;
      final zeta = outside ? zetaBounce : 1.0;
      final a = _stiffness * (_target - x) - 2 * zeta * wn * v;
      v += a * h;
      x += v * h;
      if (wasInside && (x < lo || x > hi)) {
        if (controller.enableBounce) {
          v = v.clamp(-vCap, vCap).toDouble(); // fast flick => bigger bounce
        } else {
          x = x.clamp(lo, hi).toDouble();
          v = 0;
        }
      }
    }
    final room = controller.maxOverscroll * 1.5;
    x = x.clamp(lo - room, hi + room).toDouble();

    final old = pixels;
    if (x != old) {
      forcePixels(x);
      didUpdateScrollPositionBy(x - old);
    }
    _velocity = v;

    final settled = (_target - x).abs() < 0.4 &&
        v.abs() < 8 &&
        x >= lo &&
        x <= hi;
    if (settled) {
      final end = _target;
      if (end != pixels) {
        final before = pixels;
        forcePixels(end);
        didUpdateScrollPositionBy(end - before);
      }
      _finish();
    }
  }

  void _finish() {
    _animating = false;
    _velocity = 0;
    _ticker?.stop();
    didEndScroll();
    goBallistic(0.0);
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // A drag / animateTo / jumpTo took over: stop the wheel spring.
    if (!_internal && _animating) {
      _animating = false;
      _velocity = 0;
      _ticker?.stop();
      didEndScroll();
    }
    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

// ────────────────────────────── physics ──────────────────────────────

/// Touch / drag / fling physics with a short, soft, well-damped bounce.
class BouncySmoothPhysics extends BouncingScrollPhysics {
  const BouncySmoothPhysics({super.parent});

  @override
  BouncySmoothPhysics applyTo(ScrollPhysics? ancestor) {
    return BouncySmoothPhysics(parent: buildParent(ancestor));
  }

  // Slight bounce, no long oscillation.
  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 160,
        ratio: 0.8,
      );

  // More resistance than the default so overscroll stays small.
  @override
  double frictionFactor(double overscrollFraction) =>
      0.32 * math.pow(1 - overscrollFraction, 2);

  @override
  double get minFlingVelocity => 40;

  @override
  double get maxFlingVelocity => 5500;
}

// ────────────────────────────── scrollbar ──────────────────────────────

/// Custom scrollbar. Wrap a scroll view and pass the same [controller].
///
/// - Drag the thumb, or click the track to page toward the click.
/// - Grows on hover/drag, fades out when idle.
/// - The thumb squashes while the list is overscrolled (wheel or touch
///   bounce), so the bar itself bounces with the content.
class BouncyScrollbar extends StatefulWidget {
  const BouncyScrollbar({
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
    this.thickness = 6,
    this.hoverThickness = 11,
    this.margin = 3,
    this.minThumbLength = 40,
    this.color,
    this.fadeDelay = const Duration(milliseconds: 1100),
    this.alwaysVisible = false,
    super.key,
  });

  final ScrollController controller;
  final Widget child;
  final Axis axis;
  final double thickness;
  final double hoverThickness;
  final double margin;
  final double minThumbLength;
  final Color? color;
  final Duration fadeDelay;
  final bool alwaysVisible;

  @override
  State<BouncyScrollbar> createState() => _BouncyScrollbarState();
}

class _Geo {
  const _Geo(this.length, this.offset, this.track, this.range);
  final double length; // thumb length (after squash)
  final double offset; // thumb start along the track
  final double track; // usable track length
  final double range; // scrollable extent (max - min)
}

class _BouncyScrollbarState extends State<BouncyScrollbar> {
  ScrollMetrics? _m;
  bool _visible = false;
  bool _hover = false;
  bool _drag = false;
  Timer? _hideTimer;

  bool get _vertical => widget.axis == Axis.vertical;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _poke() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.fadeDelay, () {
      if (mounted && !_drag) setState(() => _visible = false);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != widget.axis) return false;
    _safeSetState(() {
      _m = n.metrics;
      _visible = true;
    });
    _poke();
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth != 0 || n.metrics.axis != widget.axis) return false;
    _safeSetState(() => _m = n.metrics);
    return false;
  }

  _Geo? _geo() {
    final m = _m;
    if (m == null) return null;
    final range = m.maxScrollExtent - m.minScrollExtent;
    if (range <= 0.5) return null;
    final viewport = m.viewportDimension;
    final track = viewport - 2 * widget.margin;
    if (track <= 0) return null;

    final total = range + viewport;
    final base = (track * viewport / total)
        .clamp(math.min(widget.minThumbLength, track), track)
        .toDouble();

    final p = m.pixels;
    final over = p < m.minScrollExtent
        ? m.minScrollExtent - p
        : p > m.maxScrollExtent
            ? p - m.maxScrollExtent
            : 0.0;
    final squash = (over / 90).clamp(0.0, 1.0).toDouble();
    final length = math.max(
      math.min(widget.minThumbLength, base) * 0.7,
      base * (1 - 0.5 * squash),
    );

    final frac = ((p - m.minScrollExtent) / range).clamp(0.0, 1.0).toDouble();
    final offset = widget.margin + frac * (track - length);
    return _Geo(length, offset, track, range);
  }

  bool _onThumb(double pos, _Geo g) =>
      pos >= g.offset - 4 && pos <= g.offset + g.length + 4;

  void _dragStart(double pos) {
    final g = _geo();
    if (g == null || !_onThumb(pos, g)) return;
    _hideTimer?.cancel();
    setState(() {
      _drag = true;
      _visible = true;
    });
  }

  void _dragUpdate(double delta) {
    final g = _geo();
    final c = widget.controller;
    if (!_drag || g == null || !c.hasClients) return;
    final free = g.track - g.length;
    if (free <= 0) return;
    final pos = c.position;
    pos.jumpTo(
      (pos.pixels + delta * g.range / free)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent)
          .toDouble(),
    );
  }

  void _dragEnd() {
    if (!_drag) return;
    setState(() => _drag = false);
    _poke();
  }

  void _trackTap(double pos) {
    final g = _geo();
    final c = widget.controller;
    if (g == null || !c.hasClients || _onThumb(pos, g)) return;
    final p = c.position;
    final dir = pos < g.offset ? -1.0 : 1.0;
    final to = (p.pixels + dir * p.viewportDimension * 0.9)
        .clamp(p.minScrollExtent, p.maxScrollExtent)
        .toDouble();
    c.animateTo(
      to,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.color ?? scheme.onSurface;
    final g = _geo();
    final active = _hover || _drag;
    final shown = g != null && (_visible || active || widget.alwaysVisible);
    final thick = active ? widget.hoverThickness : widget.thickness;
    final stripExtent = widget.hoverThickness + widget.margin * 2;
    final alpha = _drag ? 0.78 : (_hover ? 0.58 : 0.36);

    Widget? bar;
    if (g != null) {
      final thumb = AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: _vertical ? thick : g.length,
        height: _vertical ? g.length : thick,
        decoration: BoxDecoration(
          color: base.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(999),
        ),
      );
      bar = Positioned(
        top: _vertical ? 0 : null,
        bottom: _vertical ? 0 : 0,
        right: _vertical ? 0 : null,
        left: _vertical ? null : 0,
        width: _vertical ? stripExtent : null,
        height: _vertical ? null : stripExtent,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => _trackTap(
              _vertical ? d.localPosition.dy : d.localPosition.dx,
            ),
            onVerticalDragStart:
                _vertical ? (d) => _dragStart(d.localPosition.dy) : null,
            onVerticalDragUpdate:
                _vertical ? (d) => _dragUpdate(d.primaryDelta ?? 0) : null,
            onVerticalDragEnd: _vertical ? (_) => _dragEnd() : null,
            onVerticalDragCancel: _vertical ? _dragEnd : null,
            onHorizontalDragStart:
                _vertical ? null : (d) => _dragStart(d.localPosition.dx),
            onHorizontalDragUpdate:
                _vertical ? null : (d) => _dragUpdate(d.primaryDelta ?? 0),
            onHorizontalDragEnd: _vertical ? null : (_) => _dragEnd(),
            onHorizontalDragCancel: _vertical ? null : _dragEnd,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: Duration(milliseconds: shown ? 120 : 280),
              child: Stack(
                children: [
                  Positioned(
                    top: _vertical ? g.offset : null,
                    bottom: _vertical ? null : widget.margin,
                    right: _vertical ? widget.margin : null,
                    left: _vertical ? null : g.offset,
                    child: RepaintBoundary(child: thumb),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.child,
            ),
          ),
        ),
        ?bar,
      ],
    );
  }
}

// ───────────────────────────── drop-in view ─────────────────────────────

/// `CustomScrollView` + [BouncyScrollController] + [BouncySmoothPhysics] +
/// [BouncyScrollbar]. Mouse wheel, trackpad, touch drag, fling and scrollbar
/// drag are all smooth and bounce slightly at the edges when moved fast.
class BouncySmoothScrollView extends StatefulWidget {
  const BouncySmoothScrollView({
    required this.slivers,
    this.controller,
    this.scrollbar = true,
    this.physics,
    super.key,
  });

  final List<Widget> slivers;

  /// Must be a [BouncyScrollController] to get the smoothed wheel.
  final BouncyScrollController? controller;
  final bool scrollbar;
  final ScrollPhysics? physics;

  @override
  State<BouncySmoothScrollView> createState() =>
      _BouncySmoothScrollViewState();
}

class _BouncySmoothScrollViewState extends State<BouncySmoothScrollView> {
  BouncyScrollController? _own;

  BouncyScrollController get _controller =>
      widget.controller ?? (_own ??= BouncyScrollController());

  @override
  void didUpdateWidget(covariant BouncySmoothScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _own != null) {
      _own!.dispose();
      _own = null;
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final view = ScrollConfiguration(
      // Our own scrollbar replaces the platform one.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomScrollView(
        controller: controller,
        physics: widget.physics ?? const BouncySmoothPhysics(),
        slivers: widget.slivers,
      ),
    );
    if (!widget.scrollbar) return view;
    return BouncyScrollbar(controller: controller, child: view);
  }
}
