/// Whether a title is anime or manga.
enum MediaType {
  anime('ANIME', 'Anime'),
  manga('MANGA', 'Manga');

  const MediaType(this.anilistValue, this.label);

  /// Wire value used by the AniList API and route paths.
  final String anilistValue;
  final String label;

  /// Parses "ANIME"/"MANGA" (case-insensitive) coming from a URL or API.
  static MediaType fromWire(String? value) {
    if (value == null) return MediaType.anime;
    final upper = value.toUpperCase();
    if (upper == 'MANGA') return MediaType.manga;
    return MediaType.anime;
  }

  /// The noun used for progress units ("episode" vs "chapter").
  String get unit => this == MediaType.anime ? 'episode' : 'chapter';

  /// Plural progress unit ("episodes" / "chapters").
  String get unitPlural => this == MediaType.anime ? 'episodes' : 'chapters';

  /// Verb used for a "current" list entry ("Watching" / "Reading").
  String get trackingVerb => this == MediaType.anime ? 'Watching' : 'Reading';
}

/// Release format of a title.
enum MediaFormat {
  tv('TV', 'TV'),
  tvShort('TV_SHORT', 'TV Short'),
  movie('MOVIE', 'Movie'),
  special('SPECIAL', 'Special'),
  ova('OVA', 'OVA'),
  ona('ONA', 'ONA'),
  music('MUSIC', 'Music'),
  manga('MANGA', 'Manga'),
  novel('NOVEL', 'Novel'),
  oneShot('ONE_SHOT', 'One Shot'),
  unknown('UNKNOWN', 'Unknown');

  const MediaFormat(this.wire, this.label);

  final String wire;
  final String label;

  static MediaFormat fromWire(String? value) {
    if (value == null) return MediaFormat.unknown;
    return MediaFormat.values.firstWhere(
      (f) => f.wire == value.toUpperCase(),
      orElse: () => MediaFormat.unknown,
    );
  }
}

/// Publication/airing status of a title.
enum MediaStatus {
  finished('FINISHED', 'Finished'),
  releasing('RELEASING', 'Releasing'),
  notYetReleased('NOT_YET_RELEASED', 'Not yet released'),
  cancelled('CANCELLED', 'Cancelled'),
  hiatus('HIATUS', 'On hiatus'),
  unknown('UNKNOWN', 'Unknown');

  const MediaStatus(this.wire, this.label);

  final String wire;
  final String label;

  static MediaStatus fromWire(String? value) {
    if (value == null) return MediaStatus.unknown;
    return MediaStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => MediaStatus.unknown,
    );
  }
}

/// Anime season of release.
enum MediaSeason {
  winter('WINTER', 'Winter'),
  spring('SPRING', 'Spring'),
  summer('SUMMER', 'Summer'),
  fall('FALL', 'Fall'),
  unknown('UNKNOWN', 'Unknown');

  const MediaSeason(this.wire, this.label);

  final String wire;
  final String label;

  static MediaSeason fromWire(String? value) {
    if (value == null) return MediaSeason.unknown;
    return MediaSeason.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => MediaSeason.unknown,
    );
  }
}

/// Sort options for browse and search.
enum MediaSort {
  trending('TRENDING_DESC', 'Trending'),
  popularity('POPULARITY_DESC', 'Popularity'),
  score('SCORE_DESC', 'Score'),
  favourites('FAVOURITES_DESC', 'Favorites'),
  startDate('START_DATE_DESC', 'Newest'),
  updated('UPDATED_AT_DESC', 'Recently updated'),
  titleRomaji('TITLE_ROMAJI', 'A → Z'),

  /// Relevance to the search text. Only meaningful together with a search
  /// term, so it is left out of [browseOptions].
  searchMatch('SEARCH_MATCH', 'Best match');

  const MediaSort(this.wire, this.label);

  final String wire;
  final String label;

  /// Sorts that make sense without a search term (browse pages, filters).
  static final List<MediaSort> browseOptions = [
    for (final s in values)
      if (s != searchMatch) s,
  ];
}

/// Original material a title is adapted from (AniList `MediaSource`).
enum MediaSource {
  original('ORIGINAL', 'Original'),
  manga('MANGA', 'Manga'),
  lightNovel('LIGHT_NOVEL', 'Light Novel'),
  webNovel('WEB_NOVEL', 'Web Novel'),
  novel('NOVEL', 'Novel'),
  visualNovel('VISUAL_NOVEL', 'Visual Novel'),
  videoGame('VIDEO_GAME', 'Video Game'),
  doujinshi('DOUJINSHI', 'Doujinshi'),
  comic('COMIC', 'Comic'),
  liveAction('LIVE_ACTION', 'Live Action'),
  anime('ANIME', 'Anime'),
  other('OTHER', 'Other');

