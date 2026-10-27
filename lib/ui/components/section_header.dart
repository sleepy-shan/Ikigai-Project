import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';

/// Section title with an eyebrow pill and an optional "View all" action.
///
/// The action pill lifts + glows on hover (desktop) via implicit
/// animations; the eyebrow fades/slides in on first build.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.actionPath,
    this.onAction,
    this.eyebrow,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final String? actionPath;
  final VoidCallback? onAction;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space24,
        Tokens.space16,
        // Breathing room between the header (and its button) and the cards.
        Tokens.space20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: Tokens.brandGradient,
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Text(
                      eyebrow!.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        shadows: [
                          Shadow(
                            blurRadius: 6,
                            color: Color(0x66000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.space8),
                ],
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: Tokens.brandGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: Tokens.space8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Tokens.space4),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null) _HoverActionPill(
            label: actionLabel!,
            onPressed:
                onAction ??
                (actionPath != null ? () => context.go(actionPath!) : null),
          ),
        ],
      ),
    );
  }
}

/// Action pill with hover lift + border glow (desktop) and press scale.
class _HoverActionPill extends StatefulWidget {
  const _HoverActionPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_HoverActionPill> createState() => _HoverActionPillState();
}

class _HoverActionPillState extends State<_HoverActionPill> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : (_hovering ? 1.04 : 1.0),
          duration: Tokens.durationFast,
          curve: Tokens.curveSmooth,
          child: AnimatedSlide(
            offset: Offset(0, _hovering && !_pressed ? -0.06 : 0),
            duration: Tokens.durationFast,
            curve: Tokens.curveSmooth,
            child: AnimatedContainer(
              duration: Tokens.durationFast,
              curve: Tokens.curveSmooth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                border: Border.all(
                  color: _hovering
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: _hovering ? 1.4 : 1.0,
                ),
                color: theme.cardColor.withValues(alpha: 0.6),
                boxShadow: _hovering
                    ? Tokens.glowShadow(theme.colorScheme.primary)
                    : const [],
              ),
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusMd),
                  ),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: widget.onPressed,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.label),
                    const SizedBox(width: 4),
                    AnimatedSlide(
                      offset: Offset(_hovering ? 0.2 : 0, 0),
                      duration: Tokens.durationFast,
                      curve: Tokens.curveSmooth,
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
