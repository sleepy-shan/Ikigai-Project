import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart';
import '../../data/models/media.dart';
import '../layout/app_shell.dart';
import '../../state/browse_controller.dart';
import '../../state/calendar_controller.dart';
import '../screens/browse_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/my_lists_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/person_works_screen.dart';
import '../screens/profile_list_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/media_detail_screen.dart';
import '../screens/search_screen.dart';

/// Route paths, kept in one place so links stay consistent.
abstract final class Routes {
  static const home = '/';
  static const anime = '/anime';
  static const manga = '/manga';
  static const calendar = '/calendar';
  static const lists = '/lists';
  static const history = '/history';
  static const search = '/search';
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const staff = '/staff';
  static const character = '/character';
  static const studio = '/studio';

  static String mediaDetail(MediaType type, int id) =>
      '/media/${type.anilistValue.toLowerCase()}/$id';

  /// One section of the signed-in user's AniList list, e.g.
  /// `/profile/list/watching`.
  static String profileList(ProfileSection section) =>
      '$profile/list/${section.name}';

  static String staffWorks(int id) => '$staff/$id';

  static String characterWorks(int id) => '$character/$id';

  static String studioWorks(int id) => '$studio/$id';

  /// Browse page pre-set to a home "View all" lineup, e.g.
  /// `/anime?rail=trending`.
  static String browseRail(MediaType type, BrowsePreset preset) =>
      '${type == MediaType.manga ? manga : anime}?rail=${preset.slug}';

  /// Release calendar opened on the Anime or Manga tab.
  static String calendarFor(MediaType type) =>
      '$calendar?tab=${type == MediaType.manga ? 'manga' : 'anime'}';

  static String searchWith(String query) =>
      '$search?q=${Uri.encodeComponent(query)}';
}

/// Builds `'/media/:type/:id'`.
GoRoute mediaDetailRoute() => GoRoute(
  path: '/media/:type/:id',
  builder: (context, state) => MediaDetailScreen(
    mediaId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
    initialType: MediaType.fromWire(state.pathParameters['type']),
  ),
);

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // No initialLocation: on the web the router must honor the browser URL
    // so deep links like /anime or /media/anime/21 work on load/reload.
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: Routes.anime,
            builder: (context, state) => BrowseScreen(
              type: MediaType.anime,
              preset: BrowsePreset.fromSlug(state.uri.queryParameters['rail']),
            ),
          ),
          GoRoute(
            path: Routes.manga,
            builder: (context, state) => BrowseScreen(
              type: MediaType.manga,
              preset: BrowsePreset.fromSlug(state.uri.queryParameters['rail']),
            ),
          ),
          GoRoute(
            path: Routes.calendar,
            builder: (context, state) => CalendarScreen(
              initialTab: state.uri.queryParameters['tab'] == 'manga'
                  ? CalendarTab.manga
                  : (state.uri.queryParameters['tab'] == 'anime'
                        ? CalendarTab.anime
                        : null),
            ),
          ),
          GoRoute(
            path: Routes.lists,
            builder: (context, state) => const MyListsScreen(),
          ),
          GoRoute(
            path: Routes.history,
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: Routes.search,
            builder: (context, state) => SearchScreen(
              initialQuery: state.uri.queryParameters['q'] ?? '',
            ),
          ),
          GoRoute(
            path: '/profile/list/:section',
            builder: (context, state) => ProfileListScreen(
              section: ProfileSection.fromName(
                state.pathParameters['section'],
              ),
            ),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: Routes.notifications,
            builder: (context, state) => const NotificationsScreen(),
          ),
          // Settings is a floating dialog now; keep old links working.
          GoRoute(
            path: Routes.settings,
            redirect: (context, state) => Routes.home,
          ),
          GoRoute(
            path: '/staff/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return PersonWorksScreen(
                key: ValueKey('staff-$id'),
                kind: PersonKind.staff,
                id: id,
              );
            },
          ),
          GoRoute(
            path: '/character/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return PersonWorksScreen(
                key: ValueKey('character-$id'),
                kind: PersonKind.character,
                id: id,
              );
            },
          ),
          GoRoute(
            path: '/studio/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return PersonWorksScreen(
                key: ValueKey('studio-$id'),
                kind: PersonKind.studio,
                id: id,
              );
            },
          ),
          mediaDetailRoute(),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That page does not exist.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    ),
  );
});
