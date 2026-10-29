import 'media.dart';

/// One item on the airing/release calendar.
class AiringScheduleItem {
  const AiringScheduleItem({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.title,
    required this.episode,
    required this.airingAt,
    this.coverUrl,
    this.totalEpisodes,
    this.averageScore,
    this.popularity,
    this.format = MediaFormat.unknown,
    this.platform,
  });

  final int id;
  final int mediaId;
  final MediaType mediaType;
  final String title;
  final String? coverUrl;

  /// Episode number (1-based) airing at [airingAt].
  final int episode;

  /// Epoch seconds when the episode airs.
  final int airingAt;

  /// Total episode count reported by AniList, when known.
  final int? totalEpisodes;

  /// AniList average score (0-100 scale), when known.
  final int? averageScore;

  /// AniList popularity (number of users with the title on a list); used by
  /// the calendar's "Popularity" sort.
  final int? popularity;

  /// TV, ONA, OVA, ... shown as the badge on the poster.
  final MediaFormat format;

  /// Name of the first streaming site AniList lists for the title
  /// ("Crunchyroll", "Netflix", ...), when there is one.
  final String? platform;
}
