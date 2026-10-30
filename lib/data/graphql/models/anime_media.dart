// Strongly typed AniList models (Freezed 3 + json_serializable).
//
// Field names/shape mirror the `MediaCard` fragment in anilist_documents.dart.
// Keep the two in sync: every field here must be selected by the fragment.
//
// Run: dart run build_runner build --delete-conflicting-outputs
import 'package:freezed_annotation/freezed_annotation.dart';

// Reuse the enums your app already has (they already know the wire values).
import '../../models/media.dart'
    show Media, MediaFormat, MediaSeason, MediaStatus, MediaType, NextAiringEpisode;

part 'anime_media.freezed.dart';
part 'anime_media.g.dart';

// ---------------------------------------------------------------------------
// Enum converters. AniList can add enum values at any time; the existing
// `fromWire` helpers fall back to `unknown` instead of throwing, so a new
// AniList value can never crash parsing of a whole page.
// ---------------------------------------------------------------------------
class MediaTypeConverter implements JsonConverter<MediaType, String?> {
  const MediaTypeConverter();
  @override
  MediaType fromJson(String? json) => MediaType.fromWire(json);
  @override
  String toJson(MediaType object) => object.anilistValue;
}

class MediaFormatConverter implements JsonConverter<MediaFormat, String?> {
  const MediaFormatConverter();
  @override
  MediaFormat fromJson(String? json) => MediaFormat.fromWire(json);
  @override
  String toJson(MediaFormat object) => object.wire;
}

class MediaStatusConverter implements JsonConverter<MediaStatus, String?> {
  const MediaStatusConverter();
  @override
  MediaStatus fromJson(String? json) => MediaStatus.fromWire(json);
  @override
  String toJson(MediaStatus object) => object.wire;
}

class MediaSeasonConverter implements JsonConverter<MediaSeason, String?> {
  const MediaSeasonConverter();
  @override
  MediaSeason fromJson(String? json) => MediaSeason.fromWire(json);
  @override
  String toJson(MediaSeason object) => object.wire;
}

// ---------------------------------------------------------------------------
// Small value objects
// ---------------------------------------------------------------------------
@freezed
abstract class MediaTitle with _$MediaTitle {
  const MediaTitle._();

  const factory MediaTitle({
    String? romaji,
    String? english,
    // `native` is awkward as a Dart identifier in some tooling; rename it.
    @JsonKey(name: 'native') String? nativeTitle,
  }) = _MediaTitle;

  factory MediaTitle.fromJson(Map<String, dynamic> json) =>
      _$MediaTitleFromJson(json);

  /// English, else romaji, else native.
  String get best => english ?? romaji ?? nativeTitle ?? 'Untitled';
}

@freezed
abstract class CoverImage with _$CoverImage {
  const CoverImage._();

  const factory CoverImage({String? extraLarge, String? large, String? color}) =
      _CoverImage;

  factory CoverImage.fromJson(Map<String, dynamic> json) =>
      _$CoverImageFromJson(json);

  String? get best => extraLarge ?? large;
}

/// AniList `FuzzyDate`: any component can be null.
@freezed
abstract class FuzzyDate with _$FuzzyDate {
  const FuzzyDate._();

  const factory FuzzyDate({int? year, int? month, int? day}) = _FuzzyDate;

  factory FuzzyDate.fromJson(Map<String, dynamic> json) =>
      _$FuzzyDateFromJson(json);

