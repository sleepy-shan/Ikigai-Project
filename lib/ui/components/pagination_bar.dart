import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/design_tokens.dart';

/// Which entries a pager shows for [page] of [pageCount].
///
/// Returns page numbers with `null` marking a gap ("…"). The last page number
/// is deliberately not shown (the total is only an estimate and a big number
/// like 209 adds noise); a trailing gap stands in for "more pages", and the gap
/// opens the "Go to page" dialog. The last page is only listed once the reader
/// is on it or right next to it:
///
/// ```
/// page 1   → 1 2 3 4 5 …
/// page 60  → 1 … 59 60 61 …
/// page 120 → 1 … 116 117 118 119 120
/// ```
List<int?> paginationItems({
  required int page,
  required int pageCount,
  int siblings = 1,
}) {
  final last = pageCount < 1 ? 1 : pageCount;
  final current = page < 1 ? 1 : (page > last ? last : page);
  final slots = 3 + 2 * siblings; // pages in an edge block (5 by default)
  if (last <= slots + 2) {
    return [for (var i = 1; i <= last; i++) i];
  }

  final left = current - siblings < 1 ? 1 : current - siblings;
  final right = current + siblings > last ? last : current + siblings;
  final gapLeft = left > 2;

  if (!gapLeft) {
    return [for (var i = 1; i <= slots; i++) i, null];
  }
  if (right >= last) {
    return [1, null, for (var i = last - slots + 1; i <= last; i++) i];
  }
  return [1, null, for (var i = left; i <= right; i++) i, null];
}

/// Page-by-page navigation: previous, numbered pages, next.
///
/// Wide layouts show the numbered window; narrow ones (phones) collapse it
/// into a single "Page 3" pill. Either way, tapping the pill or a
/// gap opens a small "Go to page" dialog, so far-away pages stay reachable.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    required this.page,
    required this.pageCount,
    required this.hasNext,
    required this.onPageSelected,
    this.busy = false,
    super.key,
  });

  /// Current page (1-based).
  final int page;

  /// Best-known number of pages.
  final int pageCount;

  /// Whether the API says there is a page after [page]. Wins over
  /// [pageCount], which can be an estimate.
  final bool hasNext;

  final ValueChanged<int> onPageSelected;

  /// True while a page is loading; the controls are disabled.
  final bool busy;

  static const double _compactBelow = 520;

  Future<void> _jump(BuildContext context) async {
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _JumpDialog(pageCount: pageCount),
    );
    if (target != null && target != page) onPageSelected(target);
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = !busy && page > 1;
    final canNext = !busy && (hasNext || page < pageCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBelow;
        final prev = _StepButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous page',
          onPressed: canPrev ? () => onPageSelected(page - 1) : null,
        );
        final next = _StepButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next page',
          onPressed: canNext ? () => onPageSelected(page + 1) : null,
        );

        if (compact) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              prev,
              const SizedBox(width: Tokens.space12),
              _PagePill(
                page: page,
                onTap: busy ? null : () => _jump(context),
              ),
              const SizedBox(width: Tokens.space12),
              next,
            ],
          );
        }

        final items = paginationItems(page: page, pageCount: pageCount);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            prev,
            const SizedBox(width: Tokens.space8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: item == null
                    ? _GapButton(onTap: busy ? null : () => _jump(context))
                    : _NumberButton(
                        number: item,
                        selected: item == page,
                        onTap: busy || item == page
                            ? null
                            : () => onPageSelected(item),
                      ),
              ),
            const SizedBox(width: Tokens.space8),
            next,
          ],
        );
      },
    );
  }
}

/// Previous / next. 44 px so it is a comfortable touch target.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(Tokens.radiusLg - 2);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: enabled
                ? scheme.outlineVariant
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 26,
              color: enabled
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.32),
            ),
          ),
        ),
      ),
    );
  }
}

/// One page number. The current page is a filled, accent-coloured tile.
class _NumberButton extends StatelessWidget {
  const _NumberButton({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(Tokens.radiusLg - 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            // Wide enough for five digits without changing the row's height.
            width: number >= 10000 ? 52 : 40,
            height: 40,
            child: Center(
              child: Text(
                '$number',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "…" between page numbers. Tapping it opens the jump dialog.
class _GapButton extends StatelessWidget {
  const _GapButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Go to page…',
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusLg - 2),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 40,
          child: Icon(
            Icons.more_horiz_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Compact "Page 3" pill used on phones.
class _PagePill extends StatelessWidget {
  const _PagePill({required this.page, required this.onTap});

  final int page;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusLg - 2);
    return Tooltip(
      message: 'Page $page. Tap to go to a page.',
      child: Material(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Page $page',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
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

/// "Go to page" prompt. Owns (and disposes) its own text controller.
class _JumpDialog extends StatefulWidget {
  const _JumpDialog({required this.pageCount});

  final int pageCount;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_text.text.trim());
    if (value == null || value < 1 || value > widget.pageCount) {
      setState(() => _error = 'Enter a valid page number');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Page number',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
