import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../state/settings_controller.dart';
import '../components/account_button.dart';
import '../components/app_logo.dart';
import '../components/search_field.dart';
import '../components/theme_switch.dart';
import '../router/app_router.dart';
import '../screens/settings_dialog.dart';

/// A destination in the top-level navigation.
class _Destination {
  const _Destination(this.label, this.icon, this.activeIcon, this.path);

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
}

/// The five main destinations. Shown in the phone bottom bar and at the top
/// of the desktop sidebar.
const List<_Destination> _mainDestinations = [
  _Destination('Home', Icons.home_outlined, Icons.home_rounded, Routes.home),
  _Destination('Anime', Icons.movie_outlined, Icons.movie_rounded, Routes.anime),
  _Destination(
    'Manga',
    Icons.menu_book_outlined,
    Icons.menu_book_rounded,
    Routes.manga,
  ),
  _Destination(
    'Calendar',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
    Routes.calendar,
  ),
  _Destination(
    'Watchlist',
    Icons.bookmark_border_rounded,
    Icons.bookmark_rounded,
    Routes.lists,
  ),
];

/// Sidebar-only destinations (phones reach these from the profile menu).
const _Destination _historyDestination = _Destination(
  'History',
  Icons.history_rounded,
  Icons.history_rounded,
  Routes.history,
);