  /// "2026-10-01" style string (matches what `Media.startDate` expects);
  /// null when the year is unknown.
  String? get iso {
    final y = year;
    if (y == null) return null;
    final m = (month ?? 1).toString().padLeft(2, '0');
    final d = (day ?? 1).toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

@freezed
abstract class AiringInfo with _$AiringInfo {
  const factory AiringInfo({required int episode, required int airingAt}) =
      _AiringInfo;

  factory AiringInfo.fromJson(Map<String, dynamic> json) =>
      _$AiringInfoFromJson(json);
}

@freezed
abstract class StudioNode with _$StudioNode {
  const factory StudioNode({int? id, required String name}) = _StudioNode;

  factory StudioNode.fromJson(Map<String, dynamic> json) =>
      _$StudioNodeFromJson(json);
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class StudioConnection with _$StudioConnection {
  const factory StudioConnection({@Default([]) List<StudioNode> nodes}) =
      _StudioConnection;

  factory StudioConnection.fromJson(Map<String, dynamic> json) =>
      _$StudioConnectionFromJson(json);
}

// ---------------------------------------------------------------------------
// The main entity
// ---------------------------------------------------------------------------
/// One AniList `Media` (anime OR manga: AniList uses one type for both).
@Freezed(makeCollectionsUnmodifiable: false)
abstract class AnimeMedia with _$AnimeMedia {
  const AnimeMedia._();

  const factory AnimeMedia({
    required int id,
    int? idMal,
    @MediaTypeConverter() @JsonKey(includeIfNull: true) @Default(MediaType.anime) MediaType type,
    @MediaFormatConverter() @JsonKey(includeIfNull: true) @Default(MediaFormat.unknown) MediaFormat format,
    @MediaStatusConverter() @JsonKey(includeIfNull: true) @Default(MediaStatus.unknown) MediaStatus status,
    @MediaSeasonConverter() @JsonKey(includeIfNull: true) @Default(MediaSeason.unknown) MediaSeason season,
    int? seasonYear,
    int? episodes,
    int? chapters,
    int? volumes,
    int? duration,
    int? averageScore,
    int? meanScore,
    int? popularity,
    int? favourites,
    String? source,
    String? countryOfOrigin,
    FuzzyDate? startDate,
    FuzzyDate? endDate,
    String? siteUrl,
    @Default(MediaTitle()) MediaTitle title,
    CoverImage? coverImage,
    String? bannerImage,
    String? description,
    @Default([]) List<String> genres,
    AiringInfo? nextAiringEpisode,
    @Default(StudioConnection()) StudioConnection studios,
  }) = _AnimeMedia;

  /// `json` is the map for ONE media object, e.g. an element of `Page.media`.
  factory AnimeMedia.fromJson(Map<String, dynamic> json) =>
      _$AnimeMediaFromJson(json);

  /// Adapter to the UI model your screens already use, so the migration to
  /// graphql_flutter does not force a rewrite of 40 widgets. Delete this once
  /// the UI consumes AnimeMedia directly.
  Media toMedia() => Media(
    id: id,
    type: type,
    title: title.best,
    coverUrl: coverImage?.best ?? '',
    bannerUrl: bannerImage,
    description: description,
    genres: genres,
    format: format,
    status: status,
    season: season,
    seasonYear: seasonYear,
    episodes: episodes,
    chapters: chapters,
    volumes: volumes,
    duration: duration,
    averageScore: averageScore,
    meanScore: meanScore,
    popularity: popularity,
    favourites: favourites,
    studios: [for (final s in studios.nodes) s.name],
    source: source,
    countryOfOrigin: countryOfOrigin,
    startDate: startDate?.iso,
    endDate: endDate?.iso,
    siteUrl: siteUrl,
    nextAiringEpisode: nextAiringEpisode == null
        ? null
        : NextAiringEpisode(
            episode: nextAiringEpisode!.episode,
            airingAt: nextAiringEpisode!.airingAt,
          ),
  );
}

// ---------------------------------------------------------------------------
// Page wrapper (`Page { pageInfo media { ... } }`)
// ---------------------------------------------------------------------------
@freezed
abstract class PageInfo with _$PageInfo {
  const factory PageInfo({
    @Default(1) int currentPage,
    @Default(false) bool hasNextPage,
    int? total,
  }) = _PageInfo;

  factory PageInfo.fromJson(Map<String, dynamic> json) =>
      _$PageInfoFromJson(json);
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class AnimePage with _$AnimePage {
  const factory AnimePage({
    @Default(PageInfo()) PageInfo pageInfo,
    @Default([]) List<AnimeMedia> media,
  }) = _AnimePage;

  /// Pass the `Page` object (`data['Page']`), not the whole `data` map.
  factory AnimePage.fromJson(Map<String, dynamic> json) =>
      _$AnimePageFromJson(json);
}
