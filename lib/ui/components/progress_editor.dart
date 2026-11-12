import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/models/media_entry.dart';

/// Stepper plus slider for episode/chapter progress.
///
/// Animated: the +/- buttons scale on press, the counter cross-fades on
/// change, and the slider thumb glides (slider itself animates natively).
class ProgressEditor extends StatelessWidget {
  const ProgressEditor({
    required this.progress,
    required this.total,
    required this.unit,
    required this.onChanged,
    super.key,
  });

  final int progress;

  /// Total units when known (null for ongoing titles).
  final int? total;
  final String unit;
  final ValueChanged<int> onChanged;

  void _set(int value) {
    final clamped = total == null
        ? value.clamp(0, 1 << 30)
        : value.clamp(0, total!);
    onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final max = total;
    return Row(
      children: [
        Pressable(
          onTap: progress > 0 ? () => _set(progress - 1) : null,
          child: IconButton.filledTonal(
            tooltip: 'Decrease $unit',
            onPressed: progress > 0 ? () => _set(progress - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: Tokens.durationFast,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  max != null
                      ? '$progress / $max ${unit}s'
                      : '$progress ${unit}s',
                  key: ValueKey(progress),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (max != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end: progress.clamp(0, max).toDouble(),
                  ),
                  duration: Tokens.durationMedium,
                  curve: Tokens.curveSmooth,
                  builder: (context, animated, _) => Slider(
                    value: animated.clamp(0, max.toDouble()),
                    max: max.toDouble(),
                    divisions: max > 0 ? max : null,
                    label: '$progress',
                    onChanged: (value) => _set(value.round()),
                  ),
                ),
            ],
          ),
        ),
        Pressable(
          onTap: max == null || progress < max
              ? () => _set(progress + 1)
              : null,
          child: IconButton.filledTonal(
            tooltip: 'Increase $unit',
            onPressed: max == null || progress < max
                ? () => _set(progress + 1)
                : null,
            icon: AnimatedScale(
              // Subtle pop when the value changes.
              scale: 1.0,
              duration: Tokens.durationFast,
              child: const Icon(Icons.add, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// Score picker on a 0-10 scale (null = unrated).
class ScoreSelector extends StatelessWidget {
  const ScoreSelector({
    required this.score,
    required this.onChanged,
    super.key,
  });

  final int? score;
  final ValueChanged<int?> onChanged;

  static const List<int> _scores = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: DropdownButtonFormField<int?>(
        initialValue: score,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Score',
          contentPadding: EdgeInsets.symmetric(
            horizontal: Tokens.space12,
            vertical: Tokens.space8,
          ),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Not scored')),
          for (final value in _scores)
            DropdownMenuItem<int?>(value: value, child: Text('$value / 10')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Dropdown that switches an entry's list status.
class StatusSelector extends StatelessWidget {
  const StatusSelector({
    required this.status,
    required this.type,
    required this.onChanged,
    super.key,
  });

  final ListStatus status;
  final MediaType type;
  final ValueChanged<ListStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ListStatus>(
      initialValue: status,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'List status',
        contentPadding: EdgeInsets.symmetric(
          horizontal: Tokens.space12,
          vertical: Tokens.space8,
        ),
      ),
      items: [
        for (final value in ListStatus.values)
          DropdownMenuItem(value: value, child: Text(value.labelFor(type))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
