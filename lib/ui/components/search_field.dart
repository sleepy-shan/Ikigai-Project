import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Minimalist search field used by the top bar (and available to any page).
///
/// Plain hairline outline, 10px radius, divider + search action on the
/// right — matches the search page field so both bars look identical.
/// No gradients, glows, orbs, or kbd chips: just a quiet field that
/// lights its border on hover/focus.
///
/// The legacy [LensSearchField] constructor params are kept so existing
/// callers don't break; decorative options ([showKbdChip], lens styling)
/// are intentionally ignored except for a subtle "/" hint.
class LensSearchField extends StatefulWidget {
  const LensSearchField({
    required this.controller,
    required this.focusNode,
    this.autofocus = false,
    this.hintLong = 'Search anime & manga…',
    this.hintShort = 'Search anime & manga…',
    this.showKbdChip = true,
    this.onKbdTap,
    this.showClear = false,
    this.onClear,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final String hintLong;
  final String hintShort;

  /// Kept for compatibility; renders as a subtle "/" hint, not a chip.
  final bool showKbdChip;
  final VoidCallback? onKbdTap;

  final bool showClear;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<LensSearchField> createState() => _LensSearchFieldState();
}

class _LensSearchFieldState extends State<LensSearchField> {
  bool _focused = false;
  bool _hovering = false;
  String _text = '';

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    _focused = widget.focusNode.hasFocus;
    _text = widget.controller.text;
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant LensSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  void _onText() {
    if (mounted && _text != widget.controller.text) {
      setState(() => _text = widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _submit() => widget.onSubmitted?.call(widget.controller.text);

  void _clear() {
    if (widget.onClear != null) {
      widget.onClear!();
    } else {
      widget.controller.clear();
      widget.onChanged?.call('');
    }
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color borderColor = _focused
        ? scheme.primary
        : _hovering
            ? scheme.outline
            : scheme.outlineVariant;
    final double borderWidth = _focused ? 1.5 : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final hint = maxW >= 400 ? widget.hintLong : widget.hintShort;
        final showHint = widget.showKbdChip && _text.isEmpty && maxW >= 300;
        // Very narrow fields give the text the room: smaller action buttons.
        final tight = maxW < 220;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            onTap: () => widget.focusNode.requestFocus(),
            child: AnimatedContainer(
              duration: Tokens.durationFast,
              curve: Tokens.curveSmooth,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F1F) : Colors.white,
                border: Border.all(color: borderColor, width: borderWidth),
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      autofocus: widget.autofocus,
                      textInputAction: TextInputAction.search,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                      cursorColor: scheme.primary,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintMaxLines: 1,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isDense: true,
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (showHint)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '/',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  if (_text.isNotEmpty || widget.showClear)
                    IconButton(
                      tooltip: 'Clear',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: tight ? 28 : 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: _clear,
                    ),
                  Container(
                    width: 1,
                    height: 22,
                    color: scheme.outlineVariant,
                  ),
                  IconButton(
                    tooltip: 'Search',
                    visualDensity: VisualDensity.compact,
                    padding: tight ? EdgeInsets.zero : const EdgeInsets.all(8),
                    constraints: tight
                        ? const BoxConstraints(minWidth: 36, minHeight: 36)
                        : null,
                    icon: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: _focused
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
