import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/models/people.dart';
import '../../state/load_state.dart';
import '../../state/search_controller.dart';
import '../components/media_grid.dart';
import '../components/search_field.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

final _favouritesFormat = NumberFormat('#,###');

/// Tabbed search page: Anime, Studios, Staff, Characters.
///
/// Each tab keeps its own paged result set. An empty query shows the
/// popularity ranking (Page 1); typing filters by name with a debounce.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initialQuery = '', super.key});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late final ScrollController _scrollController;
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialQuery.trim().isNotEmpty) {
        ref.read(searchControllerProvider.notifier).submit(widget.initialQuery);
      } else {
        _focusNode.requestFocus();
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 900;
    if (show != _showTop && mounted) setState(() => _showTop = show);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery &&
        widget.initialQuery.trim().isNotEmpty &&
        _controller.text != widget.initialQuery) {
      _controller.text = widget.initialQuery;
      ref.read(searchControllerProvider.notifier).submit(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SmoothCustomScrollView(
          controller: _scrollController,
          slivers: const [
            SliverToBoxAdapter(child: _SearchHeader()),
            SliverToBoxAdapter(child: _TabSearchField()),
            SliverToBoxAdapter(child: _AnimeSortRow()),
            SliverToBoxAdapter(child: _PageNav()),
            SliverToBoxAdapter(
              child: SizedBox(height: Tokens.space8),
            ),
            _ResultsSlivers(),
            SliverAppFooter(),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: BackToTopButton(
            visible: _showTop,
            onPressed: () {
              if (_scrollController.hasClients) {
                _scrollController.smoothTo(0);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Title + subtitle + tab bar (Anime / Studios / Staff / Characters).
class _SearchHeader extends ConsumerWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final controller = ref.read(searchControllerProvider.notifier);

    Widget tabButton(SearchTab value, IconData icon, String label) {
      final selected = tab == value;
      final scheme = theme.colorScheme;
      return TextButton.icon(
        onPressed: selected ? null : () => controller.setTab(value),
        icon: Icon(
          icon,
          size: 18,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        label: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Search', style: theme.textTheme.headlineMedium),
              Text(
                'Simple when you want it, extremely specific when you need it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final tabs = Wrap(
            spacing: Tokens.space4,
            runSpacing: 0,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              tabButton(SearchTab.anime, Icons.movie_outlined, 'Anime'),
              tabButton(SearchTab.studios, Icons.business_outlined, 'Studios'),
              tabButton(SearchTab.staff, Icons.person_outline, 'Staff'),
              tabButton(
                SearchTab.characters,
                Icons.person_search_outlined,
                'Characters',
              ),
            ],
          );
          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const Spacer(), tabs],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Tokens.space8,
            children: [
              titleBlock,
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: tabs,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Right-aligned name search field with a per-tab hint.
class _TabSearchField extends ConsumerWidget {
  const _TabSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final hasQuery = ref.watch(
      searchControllerProvider.select((s) => s.query.isNotEmpty),
    );
    final controller = ref.read(searchControllerProvider.notifier);
    final parent = context.findAncestorStateOfType<_SearchScreenState>();
    final textController = parent?._controller;
    final focusNode = parent?._focusNode;
    if (textController == null || focusNode == null) {
      return const SizedBox.shrink();
    }

    final hint = switch (tab) {
      SearchTab.anime => 'Search anime by name...',
      SearchTab.studios => 'Search studios by name...',
      SearchTab.staff => 'Search staff by name...',
      SearchTab.characters => 'Search characters by name...',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        Tokens.space4,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          // Shared field: the hairline/focus border is drawn once on the
          // outer container, so it always wraps the text, clear button and
          // search action as a single whole outline.
          child: LensSearchField(
            controller: textController,
            focusNode: focusNode,
            hintLong: hint,
            hintShort: hint,
            showKbdChip: false,
            showClear: hasQuery,
            onChanged: controller.onQueryChanged,
            onSubmitted: controller.submit,
            onClear: () {
              textController.clear();
              controller.clear();
            },
          ),
        ),
      ),
    );
  }
}

/// Sort selector for the Anime tab (other tabs are favourites-ranked).
class _AnimeSortRow extends ConsumerWidget {
  const _AnimeSortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    if (tab != SearchTab.anime) return const SizedBox.shrink();
    final sort = ref.watch(
      searchControllerProvider.select((s) => s.animeSort),
    );
    final controller = ref.read(searchControllerProvider.notifier);
    const options = [
      MediaSort.popularity,
      MediaSort.trending,
      MediaSort.score,
      MediaSort.titleRomaji,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        0,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: DropdownButton<MediaSort>(
            value: options.contains(sort) ? sort : MediaSort.popularity,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final s in options)
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    s == MediaSort.popularity ? 'Most Popular' : s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (s) {
              if (s != null) controller.setAnimeSort(s);
            },
          ),
        ),
      ),
    );
  }
}

/// "Characters · Page 1" label with prev/next arrows.
class _PageNav extends ConsumerWidget {
  const _PageNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final page = ref.watch(
      searchControllerProvider.select((s) => switch (s.tab) {
            SearchTab.anime => s.anime.page,
            SearchTab.studios => s.studios.page,
            SearchTab.staff => s.staff.page,
            SearchTab.characters => s.characters.page,
          }),
    );
    final hasNext = ref.watch(
      searchControllerProvider.select((s) => switch (s.tab) {
            SearchTab.anime => s.anime.hasNextPage,
            SearchTab.studios => s.studios.hasNextPage,
            SearchTab.staff => s.staff.hasNextPage,
            SearchTab.characters => s.characters.hasNextPage,
          }),
    );
    final isLoading = ref.watch(
      searchControllerProvider.select((s) => switch (s.tab) {
            SearchTab.anime => s.anime.status == LoadStatus.loading,
            SearchTab.studios => s.studios.status == LoadStatus.loading,
            SearchTab.staff => s.staff.status == LoadStatus.loading,
            SearchTab.characters =>
              s.characters.status == LoadStatus.loading,
          }),
    );
    final controller = ref.read(searchControllerProvider.notifier);
    final label = switch (tab) {
      SearchTab.anime => 'Anime',
      SearchTab.studios => 'Studios',
      SearchTab.staff => 'Staff',
      SearchTab.characters => 'Characters',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        0,
      ),
      child: Row(
        children: [
          Text(
            '$label · Page $page',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton.outlined(
            tooltip: 'Previous page',
            visualDensity: VisualDensity.compact,
            onPressed: page <= 1 || isLoading
                ? null
                : controller.previousPage,
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          const SizedBox(width: Tokens.space8),
          IconButton.outlined(
            tooltip: 'Next page',
            visualDensity: VisualDensity.compact,
            onPressed: !hasNext || isLoading ? null : controller.nextPage,
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ResultsSlivers extends ConsumerWidget {
  const _ResultsSlivers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    return switch (tab) {
      SearchTab.anime => const _AnimeResults(),
      SearchTab.studios => const _StudioResults(),
      SearchTab.staff => const _StaffResults(),
      SearchTab.characters => const _CharacterResults(),
    };
  }
}

class _AnimeResults extends ConsumerWidget {
  const _AnimeResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      searchControllerProvider.select((s) => s.anime.status),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final results = ref.watch(
      searchControllerProvider.select((s) => s.anime.items),
    );
    final errorMessage = ref.watch(
      searchControllerProvider.select((s) => s.anime.errorMessage),
    );
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (status) {
      LoadStatus.initial => const SliverEmpty(
        title: 'Start typing',
        message: 'Search anime by title — for example "frieren".',
        icon: Icons.search,
      ),
      LoadStatus.loading when results.isEmpty => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      // Keep-previous-data: show the old grid while the next page loads.
      LoadStatus.loading => SliverPosterGrid(items: results, hasMore: true),
      LoadStatus.error when results.isEmpty => SliverError(
        message: errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => SliverPosterGrid(items: results),
      LoadStatus.success when results.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'Nothing matched "${query.trim()}". '
                  'Try a different spelling or fewer words.'
            : 'No anime found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => SliverPosterGrid(items: results),
    };
  }
}

class _StudioResults extends ConsumerWidget {
  const _StudioResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.studios),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No studios matched "${query.trim()}".'
            : 'No studios found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
    };
  }
}

class _StaffResults extends ConsumerWidget {
  const _StaffResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.staff),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No staff matched "${query.trim()}".'
            : 'No staff found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
    };
  }
}

class _CharacterResults extends ConsumerWidget {
  const _CharacterResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.characters),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No characters matched "${query.trim()}".'
            : 'No characters found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
    };
  }
}