/// Responsive app chrome.
///
/// - **Desktop (>= 1000px):** top app bar (logo, search, theme, notifications,
///   profile) with a collapsible sidebar under it.
/// - **Phones (< 1000px):** the same top app bar and a bottom navigation bar.
///
/// Screens render inside [child].
class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  /// Path of the destination the current location belongs to, or null on
  /// pages that are not a destination (profile, search, a title's page).
  String? _activePath(String location) {
    if (location == Routes.home) return Routes.home;
    for (final d in [..._mainDestinations, _historyDestination]) {
      if (d.path != Routes.home && location.startsWith(d.path)) return d.path;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Tokens.breakpointMedium;
    final location =
        Uri.tryParse(ModalRoute.of(context)?.settings.name ?? '')?.path ??
        Routes.home;
    final activePath = _activePath(location);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Command-palette shortcut: "/" or Ctrl/Cmd+K jumps to search from
    // anywhere — unless the user is already typing in a text field (then
    // "/" must type literally instead of navigating away).
    bool isTyping() {
      final focus = FocusManager.instance.primaryFocus;
      final widget = focus?.context?.widget;
      return widget is EditableText;
    }

    void goSearch() {
      if (isTyping()) return;
      context.push(Routes.search);
    }

    // Fade the new page in. Not an AnimatedSwitcher: that keeps the old page
    // mounted next to the new one.
    final content = ClipRect(
      child: _PageFade(key: ValueKey(location), child: child),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): goSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            goSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): goSearch,
      },
      child: Scaffold(
        extendBody: false,
        body: Stack(
          children: [
            Positioned.fill(child: _AuroraBackground(isDark: isDark)),
            Column(
              children: [
                _TopBar(
                  isCompact: isCompact,
                  onLogoTap: () => context.go(Routes.home),
                ),
                Expanded(
                  child: isCompact
                      ? content
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Sidebar(activePath: activePath),
                            Expanded(child: content),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: isCompact
            ? _BottomBar(
                activePath: activePath,
                onTap: (d) => context.go(d.path),
              )
            : null,
      ),
    );
  }
}

/// Soft ember/ink blobs that give every page the same calm ambience.
///
/// Isolated in a [RepaintBoundary] so the gradient blobs paint once and
/// are cached — they do not repaint on every content frame.
class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Stack(
        children: [
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        Positioned(
          top: -140,
          left: -80,
          child: Container(
            width: 460,
            height: 340,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  // Tints with the selected accent via the color scheme.
                  scheme.primary.withValues(
                    alpha: isDark ? 0.28 : 0.14,
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -100,
          right: -60,
          child: Container(
            width: 420,
            height: 300,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  scheme.secondary.withValues(alpha: isDark ? 0.20 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -160,
          left: MediaQuery.sizeOf(context).width * 0.25,
          child: Container(
            width: 560,
            height: 320,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Theme.of(context).colorScheme.tertiary.withValues(
                    alpha: isDark ? 0.14 : 0.08,
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

/// Fades and nudges a page into place when it first appears.
class _PageFade extends StatefulWidget {
  const _PageFade({required this.child, super.key});

  final Widget child;

  @override
  State<_PageFade> createState() => _PageFadeState();
}

class _PageFadeState extends State<_PageFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Tokens.curveSmooth,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// App bar: logo, search, theme switch, notifications, profile.
///
/// - Wide screens (>= 600px) show the search field in the middle.
/// - Narrower screens show a search icon that opens the search page.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.isCompact, required this.onLogoTap});

  final bool isCompact;
  final VoidCallback onLogoTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final showSearchField = width >= Tokens.breakpointCompact;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: Tokens.appBarHeight,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? Tokens.space8 : Tokens.space16,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0E1515).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              AppLogo(
                size: 32,
                showWordmark: !isCompact,
                wordmarkScale: 0.95,
                onTap: onLogoTap,
              ),
              if (showSearchField)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: const _SearchField(),
                      ),
                    ),
                  ),
                )
              else ...[
                const Spacer(),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: () => context.push(Routes.search),
                ),
              ],
              ThemeSwitch(compact: isCompact),
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_none_outlined),
                onPressed: () => context.go(Routes.notifications),
              ),
              AccountButton(iconOnly: width < 1240, mobile: isCompact),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-bar minimalist search. Submitting navigates to the search results
/// route so the result is shareable via the URL. Visuals live in the
/// shared [LensSearchField] so both search bars stay identical.
class _SearchField extends StatefulWidget {
  const _SearchField();

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _focusNode.unfocus();
    context.go(Routes.searchWith(query));
  }

  @override
  Widget build(BuildContext context) {
    return LensSearchField(
      controller: _controller,
      focusNode: _focusNode,
      onSubmitted: _submit,
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop sidebar
// ---------------------------------------------------------------------------

const double _sidebarExpandedWidth = 232;
const double _sidebarCollapsedWidth = 72;

/// Desktop sidebar: Home, Anime, Manga, Calendar, Watchlist, History,
/// Settings. Collapses to icons; the choice is remembered.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.activePath});

  final String? activePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final collapsed = ref.watch(sidebarCollapsedProvider);

    Widget item(_Destination d) => _SidebarItem(
      icon: activePath == d.path ? d.activeIcon : d.icon,
      label: d.label,
      selected: activePath == d.path,
      collapsed: collapsed,
      onTap: () => context.go(d.path),
    );

    return AnimatedContainer(
      duration: Tokens.durationMedium,
      curve: Tokens.curveSmooth,
      width: collapsed ? _sidebarCollapsedWidth : _sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0E1515).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.72),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : theme.dividerColor,
          ),
        ),
      ),
      child: ClipRect(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: Tokens.space12,
                ),
                children: [
                  for (final d in _mainDestinations) item(d),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Tokens.space8,
                      vertical: Tokens.space8,
                    ),
                    child: Divider(height: 1),
                  ),
                  item(_historyDestination),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    selected: false,
                    collapsed: collapsed,
                    onTap: () => showSettingsDialog(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, Tokens.space12),
              child: _SidebarItem(
                icon: collapsed
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded,
                label: 'Collapse',
                tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                selected: false,
                collapsed: collapsed,
                onTap: () =>
                    ref.read(sidebarCollapsedProvider.notifier).toggle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One sidebar row. The icon stays put while the sidebar animates; only the
/// label fades, so collapsing never makes icons jump.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Overrides the collapsed-state tooltip (defaults to [label]).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = selected ? scheme.primary : scheme.onSurfaceVariant;
    final textColor = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    final row = Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          animationDuration: Tokens.durationFast,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 15),
                  Icon(icon, size: 22, color: iconColor),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: Tokens.durationFast,
                      opacity: collapsed ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(left: Tokens.space12),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!collapsed && tooltip == null) return row;
    return Tooltip(
      message: collapsed ? (tooltip ?? label) : tooltip!,
      preferBelow: false,
      child: row,
    );
  }
}

// ---------------------------------------------------------------------------
// Phone bottom bar
// ---------------------------------------------------------------------------

/// Docked bottom navigation for phones: Home, Anime, Manga, Calendar,
/// Watchlist.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.activePath, required this.onTap});

  final String? activePath;
  final ValueChanged<_Destination> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0E1515).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.92),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                for (final d in _mainDestinations)
                  Expanded(
                    child: _BottomItem(
                      destination: d,
                      selected: d.path == activePath,
                      onTap: () => onTap(d),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Tokens.durationFast,
                curve: Tokens.curveSmooth,
                height: 3,
                width: selected ? 20 : 0,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 5),
              Icon(
                selected ? destination.activeIcon : destination.icon,
                size: 21,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
