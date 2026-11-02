import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Responsive breakpoints shared by every screen.
///
/// - compact: phones (<600)
/// - medium: large phones / small tablets (600–1000)
/// - expanded: tablets / small laptops (1000–1400)
/// - wide: desktops (>1400)
enum AppBreakpoint { compact, medium, expanded, wide }

extension BreakpointX on BuildContext {
  AppBreakpoint get breakpoint {
    final width = MediaQuery.sizeOf(this).width;
    if (width < Tokens.breakpointCompact) return AppBreakpoint.compact;
    if (width < Tokens.breakpointMedium) return AppBreakpoint.medium;
    if (width < Tokens.breakpointExpanded) return AppBreakpoint.expanded;
    return AppBreakpoint.wide;
  }

  bool get isPhone => breakpoint == AppBreakpoint.compact;
  bool get isTablet => breakpoint == AppBreakpoint.medium;
  bool get isDesktop =>
      breakpoint == AppBreakpoint.expanded || breakpoint == AppBreakpoint.wide;
}

/// Centers content with a max width so ultra-wide screens don't stretch
/// edge-to-edge, while phones keep full-bleed 16px gutters.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    required this.child,
    this.maxWidth = Tokens.maxContentWidth,
    this.padding,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final pad = padding ??
        EdgeInsets.symmetric(
          horizontal: switch (context.breakpoint) {
            AppBreakpoint.compact => Tokens.space16,
            AppBreakpoint.medium => Tokens.space20,
            AppBreakpoint.expanded => Tokens.space24,
            AppBreakpoint.wide => Tokens.space32,
          },
        );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: pad, child: child),
      ),
    );
  }
}

/// Horizontal padding that grows with the viewport.
EdgeInsets responsiveGutter(BuildContext context) => EdgeInsets.symmetric(
      horizontal: switch (context.breakpoint) {
        AppBreakpoint.compact => Tokens.space16,
        AppBreakpoint.medium => Tokens.space20,
        _ => Tokens.space24,
      },
    );

/// How much the reader's text-size setting enlarges text (1.0 = default).
///
/// Grids and lists with a fixed row height multiply the text part of that
/// height by this, so large system fonts don't overflow the tiles.
double textScaleOf(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(1.0, 2.5)
        .toDouble();
