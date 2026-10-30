import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_list_entry.freezed.dart';
part 'media_list_entry.g.dart';

/// AniList `MediaListStatus`.
@JsonEnum()
enum MediaListStatus {
  @JsonValue('CURRENT')
  current,
  @JsonValue('PLANNING')
  planning,
  @JsonValue('COMPLETED')
  completed,
  @JsonValue('DROPPED')
  dropped,
  @JsonValue('PAUSED')
  paused,
  @JsonValue('REPEATING')
  repeating;

  /// Wire value for mutation variables.
  String get wire => switch (this) {
    current => 'CURRENT',
    planning => 'PLANNING',
    completed => 'COMPLETED',
    dropped => 'DROPPED',
    paused => 'PAUSED',
    repeating => 'REPEATING',
  };
}

/// The signed-in user's list entry for one title (AniList `MediaList`).
///
/// `score` is always requested as `score(format: POINT_100)` so it is
/// independent of the user's chosen score format (0-100 here).
@freezed
abstract class MediaListEntry with _$MediaListEntry {
  const MediaListEntry._();

  const factory MediaListEntry({
    /// MediaList id. Null for an optimistic entry that does not exist yet.
    int? id,
    required int mediaId,
    @JsonKey(unknownEnumValue: MediaListStatus.planning)
    @Default(MediaListStatus.planning)
    MediaListStatus status,
    @Default(0) int progress,
    @Default(0.0) double score,
    int? updatedAt,
  }) = _MediaListEntry;

  factory MediaListEntry.fromJson(Map<String, dynamic> json) =>
      _$MediaListEntryFromJson(json);

  bool get isNew => id == null;
}