/// Responsive grid of horizontal person/studio cards.
class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = _peopleColumns(constraints.crossAxisExtent);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space8,
            Tokens.space16,
            Tokens.space16,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Tokens.space12,
              crossAxisSpacing: Tokens.space12,
              childAspectRatio: 2.9,
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: itemCount,
            itemBuilder: (context, index) => RepaintBoundary(
              child: itemBuilder(context, index),
            ),
          ),
        );
      },
    );
  }
}

int _peopleColumns(double width) {
  if (width >= 1250) return 4;
  if (width >= 950) return 3;
  if (width >= 620) return 2;
  return 1;
}

String _formatFavourites(int value) => _favouritesFormat.format(value);

/// Favourites pill: "♡ 39,561".
class _FavouritesPill extends StatelessWidget {
  const _FavouritesPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
      child: Text(
        '♡ ${_formatFavourites(count)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PersonImage extends StatelessWidget {
  const _PersonImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      child: SizedBox(
        width: 56,
        height: 78,
        child: url.isEmpty
            ? Container(
                color: theme.disabledColor.withValues(alpha: 0.15),
                child: const Icon(
                  Icons.person_outline,
                  size: 24,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stack) => Container(
                  color: theme.disabledColor.withValues(alpha: 0.15),
                  child: const Icon(Icons.person_outline, size: 24),
                ),
              ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});

  final SearchCharacter character;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.characterWorks(character.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            _PersonImage(url: character.imageUrl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    character.nameFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (character.nameNative != null &&
                      character.nameNative!.isNotEmpty)
                    Text(
                      character.nameNative!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: Tokens.space4),
                  _FavouritesPill(count: character.favourites),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff});

  final SearchStaff staff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.staffWorks(staff.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            _PersonImage(url: staff.imageUrl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    staff.nameFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (staff.nameNative != null &&
                      staff.nameNative!.isNotEmpty)
                    Text(
                      staff.nameNative!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: Tokens.space4),
                  Wrap(
                    spacing: Tokens.space4,
                    runSpacing: Tokens.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (staff.role.isNotEmpty)
                        Text(
                          staff.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      _FavouritesPill(count: staff.favourites),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StudioCard extends StatelessWidget {
  const _StudioCard({required this.studio});

  final SearchStudio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.studioWorks(studio.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            Container(
              width: 56,
              height: 78,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
              ),
              child: const Icon(Icons.business_outlined, size: 24),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    studio.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Wrap(
                    spacing: Tokens.space4,
                    runSpacing: Tokens.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        studio.isAnimationStudio
                            ? 'Animation studio'
                            : 'Studio',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _FavouritesPill(count: studio.favourites),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
