import 'package:flutter/material.dart';
import 'package:fluro/fluro.dart';

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

/// Pulls a positive integer path parameter such as `:id`.
int _intParam(Map<String, List<String>> params, String name) =>
    int.tryParse(params[name]?.first ?? '') ?? 0;

/// First value of a path/query parameter, or null.
String? _param(Map<String, List<String>> params, String name) =>
    params[name]?.first;

/// Wraps [page] in the app chrome (top bar, sidebar, bottom bar).
///
/// Fluro has no ShellRoute, so every page route is wrapped explicitly.
Widget _shell(Widget page) => AppShell(child: page);

/// Opens [Routes.home] as soon as it is built; keeps the old `/settings`
/// link working now that settings is a floating dialog.
class _RedirectHome extends StatefulWidget {
  const _RedirectHome();

  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(Routes.home);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The Fluro router for the whole app.
///
/// No initial route is set: on the web the browser URL is honored so deep
/// links like /anime or /media/anime/21 work on load/reload.
final FluroRouter appRouter = _buildRouter();

FluroRouter _buildRouter() {
  final router = FluroRouter();

  void page(String path, Widget Function(Map<String, List<String>>) build) {
    router.define(
      path,
      transitionType: TransitionType.none,
      handler: Handler(
        handlerFunc: (context, params) => _shell(build(params)),
      ),
    );
  }

  page(Routes.home, (_) => const HomeScreen());
  page(
    Routes.anime,
    (p) => BrowseScreen(
      type: MediaType.anime,
      preset: BrowsePreset.fromSlug(_param(p, 'rail')),
    ),
  );
  page(
    Routes.manga,
    (p) => BrowseScreen(
      type: MediaType.manga,
      preset: BrowsePreset.fromSlug(_param(p, 'rail')),
    ),
  );
  page(
    Routes.calendar,
    (p) => CalendarScreen(
      initialTab: _param(p, 'tab') == 'manga'
          ? CalendarTab.manga
          : (_param(p, 'tab') == 'anime' ? CalendarTab.anime : null),
    ),
  );
  page(Routes.lists, (_) => const MyListsScreen());
  page(Routes.history, (_) => const HistoryScreen());
  page(
    Routes.search,
    (p) => SearchScreen(initialQuery: _param(p, 'q') ?? ''),
  );
  page(
    '${Routes.profile}/list/:section',
    (p) => ProfileListScreen(
      section: ProfileSection.fromName(_param(p, 'section')),
    ),
  );
  page(Routes.profile, (_) => const ProfileScreen());
  page(Routes.notifications, (_) => const NotificationsScreen());
  // Settings is a floating dialog now; keep old links working.
  page(Routes.settings, (_) => const _RedirectHome());
  page(
    '${Routes.staff}/:id',
    (p) {
      final id = _intParam(p, 'id');
      return PersonWorksScreen(
        key: ValueKey('staff-$id'),
        kind: PersonKind.staff,
        id: id,
      );
    },
  );
  page(
    '${Routes.character}/:id',
    (p) {
      final id = _intParam(p, 'id');
      return PersonWorksScreen(
        key: ValueKey('character-$id'),
        kind: PersonKind.character,
        id: id,
      );
    },
  );
  page(
    '${Routes.studio}/:id',
    (p) {
      final id = _intParam(p, 'id');
      return PersonWorksScreen(
        key: ValueKey('studio-$id'),
        kind: PersonKind.studio,
        id: id,
      );
    },
  );
  page(
    '/media/:type/:id',
    (p) => MediaDetailScreen(
      mediaId: _intParam(p, 'id'),
      initialType: MediaType.fromWire(_param(p, 'type')),
    ),
  );

  router.notFoundHandler = Handler(
    handlerFunc: (context, params) => const _NotFoundScreen(),
  );
  return router;
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}

/// Navigation shortcuts backed by [appRouter].
extension AppNavigation on BuildContext {
  /// Replaces the whole navigation stack with [path].
  Future<void> go(String path) =>
      appRouter.navigateTo(this, path, clearStack: true);

  /// Pushes [path] on top of the current page.
  Future<void> push(String path) => appRouter.navigateTo(this, path);

  /// Whether there is a page to go back to.
  bool canPop() => Navigator.of(this).canPop();

  /// Goes back one page.
  void pop() => Navigator.of(this).pop();
}
