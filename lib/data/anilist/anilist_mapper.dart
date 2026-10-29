import '../models/account.dart';
import '../models/airing_schedule.dart';
import '../models/media.dart';
import '../models/people.dart';

/// Converts AniList JSON payloads into app models.
///
/// All parsing is defensive: AniList can omit fields, and titles may be
/// missing English or romaji variants, so every field has a fallback.
abstract final class AniListMapper {
  /// Parses a list of media nodes from a `Page.media` payload.
  static List<Media> mediaList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(_media).whereType<Media>().toList(growable: false);
  }

  /// Parses a single `Media` object (detail page).
  static Media? single(Object? raw) => _media(raw);

  static Media? _media(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;

    final type = MediaType.fromWire(json['type'] as String?);
    final title =
        (json['title'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        const {};

    return Media(
      id: id,
      type: type,
      title: _title(title),
      coverUrl: _coverUrl(json['coverImage'] as Map?),
      bannerUrl: (json['bannerImage'] as String?)?.trim(),
      description: json['description'] as String?,
      genres:
          (json['genres'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      tags: _tags(json['tags'] as List?),
      format: MediaFormat.fromWire(json['format'] as String?),
      status: MediaStatus.fromWire(json['status'] as String?),
      season: MediaSeason.fromWire(json['season'] as String?),
      seasonYear: (json['seasonYear'] as num?)?.toInt(),
      episodes: (json['episodes'] as num?)?.toInt(),
      chapters: (json['chapters'] as num?)?.toInt(),
      volumes: (json['volumes'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      averageScore: (json['averageScore'] as num?)?.toInt(),
      meanScore: (json['meanScore'] as num?)?.toInt(),
      popularity: (json['popularity'] as num?)?.toInt(),
      favourites: (json['favourites'] as num?)?.toInt(),
      studios: _studios(json['studios'] as Map?),
      source: (json['source'] as String?)?.replaceAll('_', ' '),
      countryOfOrigin: json['countryOfOrigin'] as String?,
      startDate: _fuzzyDate(json['startDate'] as Map?),
      endDate: _fuzzyDate(json['endDate'] as Map?),
      siteUrl: json['siteUrl'] as String?,
      nextAiringEpisode: _airing(json['nextAiringEpisode'] as Map?),
      relations: _relations(json['relations'] as Map?),
      recommendations: _recommendations(json['recommendations'] as Map?),
    );
  }

  /// English title wins, then romaji, then native, then a placeholder.
  static String _title(Map<dynamic, dynamic> title) {
    for (final key in const ['english', 'romaji', 'native']) {
      final value = title[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return 'Untitled';
  }

  static String _coverUrl(Map? coverImage) {
    if (coverImage == null) return '';
    for (final key in const ['extraLarge', 'large', 'medium']) {
      final value = coverImage[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  static List<MediaTag> _tags(List? tags) {
    if (tags == null) return const [];
    return tags
        .whereType<Map>()
        .map(
          (tag) => MediaTag(
            name: (tag['name'] as String?)?.trim() ?? '',
            rank: (tag['rank'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((tag) => tag.name.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _studios(Map? studios) {
    final nodes = studios?['nodes'];
    if (nodes is! List) return const [];
    return nodes
        .whereType<Map>()
        .map((node) => (node['name'] as String?)?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  static List<MediaEdge> _relations(Map? relations) {
    final edges = relations?['edges'];
    if (edges is! List) return const [];
    return edges
        .whereType<Map>()
        .map((edge) {
          final node = _media(edge['node']);
          if (node == null) return null;
          return MediaEdge(
            relationType: _relationType(
              (edge['relationType'] as String?) ?? '',
            ),
            media: node,
          );
        })
        .whereType<MediaEdge>()
        .toList(growable: false);
  }

  static List<Media> _recommendations(Map? recommendations) {
    final nodes = recommendations?['nodes'];
    if (nodes is! List) return const [];
    return nodes
        .whereType<Map>()
        .map((node) => _media(node['mediaRecommendation']))
        .whereType<Media>()
        .toList(growable: false);
  }

  static NextAiringEpisode? _airing(Map? airing) {
    if (airing == null) return null;
    final episode = (airing['episode'] as num?)?.toInt();
    final at = (airing['airingAt'] as num?)?.toInt();
    if (episode == null || at == null) return null;
    return NextAiringEpisode(episode: episode, airingAt: at);
  }

  /// AniList uses fuzzy dates ({year, month, day}); build "YYYY-MM-DD" when a
  /// full date is available, otherwise null.
  static String? _fuzzyDate(Map? date) {
    if (date == null) return null;
    final year = (date['year'] as num?)?.toInt();
    final month = (date['month'] as num?)?.toInt();
    final day = (date['day'] as num?)?.toInt();
    if (year == null || month == null || day == null) return null;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// "SEQUEL" -> "Sequel", "SIDE_STORY" -> "Side Story".
  static String _relationType(String wire) {
    if (wire.trim().isEmpty) return 'Related';
    final words = wire.toLowerCase().split('_');
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  /// Parses `Page.airingSchedules`.
  ///
  /// Entries whose media is missing (or has no usable id) are dropped rather
  /// than mapped to `mediaId: 0`, which produced a dead `/media/anime/0` link.
  /// Adult titles are dropped too: the schedule root has no `isAdult` filter
  /// argument, so it has to be applied here.
  static List<AiringScheduleItem> airingSchedule(Object? raw) {
    if (raw is! List) return const [];
    final out = <AiringScheduleItem>[];
    for (final item in raw.whereType<Map>()) {
      final media = _asMap(item['media']);
      final mediaId = (media?['id'] as num?)?.toInt();
      if (media == null || mediaId == null || mediaId <= 0) continue;
      if (media['isAdult'] == true) continue;
      out.add(
        AiringScheduleItem(
          id: (item['id'] as num?)?.toInt() ?? 0,
          mediaId: mediaId,
          mediaType: MediaType.fromWire(media['type'] as String?),
          title: AniListMapper._title(_asMap(media['title']) ?? const {}),
          coverUrl: AniListMapper._coverUrl(media['coverImage'] as Map?),
          episode: (item['episode'] as num?)?.toInt() ?? 0,
          airingAt: (item['airingAt'] as num?)?.toInt() ?? 0,
          totalEpisodes: (media['episodes'] as num?)?.toInt(),
          averageScore: (media['averageScore'] as num?)?.toInt(),
          popularity: (media['popularity'] as num?)?.toInt(),
          format: MediaFormat.fromWire(media['format'] as String?),
          platform: _streamingSite(media['externalLinks']),
        ),
      );
    }
    return List.unmodifiable(out);
  }

  /// First enabled streaming link's site name ("Crunchyroll"), if any.
  static String? _streamingSite(Object? raw) {
    if (raw is! List) return null;
    for (final link in raw.whereType<Map>()) {
      if (link['type'] != 'STREAMING' || link['isDisabled'] == true) continue;
      final site = (link['site'] as String?)?.trim();
      if (site != null && site.isNotEmpty) return site;
    }
    return null;
  }

  /// Parses a `Page.characters` payload for the search tab.
  static List<SearchCharacter> characters(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final map = item.map((key, value) => MapEntry(key.toString(), value));
          final id = (map['id'] as num?)?.toInt();
          if (id == null) return null;
          final name =
              (map['name'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {};
          final full = (name['full'] as String?)?.trim() ?? '';
          if (full.isEmpty) return null;
          final image =
              (map['image'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {};
          return SearchCharacter(
            id: id,
            nameFull: full,
            nameNative: (name['native'] as String?)?.trim(),
            imageUrl: (image['large'] as String?)?.trim() ?? '',
            favourites: (map['favourites'] as num?)?.toInt() ?? 0,
          );
        })
        .whereType<SearchCharacter>()
        .toList(growable: false);
  }

  /// Parses a `Page.staff` payload for the search tab.
  static List<SearchStaff> staff(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final map = item.map((key, value) => MapEntry(key.toString(), value));
          final id = (map['id'] as num?)?.toInt();
          if (id == null) return null;
          final name =
              (map['name'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {};
          final full = (name['full'] as String?)?.trim() ?? '';
          if (full.isEmpty) return null;
          final image =
              (map['image'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {};
          final occupations =
              (map['primaryOccupations'] as List?)
                  ?.map((e) => e.toString().replaceAll('_', ' '))
                  .where((e) => e.trim().isNotEmpty)
                  .toList(growable: false) ??
              const [];
          return SearchStaff(
            id: id,
            nameFull: full,
            nameNative: (name['native'] as String?)?.trim(),
            imageUrl: (image['large'] as String?)?.trim() ?? '',
            favourites: (map['favourites'] as num?)?.toInt() ?? 0,
            role: occupations.join(' · '),
          );
        })
        .whereType<SearchStaff>()
        .toList(growable: false);
  }

  /// Parses a `Page.studios` payload for the search tab.
  static List<SearchStudio> studios(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final map = item.map((key, value) => MapEntry(key.toString(), value));
          final id = (map['id'] as num?)?.toInt();
          if (id == null) return null;
          final name = (map['name'] as String?)?.trim() ?? '';
          if (name.isEmpty) return null;
          return SearchStudio(
            id: id,
            name: name,
            favourites: (map['favourites'] as num?)?.toInt() ?? 0,
            isAnimationStudio: map['isAnimationStudio'] != false,
          );
        })
        .whereType<SearchStudio>()
        .toList(growable: false);
  }

  /// Reads `Page.pageInfo` for the people/studio search endpoints.
  static ({int page, bool hasNextPage}) pageInfo(
    Object? raw,
    int fallbackPage,
  ) {
    if (raw is! Map) return (page: fallbackPage, hasNextPage: false);
    final info =
        (raw['pageInfo'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        const {};
    return (
      page: (info['currentPage'] as num?)?.toInt() ?? fallbackPage,
      hasNextPage: info['hasNextPage'] == true,
    );
  }

  /// Parses `Staff(id:)` into a profile plus the merged list of titles they
  /// voiced (`characterMedia`) or worked on (`staffMedia`).
  static PersonWorks? staffWorks(Object? raw, int fallbackPage) {
    final map = _asMap(raw);
    if (map == null) return null;
    final profile = _profile(map, withRole: true);
    if (profile == null) return null;
    return PersonWorks(
      person: profile,
      works: _mergeConnections([
        map['characterMedia'],
        map['staffMedia'],
      ], fallbackPage),
    );
  }

  /// Parses `Character(id:)` into a profile plus the series they appear in.
  static PersonWorks? characterWorks(Object? raw, int fallbackPage) {
    final map = _asMap(raw);
    if (map == null) return null;
    final profile = _profile(map);
    if (profile == null) return null;
    return PersonWorks(
      person: profile,
      works: _mergeConnections([map['media']], fallbackPage),
    );
  }

  /// Parses `Studio(id:)` into a profile plus the titles it produced.
  static PersonWorks? studioWorks(Object? raw, int fallbackPage) {
    final map = _asMap(raw);
    if (map == null) return null;
    final id = (map['id'] as num?)?.toInt();
    final name = (map['name'] as String?)?.trim() ?? '';
    if (id == null || name.isEmpty) return null;
    return PersonWorks(
      person: PersonProfile(
        id: id,
        nameFull: name,
        favourites: (map['favourites'] as num?)?.toInt() ?? 0,
        role: map['isAnimationStudio'] == false ? 'Studio' : 'Animation studio',
      ),
      works: _mergeConnections([map['media']], fallbackPage),
    );
  }

  /// Parses `Page.notifications` (airing / related addition / data change).
  /// Unknown or media-less notifications are skipped.
  static List<UserNotification> notifications(Object? raw) {
    if (raw is! List) return const [];
    final out = <UserNotification>[];
    for (final item in raw) {
      final map = _asMap(item);
      if (map == null) continue;
      final id = (map['id'] as num?)?.toInt();
      final type = map['type'] as String?;
      if (id == null || type == null) continue;
      final parsed = mediaList([map['media']]);
      if (parsed.isEmpty) continue;
      final media = parsed.first;

      final NotificationKind kind;
      final String message;
      switch (type) {
        case 'AIRING':
          final episode = (map['episode'] as num?)?.toInt();
          kind = NotificationKind.airing;
          message = episode == null
              ? 'A new episode aired'
              : 'Episode $episode aired';
        case 'RELATED_MEDIA_ADDITION':
          kind = NotificationKind.relatedAddition;
          message = 'A related title was added';
        case 'MEDIA_DATA_CHANGE':
          final reason = (map['reason'] as String?)?.trim() ?? '';
          kind = NotificationKind.dataChange;
          message = reason.isEmpty ? 'Details were updated' : reason;
        default:
          continue;
      }
      final seconds = (map['createdAt'] as num?)?.toInt() ?? 0;
      out.add(
        UserNotification(
          id: id,
          kind: kind,
          mediaId: media.id,
          mediaType: media.type,
          title: media.title,
          coverUrl: media.coverUrl,
          message: message,
          createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        ),
      );
    }
    return out;
  }

  /// Parses `Viewer` (with `statistics.anime`) for the profile page.
  static ViewerProfile? viewerProfile(Object? raw) {
    final map = _asMap(raw);
    if (map == null) return null;
    final name = (map['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    final anime = _asMap(_asMap(map['statistics'])?['anime']);
    var watching = 0;
    var completed = 0;
    var planning = 0;
    var paused = 0;
    var dropped = 0;
    var rewatching = 0;
    final statuses = anime?['statuses'];
    if (statuses is List) {
      for (final entry in statuses) {
        final status = _asMap(entry);
        final count = (status?['count'] as num?)?.toInt() ?? 0;
        switch (status?['status']) {
          case 'CURRENT':
            watching = count;
          case 'COMPLETED':
            completed = count;
          case 'PLANNING':
            planning = count;
          case 'PAUSED':
            paused = count;
          case 'DROPPED':
            dropped = count;
          case 'REPEATING':
            rewatching = count;
        }
      }
    }
    final manga = _asMap(_asMap(map['statistics'])?['manga']);
    // `favourites.anime` is a connection; only its total is needed.
    final favourites = _asMap(_asMap(map['favourites'])?['anime']);
    final favouritesTotal = _asMap(favourites?['pageInfo'])?['total'];
    final banner = (map['bannerImage'] as String?)?.trim();
    return ViewerProfile(
      name: name,
      avatarUrl: _asMap(map['avatar'])?['large'] as String?,
      bannerUrl: banner == null || banner.isEmpty ? null : banner,
      totalCount: (anime?['count'] as num?)?.toInt() ?? 0,
      watching: watching,
      completed: completed,
      planning: planning,
      paused: paused,
      dropped: dropped,
      rewatching: rewatching,
      favourites: (favouritesTotal as num?)?.toInt() ?? 0,
      episodesWatched: (anime?['episodesWatched'] as num?)?.toInt(),
      minutesWatched: (anime?['minutesWatched'] as num?)?.toInt(),
      meanScore: (anime?['meanScore'] as num?)?.toDouble(),
      mangaCount: (manga?['count'] as num?)?.toInt() ?? 0,
      chaptersRead: (manga?['chaptersRead'] as num?)?.toInt(),
      volumesRead: (manga?['volumesRead'] as num?)?.toInt(),
      mangaMeanScore: (manga?['meanScore'] as num?)?.toDouble(),
      animeGenres: _genres(anime?['genres']),
      mangaGenres: _genres(manga?['genres']),
    );
  }

  /// Reads a `UserStatistics.genres` slice: `[{ genre, count }]`.
  static List<GenreStat> _genres(Object? raw) {
    if (raw is! List) return const [];
    final out = <GenreStat>[];
    for (final item in raw) {
      final map = _asMap(item);
      final genre = (map?['genre'] as String?)?.trim() ?? '';
      if (genre.isEmpty) continue;
      out.add(
        GenreStat(genre: genre, count: (map?['count'] as num?)?.toInt() ?? 0),
      );
    }
    return out;
  }

  /// Flattens a `MediaListCollection` into entries, newest update first.
  static List<AccountListEntry> accountListEntries(Object? raw) {
    final map = _asMap(raw);
    final lists = map?['lists'];
    if (lists is! List) return const [];
    // Every `score` below is expressed in this format.
    final scoreFormat = ScoreFormat.fromWire(
      _asMap(_asMap(_asMap(map?['user'])?['mediaListOptions']))?['scoreFormat']
          as String?,
    );
    final out = <AccountListEntry>[];
    for (final list in lists) {
      final entries = _asMap(list)?['entries'];
      if (entries is! List) continue;
      for (final item in entries) {
        final entry = _asMap(item);
        if (entry == null) continue;
        final media = _media(entry['media']);
        if (media == null) continue;
        final seconds = (entry['updatedAt'] as num?)?.toInt();
        out.add(
          AccountListEntry(
            media: media,
            status: (entry['status'] as String?) ?? '',
            progress: (entry['progress'] as num?)?.toInt() ?? 0,
            progressVolumes: (entry['progressVolumes'] as num?)?.toInt(),
            score: (entry['score'] as num?)?.toDouble(),
            scoreFormat: scoreFormat,
            updatedAt: seconds == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          ),
        );
      }
    }
    out.sort((a, b) {
      final at = a.updatedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.updatedAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return out;
  }

  /// Parses `User.favourites.anime` into a page of titles.
  static MediaPage favouriteAnime(Object? raw, int fallbackPage) {
    final anime = _asMap(_asMap(_asMap(raw)?['favourites'])?['anime']);
    final info = _asMap(anime?['pageInfo']);
    return MediaPage(
      items: mediaList(anime?['nodes']),
      page: (info?['currentPage'] as num?)?.toInt() ?? fallbackPage,
      hasNextPage: info?['hasNextPage'] == true,
    );
  }

  /// Parses `Page.activities` (list / text / message activities).
  static List<UserActivity> activities(Object? raw) {
    final activities = _asMap(raw)?['activities'];
    if (activities is! List) return const [];
    final out = <UserActivity>[];
    for (final item in activities) {
      final map = _asMap(item);
      final id = (map?['id'] as num?)?.toInt();
      if (map == null || id == null) continue;
      final media = _media(map['media']);
      final seconds = (map['createdAt'] as num?)?.toInt() ?? 0;
      out.add(
        UserActivity(
          id: id,
          kind: switch (map['type']) {
            'TEXT' => ActivityKind.text,
            'MESSAGE' => ActivityKind.message,
            _ => ActivityKind.listUpdate,
          },
          createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          mediaId: media?.id,
          mediaType: media?.type,
          title: media?.title,
          coverUrl: media?.coverUrl,
          status: (map['status'] as String?)?.trim(),
          progress: int.tryParse('${map['progress'] ?? ''}'),
          text:
              (map['text'] as String?)?.trim() ??
              (map['message'] as String?)?.trim(),
        ),
      );
    }
    return out;
  }

  static PersonProfile? _profile(
    Map<String, dynamic> map, {
    bool withRole = false,
  }) {
    final id = (map['id'] as num?)?.toInt();
    if (id == null) return null;
    final name = _asMap(map['name']) ?? const <String, dynamic>{};
    final full = (name['full'] as String?)?.trim() ?? '';
    if (full.isEmpty) return null;
    final image = _asMap(map['image']) ?? const <String, dynamic>{};
    final role = withRole
        ? ((map['primaryOccupations'] as List?)
                  ?.map((e) => e.toString().replaceAll('_', ' '))
                  .where((e) => e.trim().isNotEmpty)
                  .join(' · ') ??
              '')
        : '';
    return PersonProfile(
      id: id,
      nameFull: full,
      nameNative: (name['native'] as String?)?.trim(),
      imageUrl: (image['large'] as String?)?.trim() ?? '',
      favourites: (map['favourites'] as num?)?.toInt() ?? 0,
      role: role,
    );
  }

  /// Merges one or more `MediaConnection`s: de-duplicates by media id
  /// (a voice actor can voice several characters in one show) and orders by
  /// popularity. A next page exists if any connection has one.
  static MediaPage _mergeConnections(
    List<Object?> connections,
    int fallbackPage,
  ) {
    final seen = <int>{};
    final items = <Media>[];
    var page = fallbackPage;
    var hasNext = false;
    for (final raw in connections) {
      final connection = _asMap(raw);
      if (connection == null) continue;
      final info = _asMap(connection['pageInfo']);
      page = (info?['currentPage'] as num?)?.toInt() ?? page;
      if (info?['hasNextPage'] == true) hasNext = true;
      for (final media in mediaList(connection['nodes'])) {
        if (seen.add(media.id)) items.add(media);
      }
    }
    items.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
    return MediaPage(items: items, page: page, hasNextPage: hasNext);
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
