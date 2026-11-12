import 'package:material_ui/material_ui.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/models/media_entry.dart';

/// Color used for each list status.
Color statusColor(ListStatus status) => switch (status) {
  ListStatus.watching => Tokens.statusWatching,
  ListStatus.planning => Tokens.statusPlanning,
  ListStatus.completed => Tokens.statusCompleted,
  ListStatus.paused => Tokens.statusPaused,
  ListStatus.dropped => Tokens.statusDropped,
};

/// Small colored chip describing a list status.
///
/// Animates background/border/text color when [status] changes (e.g.
/// Planning -> Watching) via [AnimatedContainer] instead of popping.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, this.type, super.key});

  final ListStatus status;

  /// Media type, so "Watching" can render as "Reading" for manga.
  final MediaType? type;

  @override
  Widget build(BuildContext context) {
    final base = statusColor(status);
    // Light mode: pure status hues (esp. paused yellow) are too faint as
    // text on a tinted-white chip — darken for contrast. Dark mode keeps
    // the vivid hue on the dark chip.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color = isDark
        ? base
        : HSLColor.fromColor(base)
              .withLightness(
                (HSLColor.fromColor(base).lightness - 0.18).clamp(0.0, 1.0),
              )
              .toColor();
    final label = type != null ? status.labelFor(type!) : status.label;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
