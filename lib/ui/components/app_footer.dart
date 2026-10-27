import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../state/browse_controller.dart';
import '../components/app_logo.dart';
import '../router/app_router.dart';

/// Site footer matching the Yomi mock: brand blurb on the left,
/// link columns (Browse / Genres / Format), and a legal bottom bar.
///
/// No Discord button by request. Links are functional: genre/format
/// taps apply an anime browse filter and navigate there, browse taps
/// jump to the relevant route.
class AppFooter extends ConsumerWidget {
  const AppFooter({super.key});

  Future<void> _browseGenre(
    BuildContext context,
    WidgetRef ref,
    String genre,
  ) async {
    await ref
        .read(browseControllerProvider(MediaType.anime).notifier)
        .applyFilters(genre: genre);
    if (context.mounted) context.go(Routes.anime);
  }

  Future<void> _browseFormat(
    BuildContext context,
    WidgetRef ref,
    MediaFormat format,
  ) async {
    await ref
        .read(browseControllerProvider(MediaType.anime).notifier)
        .applyFilters(format: format);
    if (context.mounted) context.go(Routes.anime);
  }

  Future<void> _browseSort(
    BuildContext context,
    WidgetRef ref,
    MediaSort sort,
  ) async {
    await ref
        .read(browseControllerProvider(MediaType.anime).notifier)
        .setSort(sort);
    if (context.mounted) context.go(Routes.anime);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final year = DateTime.now().year;

    return Container(
      margin: const EdgeInsets.only(top: Tokens.space32),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Tokens.maxContentWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space16,
              Tokens.space32,
              Tokens.space16,
              Tokens.space16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 800;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _BrandBlock(theme: theme),
                          ),
                          Expanded(
                            child: _LinkColumn(
                              title: 'Browse',
                              links: [
                                ('Trending', () => _browseSort(context, ref, MediaSort.trending)),
                                ('Top Rated', () => _browseSort(context, ref, MediaSort.score)),
                                ('New Releases', () { context.go(Routes.calendar); }),
                                ('Seasonal', () { context.go(Routes.calendar); }),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _LinkColumn(
                              title: 'Genres',
                              links: [
                                ('Action', () => _browseGenre(context, ref, 'Action')),
                                ('Romance', () => _browseGenre(context, ref, 'Romance')),
                                ('Sci-Fi', () => _browseGenre(context, ref, 'Sci-Fi')),
                                ('Horror', () => _browseGenre(context, ref, 'Horror')),
                                ('Fantasy', () => _browseGenre(context, ref, 'Fantasy')),
                                ('Slice of Life', () => _browseGenre(context, ref, 'Slice of Life')),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _LinkColumn(
                              title: 'Format',
                              links: [
                                ('TV Series', () => _browseFormat(context, ref, MediaFormat.tv)),
                                ('Movies', () => _browseFormat(context, ref, MediaFormat.movie)),
                                ('OVA', () => _browseFormat(context, ref, MediaFormat.ova)),
                                ('ONA', () => _browseFormat(context, ref, MediaFormat.ona)),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandBlock(theme: theme),
                        const SizedBox(height: Tokens.space24),
                        Wrap(
                          spacing: Tokens.space32,
                          runSpacing: Tokens.space24,
                          children: [
                            SizedBox(
                              width: 150,
                              child: _LinkColumn(
                                title: 'Browse',
                                links: [
                                  ('Trending', () => _browseSort(context, ref, MediaSort.trending)),
                                  ('Top Rated', () => _browseSort(context, ref, MediaSort.score)),
                                  ('New Releases', () { context.go(Routes.calendar); }),
                                  ('Seasonal', () { context.go(Routes.calendar); }),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: _LinkColumn(
                                title: 'Genres',
                                links: [
                                  ('Action', () => _browseGenre(context, ref, 'Action')),
                                  ('Romance', () => _browseGenre(context, ref, 'Romance')),
                                  ('Sci-Fi', () => _browseGenre(context, ref, 'Sci-Fi')),
                                  ('Horror', () => _browseGenre(context, ref, 'Horror')),
                                  ('Fantasy', () => _browseGenre(context, ref, 'Fantasy')),
                                  ('Slice of Life', () => _browseGenre(context, ref, 'Slice of Life')),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: _LinkColumn(
                                title: 'Format',
                                links: [
                                  ('TV Series', () => _browseFormat(context, ref, MediaFormat.tv)),
                                  ('Movies', () => _browseFormat(context, ref, MediaFormat.movie)),
                                  ('OVA', () => _browseFormat(context, ref, MediaFormat.ova)),
                                  ('ONA', () => _browseFormat(context, ref, MediaFormat.ona)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Tokens.space32),
                Divider(height: 1, color: theme.dividerColor),
                const SizedBox(height: Tokens.space16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bottomWide = constraints.maxWidth >= 640;
                    final left = Text(
                      '© $year Ikigai. All rights reserved.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                    final right = Text(
                      'Ikigai does not host any media files. '
                      'Metadata provided by AniList.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: bottomWide ? TextAlign.end : TextAlign.start,
                    );
                    if (bottomWide) {
                      return Row(
                        children: [left, const Spacer(), Flexible(child: right)],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        left,
                        const SizedBox(height: Tokens.space4),
                        right,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 32, showWordmark: true),
        const SizedBox(height: Tokens.space12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            'Discover anime and manga with seasonal calendars, '
            'airing schedules, and personal tracking. Built for real fans.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: Tokens.space12),
        Text(
          'Free & open — no ads, no account required.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({required this.title, required this.links});

  final String title;
  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: Tokens.space12),
        for (final (label, onTap) in links)
          _FooterLink(label: label, onTap: onTap),
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            widget.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _hovering
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              decoration: _hovering ? TextDecoration.underline : null,
              decorationColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sliver wrapper so scrollable screens can drop the footer at the end
/// of a [CustomScrollView] with a single line.
class SliverAppFooter extends StatelessWidget {
  const SliverAppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(child: AppFooter());
  }
}
