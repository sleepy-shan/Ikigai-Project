import 'media.dart';

/// One title the user recently opened, kept so they can jump back to it.
///
/// Only the fields needed to draw a row are stored (title + cover), so the
/// History screen renders without any AniList request.
class HistoryEntry {
  const HistoryEntry({
    required this.mediaId,
    required this.type,
    required this.title,
    required this.viewedAt,
    this.coverUrl,
  });

  factory HistoryEntry.fromMedia(Media media, {DateTime? viewedAt}) {
    return HistoryEntry(
      mediaId: media.id,
      type: media.type,
      title: media.title,
      coverUrl: media.coverUrl.isEmpty ? null : media.coverUrl,
      viewedAt: viewedAt ?? DateTime.now(),
    );
  }

  /// Returns null when [json] is not a usable entry, so one bad record never
  /// discards the rest of the history.
  static HistoryEntry? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final viewed = DateTime.tryParse('${json['viewedAt']}');
    if (id is! int || title is! String || viewed == null) return null;
    final cover = json['cover'];
    return HistoryEntry(
      mediaId: id,
      type: MediaType.fromWire('${json['type']}'),
      title: title,
      coverUrl: cover is String && cover.isNotEmpty ? cover : null,
      viewedAt: viewed,
    );
  }

  final int mediaId;
  final MediaType type;
  final String title;
  final String? coverUrl;
  final DateTime viewedAt;

  Map<String, Object?> toJson() => {
    'id': mediaId,
    'type': type.anilistValue,
    'title': title,
    'cover': coverUrl,
    'viewedAt': viewedAt.toIso8601String(),
  };
}
