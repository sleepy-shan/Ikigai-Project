/// GraphQL documents used against the AniList API.
///
/// Field selections are kept identical between list and detail queries so a
/// single mapper can be used for both.
library;

/// Public media lists (trending, browse, search, the calendar) always send
/// `isAdult: false`, so 18+ titles never appear in discovery surfaces. The
/// detail query is by id and intentionally does not filter.

/// Selection shared by every card and detail header.
const String kMediaListSelection = '''
  id
  idMal
  type
  format
  status
  season
  seasonYear
  episodes
  chapters
  volumes
  duration
  averageScore
  meanScore
  popularity
  favourites
  source
  countryOfOrigin
  startDate { year month day }
  endDate { year month day }
  siteUrl
  title { romaji english native }
  coverImage { extraLarge large color }
  bannerImage
  description(asHtml: false)
  genres
  nextAiringEpisode { episode airingAt timeUntilAiring }
  studios(isMain: true) { nodes { name } }
''';

/// Extra fields only needed on the detail page.
const String kMediaDetailSelection = '''$kMediaListSelection
  tags { name rank isMediaSpoiler }
  relations { edges { relationType(version: 2) node { id type
      title { romaji english native }
      coverImage { large }
      format status averageScore } } }
  recommendations(sort: RATING_DESC, perPage: 12) { nodes { mediaRecommendation { id type
      title { romaji english native }
      coverImage { large }
      format status averageScore } } }
''';

/// Trending + popular rails on the home page.
String trendingQuery({required bool detail}) => detail
    ? '''
query (\$page: Int, \$perPage: Int, \$type: MediaType) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    media(type: \$type, isAdult: false, sort: TRENDING_DESC) { $kMediaDetailSelection }
  }
}'''
    : '''
query (\$page: Int, \$perPage: Int, \$type: MediaType) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    media(type: \$type, isAdult: false, sort: TRENDING_DESC) { $kMediaListSelection }
  }
}''';

/// Browse with the filter set offered by the UI.
///
/// `isAdult` is a variable that defaults to false: only the Anime/Manga
/// browse screen's "Explicitly" filter ever sends true.
String browseQuery({required bool detail}) =>
    '''
query (
  \$page: Int, \$perPage: Int, \$type: MediaType, \$sort: [MediaSort],
  \$search: String, \$genre: String, \$status: MediaStatus,
  \$format: MediaFormat, \$season: MediaSeason, \$seasonYear: Int,
  \$source: MediaSource, \$countryOfOrigin: CountryCode, \$minScore: Int,
  \$isAdult: Boolean = false
) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    media(
      type: \$type, isAdult: \$isAdult, sort: \$sort, search: \$search,
      genre: \$genre, status: \$status, format: \$format, season: \$season,
      seasonYear: \$seasonYear, source: \$source,
      countryOfOrigin: \$countryOfOrigin, averageScore_greater: \$minScore
    ) { ${detail ? kMediaDetailSelection : kMediaListSelection} }
  }
}''';

/// Single media lookup used by the detail screen.
const String kMediaDetailQuery =
    '''
query (\$id: Int) {
  Media(id: \$id) { $kMediaDetailSelection }
}''';

/// Authenticated viewer lookup used to validate an AniList OAuth token.
const String kViewerQuery = '''
query {
  Viewer {
    id
    name
    avatar { large }
  }
}''';

/// Airing schedule for a time window (epoch seconds).
const String kAiringScheduleQuery = '''
query (\$page: Int, \$perPage: Int, \$airingAt_greater: Int, \$airingAt_lesser: Int) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    airingSchedules(
      airingAt_greater: \$airingAt_greater,
      airingAt_lesser: \$airingAt_lesser,
      sort: TIME
    ) {
      id
      episode
      airingAt
      media {
        id
        type
        isAdult
        episodes
        averageScore
        title { romaji english native }
        coverImage { large }
      }
    }
  }
}''';

/// Manga releases whose start date falls inside a window.
///
/// `startDate_greater` / `startDate_lesser` are exclusive `FuzzyDateInt`s
/// (`YYYYMMDD`), so the filter runs on AniList's side and every week returns
/// its own titles. Sorted by popularity so a capped fetch keeps the titles
/// people actually look for; the app groups them by day afterwards.
const String kMangaReleasesQuery = '''
query (\$page: Int, \$perPage: Int, \$startDate_greater: FuzzyDateInt, \$startDate_lesser: FuzzyDateInt) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    media(
      type: MANGA,
      isAdult: false,
      startDate_greater: \$startDate_greater,
      startDate_lesser: \$startDate_lesser,
      sort: POPULARITY_DESC
    ) {
      id
      type
      format
      status
      chapters
      volumes
      averageScore
      popularity
      startDate { year month day }
      title { romaji english native }
      coverImage { large color }
    }
  }
}''';

/// Character search/ranking for the Search > Characters tab.
///
/// An omitted/empty `search` returns the favourites ranking (Page 1).
const String kCharacterSearchQuery = '''
query (\$page: Int, \$perPage: Int, \$search: String) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage }
    characters(search: \$search, sort: FAVOURITES_DESC) {
      id
      name { full native }
      image { large }
      favourites
    }
  }
}''';

/// Staff search/ranking for the Search > Staff tab.
const String kStaffSearchQuery = '''
query (\$page: Int, \$perPage: Int, \$search: String) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage }
    staff(search: \$search, sort: FAVOURITES_DESC) {
      id
      name { full native }
      image { large }
      favourites
      primaryOccupations
    }
  }
}''';

/// Studio search/ranking for the Search > Studios tab.
const String kStudioSearchQuery = '''
query (\$page: Int, \$perPage: Int, \$search: String) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage }
    studios(search: \$search, sort: FAVOURITES_DESC) {
      id
      name
      favourites
      isAnimationStudio
    }
  }
}''';

