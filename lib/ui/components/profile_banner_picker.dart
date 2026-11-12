import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/profile_banner.dart';
import '../../state/profile_banner_controller.dart';
import 'profile_banner.dart';

/// Opens the banner picker: choose one of the built-in animated,
/// anime-inspired styles, or fall back to the AniList banner.
Future<void> showProfileBannerPicker(
  BuildContext context, {
  String? anilistBannerUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _ProfileBannerPickerDialog(anilistBannerUrl: anilistBannerUrl),
  );
}

class _ProfileBannerPickerDialog extends ConsumerWidget {
  const _ProfileBannerPickerDialog({this.anilistBannerUrl});

  final String? anilistBannerUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = ref.watch(profileBannerControllerProvider);
    final controller = ref.read(profileBannerControllerProvider.notifier);

    return Dialog(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(Tokens.space16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusXl),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusXl),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_motion_rounded,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: Tokens.space8),
                      Expanded(
                        child: Text(
                          'Choose your banner',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.space4),
                  Text(
                    'An Ikigai-only touch — pick an animated anime-inspired '
                    'look. Your AniList banner is still one tap away.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Tokens.space16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = Tokens.space12;
                      final columns = constraints.maxWidth >= 460 ? 3 : 2;
                      final tileWidth =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final preset in BannerPreset.values)
                            SizedBox(
                              width: tileWidth,
                              child: _PresetTile(
                                preset: preset,
                                anilistBannerUrl: anilistBannerUrl,
                                selected: current.preset == preset,
                                onTap: () => controller.setPreset(preset),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: Tokens.space16),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => controller.reset(),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.anilistBannerUrl,
    required this.selected,
    required this.onTap,
  });

  final BannerPreset preset;
  final String? anilistBannerUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: preset.description,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 62,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProfileBannerView(
                    preset: preset,
                    fallbackImageUrl: anilistBannerUrl,
                  ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Tokens.space4),
            Text(
              preset.label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
