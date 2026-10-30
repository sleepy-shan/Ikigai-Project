import 'package:gql/ast.dart' show DocumentNode;
import 'package:graphql_flutter/graphql_flutter.dart';

/// Shared field selection. List pages and the detail page use the SAME
/// fragment on purpose: graphql_flutter normalizes by `__typename:id`, so a
/// card the user already saw is a complete `Media:123` record in the cache and
/// opening its detail page can be answered with zero network.
///
/// Never put user-specific fields (`mediaListEntry`, `isFavourite`) in this
/// fragment: they would be stored on the shared `Media:123` record and leak
/// across accounts / go stale after sign-out.
const String _mediaCardFragment = r'''
fragment MediaCard on Media {
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
  nextAiringEpisode { episode airingAt }
  studios(isMain: true) { nodes { id name } }
}
''';

/// Browse / trending / search. One document, variables decide the rail.
/// Null variables are simply omitted by the caller.
final DocumentNode browseMediaDoc = gql('''
query BrowseMedia(
  \$page: Int, \$perPage: Int, \$type: MediaType, \$sort: [MediaSort],
  \$search: String, \$status: MediaStatus, \$season: MediaSeason,
  \$seasonYear: Int, \$isAdult: Boolean = false
) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { currentPage hasNextPage total }
    media(
      type: \$type, sort: \$sort, search: \$search, status: \$status,
      season: \$season, seasonYear: \$seasonYear, isAdult: \$isAdult
    ) { ...MediaCard }
  }
}
$_mediaCardFragment
''');

/// Detail page (same fragment as the cards, see note above).
final DocumentNode mediaByIdDoc = gql('''
query MediaById(\$id: Int) {
  Media(id: \$id) { ...MediaCard }
}
$_mediaCardFragment
''');

/// The signed-in user's entry for ONE title. Light (one row) and exactly what
/// a "+1 episode" button needs. Requires a Bearer token.
final DocumentNode myEntryForMediaDoc = gql(r'''
query MyEntryForMedia($id: Int) {
  Media(id: $id) {
    id
    mediaListEntry {
      id
      mediaId
      status
      progress
      score(format: POINT_100)
      updatedAt
    }
  }
}
''');

/// Create-or-update. AniList upserts on `mediaId`.
/// Send ABSOLUTE progress (not "+1") so a retried/duplicated request is
/// idempotent.
final DocumentNode saveMediaListEntryDoc = gql(r'''
mutation SaveMediaListEntry(
  $mediaId: Int, $status: MediaListStatus, $progress: Int, $scoreRaw: Int
) {
  SaveMediaListEntry(
    mediaId: $mediaId, status: $status, progress: $progress, scoreRaw: $scoreRaw
  ) {
    id
    mediaId
    status
    progress
    score(format: POINT_100)
    updatedAt
  }
}
''');

/// Removes ONE entry from the user's AniList list. Needs the MediaList id
/// (not the media id), which comes from the tracked-entry query.
final DocumentNode deleteMediaListEntryDoc = gql(r'''
mutation DeleteMediaListEntry($id: Int) {
  DeleteMediaListEntry(id: $id) {
    deleted
  }
}
''');