/// Compact media fields for a person's works grid (poster cards only need
/// these, which keeps two paged connections per request cheap).
const String kMediaCardSelection = '''
  id
  type
  format
  status
  seasonYear
  episodes
  chapters
  averageScore
  popularity
  startDate { year month day }
  title { romaji english native }
  coverImage { large color }
''';

/// Staff profile plus the titles they worked on.
///
/// Voice actors are linked to media through the characters they voice
/// (`characterMedia`), while directors/mangaka/composers use `staffMedia`,
/// so both connections are requested and merged by the mapper.
const String kStaffWorksQuery = '''
query (\$id: Int, \$page: Int, \$perPage: Int) {
  Staff(id: \$id) {
    id
    name { full native }
    image { large }
    favourites
    primaryOccupations
    characterMedia(page: \$page, perPage: \$perPage, sort: POPULARITY_DESC) {
      pageInfo { currentPage hasNextPage }
      nodes { $kMediaCardSelection }
    }
    staffMedia(page: \$page, perPage: \$perPage, sort: POPULARITY_DESC) {
      pageInfo { currentPage hasNextPage }
      nodes { $kMediaCardSelection }
    }
  }
}''';

/// Character profile plus the series they appear in.
const String kCharacterWorksQuery = '''
query (\$id: Int, \$page: Int, \$perPage: Int) {
  Character(id: \$id) {
    id
    name { full native }
    image { large }
    favourites
    media(page: \$page, perPage: \$perPage, sort: POPULARITY_DESC) {
      pageInfo { currentPage hasNextPage }
      nodes { $kMediaCardSelection }
    }
  }
}''';

/// Studio profile plus the titles it produced (most popular first).
const String kStudioWorksQuery = '''
query (\$id: Int, \$page: Int, \$perPage: Int) {
  Studio(id: \$id) {
    id
    name
    favourites
    isAnimationStudio
    media(page: \$page, perPage: \$perPage, sort: POPULARITY_DESC) {
      pageInfo { currentPage hasNextPage }
      nodes { $kMediaCardSelection }
    }
  }
}''';

/// The signed-in user's recent notifications about titles: new episodes,
/// newly added related titles and site-data changes. Requires a token.
const String kNotificationsQuery = '''
query (\$perPage: Int) {
  Page(page: 1, perPage: \$perPage) {
    notifications(type_in: [AIRING, RELATED_MEDIA_ADDITION, MEDIA_DATA_CHANGE]) {
      ... on AiringNotification {
        id
        type
        episode
        createdAt
        media { $kMediaCardSelection }
      }
      ... on RelatedMediaAdditionNotification {
        id
        type
        createdAt
        media { $kMediaCardSelection }
      }
      ... on MediaDataChangeNotification {
        id
        type
        reason
        createdAt
        media { $kMediaCardSelection }
      }
    }
  }
}''';

/// Profile header + anime/manga statistics for the signed-in user.
///
/// `statistics.anime.statuses` carries one row per list status (CURRENT,
/// PLANNING, COMPLETED, PAUSED, DROPPED, REPEATING) and `favourites.anime`
/// gives the favourites total, so the profile can mirror AniList's own
/// statistics strip. The `genres(limit:)` slices power the genre overview
/// and `minutesWatched` is turned into "days watched" by the UI.
const String kViewerProfileQuery = '''
query {
  Viewer {
    id
    name
    avatar { large }
    bannerImage
    favourites { anime { pageInfo { total } } }
    statistics {
      anime {
        count
        episodesWatched
        minutesWatched
        meanScore
        statuses { status count }
        genres(limit: 10) { genre count }
      }
      manga {
        count
        chaptersRead
        volumesRead
        meanScore
        genres(limit: 10) { genre count }
      }
    }
  }
}''';

/// One section of the user's AniList **anime** list.
///
/// Pass `status: null` for the full collection ("All"); AniList then returns
/// every status group and the mapper flattens them. Requires a token because
/// it reads the authenticated user's private list.
///
/// `user.mediaListOptions.scoreFormat` is requested because every entry's
/// `score` is expressed in that format (100-point, 10-point, 5-star, smileys),
/// so it is meaningless without it.
const String kMediaListCollectionQuery = '''
query (\$userId: Int, \$type: MediaType, \$status: MediaListStatus) {
  MediaListCollection(userId: \$userId, type: \$type, status: \$status) {
    user { mediaListOptions { scoreFormat } }
    lists {
      name
      status
      entries {
        id
        status
        score
        progress
        progressVolumes
        updatedAt
        media { $kMediaCardSelection }
      }
    }
  }
}''';

/// The user's favourited anime (a connection separate from list statuses).
const String kFavouriteAnimeQuery = '''
query (\$userId: Int, \$page: Int, \$perPage: Int) {
  User(id: \$userId) {
    favourites {
      anime(page: \$page, perPage: \$perPage) {
        pageInfo { currentPage hasNextPage }
        nodes { $kMediaCardSelection }
      }
    }
  }
}''';

/// The signed-in user's recent activity: list updates, text posts and
/// messages, newest first. Requires a token.
const String kViewerActivityQuery = '''
query (\$userId: Int, \$perPage: Int) {
  Page(page: 1, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage }
    activities(userId: \$userId, sort: ID_DESC) {
      ... on ListActivity {
        id
        type
        status
        progress
        createdAt
        media {
          id
          type
          title { romaji english native }
          coverImage { large color }
        }
      }
      ... on TextActivity {
        id
        type
        text
        createdAt
      }
      ... on MessageActivity {
        id
        type
        message
        createdAt
      }
    }
  }
}''';
