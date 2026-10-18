import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Horizontal rail with desktop affordances: arrow buttons, edge fades.
///
/// Why not a plain `ListView.separated(horizontal)`?
/// - Discoverability: on desktop a bare rail gives no hint it scrolls.
///   Arrows + fades signal overflow and give a click target.
/// - Performance: fixed [itemExtent] lets the viewport lay out without
///   measuring every child; `primary: false` + owned controller avoids
///   `PrimaryScrollController` fights with the outer vertical sliver.
/// - Resource safety: the controller is owned here and disposed.
///
/// For very short static strips (<=8 chips) consider `SingleChildScrollView
/// + Row` instead — no virtualization overhead. This widget targets
/// virtualized rails (12+ posters, continue cards).
class ArrowRail extends StatefulWidget {
  const ArrowRail({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtent,
    this.separatorWidth = Tokens.space12,
    this.padding = const EdgeInsets.symmetric(horizontal: Tokens.space16),
    this.scrollStepFraction = 0.8,
    super.key,
  });

  final double height;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Fixed main-axis extent per item (including separator). When set, the
  /// viewport skips child measurement — faster for uniform cards.
  /// Example: rail card 148 + separator 12 = 160.
  final double? itemExtent;
  final double separatorWidth;
  final EdgeInsets padding;

  /// Fraction of the viewport width to glide per arrow tap.
  final double scrollStepFraction;

  @override
  State<ArrowRail> createState() => _ArrowRailState();
}

class _ArrowRailState extends State<ArrowRail> {
  late final ScrollController _controller;
  bool _canBack = false;
  bool _canForward = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateEdges();
    });
  }

  void _updateEdges() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final canBack = pos.pixels > 4;
    final canForward = pos.pixels < pos.maxScrollExtent - 4;
    if (canBack != _canBack || canForward != _canForward) {
      if (mounted) {
        setState(() {
          _canBack = canBack;
          _canForward = canForward;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ArrowRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateEdges();
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateEdges)
      ..dispose();
    super.dispose();
  }

  void _step(int direction) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target = (_controller.offset +
            direction * viewport * widget.scrollStepFraction)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: Tokens.durationMedium,
      curve: Tokens.curveSmooth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            _buildList(),
            // Left fade + arrow.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _canBack ? 1.0 : 0.0,
                duration: Tokens.durationFast,
                child: IgnorePointer(
                  ignoring: !_canBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ArrowButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Scroll back',
                        visible: _hovering || _canBack,
                        onTap: () => _step(-1),
                      ),
                      const SizedBox(width: 28),
                    ],
                  ),
                ),
              ),
            ),
            // Right fade + arrow.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _canForward ? 1.0 : 0.0,
                duration: Tokens.durationFast,
                child: IgnorePointer(
                  ignoring: !_canForward,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 28),
                      _ArrowButton(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Scroll forward',
                        visible: _hovering || _canForward,
                        onTap: () => _step(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    // Fixed-extent path: ListView.builder with itemExtent — no measuring.
    if (widget.itemExtent != null) {
      return ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        primary: false,
        // Clamping: no overscroll glow / white flash and no bounce-back
        // spring on fast flings.
        physics: const ClampingScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        padding: widget.padding,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(right: widget.separatorWidth),
          child: widget.itemBuilder(context, index),
        ),
      );
    }
    return ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      primary: false,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.hardEdge,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: widget.padding,
      itemCount: widget.itemCount,
      separatorBuilder: (context, index) =>
          SizedBox(width: widget.separatorWidth),
      itemBuilder: widget.itemBuilder,
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.visible,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.6,
      duration: Tokens.durationFast,
      curve: Tokens.curveSmooth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Center(
          child: Container(
            decoration: BoxDecoration(
              // Transparent dark glass — same in light and dark mode,
              // lets the poster show through instead of a solid surface block.
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              tooltip: tooltip,
              icon: Icon(icon, color: Colors.white),
              onPressed: onTap,
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-virtualized horizontal strip for short static content (<=8 items).
///
/// Uses `SingleChildScrollView + Row` — cheaper than a viewport when every
/// child is always built anyway (e.g. 8 genre chips). Owns and disposes
/// its controller.
class StaticStrip extends StatefulWidget {
  const StaticStrip({
    required this.height,
    required this.children,
    this.separatorWidth = Tokens.space8,
    this.padding = const EdgeInsets.symmetric(horizontal: Tokens.space16),
    super.key,
  });

  final double height;
  final List<Widget> children;
  final double separatorWidth;
  final EdgeInsets padding;

  @override
  State<StaticStrip> createState() => _StaticStripState();
}

class _StaticStripState extends State<StaticStrip> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        primary: false,
        physics: const ClampingScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        padding: widget.padding,
        child: Row(
          children: [
            for (var i = 0; i < widget.children.length; i++) ...[
              widget.children[i],
              if (i != widget.children.length - 1)
                SizedBox(width: widget.separatorWidth),
            ],
          ],
        ),
      ),
    );
  }
}