  const MediaSource(this.wire, this.label);

  final String wire;
  final String label;
}

/// Countries of origin offered by AniList (`countryOfOrigin` ISO codes).
const Map<String, String> kCountries = {
  'JP': 'Japan',
  'KR': 'South Korea',
  'CN': 'China',
  'TW': 'Taiwan',
};

/// Minimum average scores offered by the Score filter (0-100 scale; shown
/// to the user on a 10-point scale, e.g. 75 -> "≥ 7.5").
const List<int> kScoreThresholds = [90, 85, 80, 75, 70, 65, 60, 50];

/// Genres offered by the AniList API (their fixed `GenreCollection`).
const List<String> kGenres = [
  'Action',
  'Adventure',
  'Comedy',
  'Drama',
  'Ecchi',
  'Fantasy',
  'Horror',
  'Mahou Shoujo',
  'Mecha',
  'Music',
  'Mystery',
  'Psychological',
  'Romance',
  'Sci-Fi',
  'Slice of Life',
  'Sports',
  'Supernatural',
  'Thriller',
];

/// A title (anime or manga) as displayed anywhere in the app.
class Media {
  const Media({
    required this.id,
    required this.type,
    required this.title,
    required this.coverUrl,
    this.bannerUrl,
    this.description,
    this.genres = const [],
    this.tags = const [],
    this.format = MediaFormat.unknown,
    this.status = MediaStatus.unknown,
    this.season = MediaSeason.unknown,
    this.seasonYear,
    this.episodes,
    this.chapters,
    this.volumes,
    this.duration,
    this.averageScore,
    this.meanScore,
    this.popularity,
    this.favourites,
    this.studios = const [],
    this.source,
    this.countryOfOrigin,
    this.startDate,
    this.endDate,
    this.siteUrl,
    this.nextAiringEpisode,
    this.relations = const [],
    this.recommendations = const [],
  });

  final int id;
  final MediaType type;

  /// Best available display title (English, else romaji, else native).
  final String title;
  final String coverUrl;
  final String? bannerUrl;
  final String? description;
  final List<String> genres;

  /// AniList spoiler tags with their rank, used on the detail page.
  final List<MediaTag> tags;
  final MediaFormat format;
  final MediaStatus status;
  final MediaSeason season;
  final int? seasonYear;

  /// Episode count (anime) or chapter count (manga).
  final int? episodes;
  final int? chapters;
  final int? volumes;

  /// Episode length in minutes (anime only).
  final int? duration;
  final int? averageScore;
  final int? meanScore;
  final int? popularity;
  final int? favourites;
  final List<String> studios;
  final String? source;
  final String? countryOfOrigin;

  /// ISO-8601 dates ("2026-10-01").
  final String? startDate;
  final String? endDate;
  final String? siteUrl;

  final NextAiringEpisode? nextAiringEpisode;
  final List<MediaEdge> relations;
  final List<Media> recommendations;

  /// Total progress units known for the title (episodes or chapters).
  int? get totalUnits => type == MediaType.anime ? episodes : chapters;

  /// True when AniList reports more units than [progress].
  bool hasUnitsBeyond(int progress) {
    final total = totalUnits;
    return total != null && total > progress;
  }
}

/// AniList `MediaTag` — category with a relevance rank.
class MediaTag {
  const MediaTag({required this.name, required this.rank});

  final String name;
  final int rank;
}

/// Next episode that will air, shown on cards and detail pages.
class NextAiringEpisode {
  const NextAiringEpisode({required this.episode, required this.airingAt});

  final int episode;

  /// Epoch seconds.
  final int airingAt;
}

/// A relation edge to another title (sequel, prequel, side story, ...).
class MediaEdge {
  const MediaEdge({required this.relationType, required this.media});

  final String relationType;
  final Media media;
}

/// A page of results plus pagination info.
class MediaPage {
  const MediaPage({
    required this.items,
    required this.page,
    required this.hasNextPage,
    this.total,
  });

  final List<Media> items;
  final int page;
  final bool hasNextPage;

  /// Total matching titles reported by the API (`pageInfo.total`), if known.
  final int? total;

  static const MediaPage empty = MediaPage(
    items: [],
    page: 1,
    hasNextPage: false,
  );
}
