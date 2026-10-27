import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/app_exception.dart';
import '../../data/models/people.dart';
import '../../state/media_providers.dart';
import '../components/app_footer.dart';
import '../components/media_grid.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

final _favouritesFormat = NumberFormat('#,###');

/// What the page is about: a staff member, a character or a studio.
enum PersonKind { staff, character, studio }

/// Titles linked to one staff member (what they voiced / worked on) or one
/// character (the series they appear in).
///
/// Opened by tapping a card on Search > Staff / Characters.
class PersonWorksScreen extends ConsumerStatefulWidget {
  const PersonWorksScreen({required this.kind, required this.id, super.key});

  final PersonKind kind;
  final int id;

  @override
  ConsumerState<PersonWorksScreen> createState() => _PersonWorksScreenState();
}

class _PersonWorksScreenState extends ConsumerState<PersonWorksScreen> {
  final BouncyScrollController _scroll = BouncyScrollController();
  int _page = 1;

  /// Last loaded profile, so the header stays put while another page loads.
  PersonProfile? _profile;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AsyncValue<PersonWorks> _watch() {
    final key = (widget.id, _page);
    return switch (widget.kind) {
      PersonKind.staff => ref.watch(staffWorksProvider(key)),
      PersonKind.character => ref.watch(characterWorksProvider(key)),
      PersonKind.studio => ref.watch(studioWorksProvider(key)),
    };
  }

  void _retry() {
    final key = (widget.id, _page);
    switch (widget.kind) {
      case PersonKind.staff:
        ref.invalidate(staffWorksProvider(key));
      case PersonKind.character:
        ref.invalidate(characterWorksProvider(key));
      case PersonKind.studio:
        ref.invalidate(studioWorksProvider(key));
    }
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.smoothTo(0);
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.search);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = _watch();
    final data = async.value;
    if (data != null) _profile = data.person;

    final label = switch (widget.kind) {
      PersonKind.staff => 'Credits',
      PersonKind.character => 'Appears in',
      PersonKind.studio => 'Productions',
    };
    final emptyMessage = switch (widget.kind) {
      PersonKind.staff =>
        'No anime or manga credits are listed for this person yet.',
      PersonKind.character => 'No series are listed for this character yet.',
      PersonKind.studio => 'No anime are listed for this studio yet.',
    };
    final loading = async.isLoading;
    final hasNext = data?.works.hasNextPage ?? false;

    final Widget results = async.when(
      loading: () => const SliverToBoxAdapter(child: LoadingPosterGrid()),
      error: (error, stack) => SliverError(
        message: error is AppException
            ? error.userMessage
            : 'Could not load this page. Please try again.',
        onRetry: _retry,
      ),
      data: (works) => works.works.items.isEmpty
          ? SliverEmpty(
              title: 'No titles found',
              message: emptyMessage,
              icon: Icons.movie_outlined,
            )
          : SliverPosterGrid(items: works.works.items),
    );

    return SmoothCustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: _PersonHeader(
            kind: widget.kind,
            profile: _profile,
            onBack: _back,
          ),
        ),
        SliverToBoxAdapter(
          child: _PageNav(
            label: label,
            page: _page,
            canGoPrevious: _page > 1 && !loading,
            canGoNext: hasNext && !loading,
            onPrevious: () => _goToPage(_page - 1),
            onNext: () => _goToPage(_page + 1),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Tokens.space8)),
        results,
        const SliverAppFooter(),
      ],
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.kind,
    required this.profile,
    required this.onBack,
  });

  final PersonKind kind;
  final PersonProfile? profile;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final person = profile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space16,
        Tokens.space16,
        Tokens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Tokens.space16,
        children: [
          IconButton.outlined(
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          _Avatar(
            url: person?.imageUrl ?? '',
            icon: kind == PersonKind.studio
                ? Icons.business_outlined
                : Icons.person_outline,
          ),
          Expanded(
            child: person == null
                ? const _HeaderSkeleton()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.nameFull,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium,
                      ),
                      if (person.nameNative != null &&
                          person.nameNative!.isNotEmpty)
                        Text(
                          person.nameNative!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: Tokens.space8),
                      Wrap(
                        spacing: Tokens.space8,
                        runSpacing: Tokens.space4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (person.role.isNotEmpty)
                            Text(
                              person.role,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Tokens.space8,
                              vertical: Tokens.space2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(Tokens.radiusSm),
                            ),
                            child: Text(
                              '♡ ${_favouritesFormat.format(person.favourites)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.icon});

  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget placeholder() => Container(
      color: theme.disabledColor.withValues(alpha: 0.15),
      child: Icon(icon, size: 32),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      child: SizedBox(
        width: 84,
        height: 118,
        child: url.isEmpty
            ? placeholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stack) => placeholder(),
              ),
      ),
    );
  }
}

/// Neutral bars shown in place of the name while the first page loads.
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Tokens.space8,
      children: [bar(220, 28), bar(140, 18), bar(90, 18)],
    );
  }
}

/// "Credits · Page 1" label with prev/next arrows (mirrors the search page).
class _PageNav extends StatelessWidget {
  const _PageNav({
    required this.label,
    required this.page,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final int page;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          const SizedBox(width: Tokens.space8),
          IconButton.outlined(
            tooltip: 'Next page',
            visualDensity: VisualDensity.compact,
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}
