import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/graphql/anilist_documents.dart';
import '../data/graphql/models/anime_media.dart';
import '../data/graphql/models/media_list_entry.dart';
import '../data/models/media.dart' show MediaSeason, MediaSort, MediaStatus, MediaType;
import 'graphql_providers.dart';
import 'providers.dart'; // authStateProvider
import 'swr.dart';

part 'anime_providers.freezed.dart';

/// Family key for a catalog page. Freezed gives value equality, so two widgets
/// asking for the same rail share ONE provider, one stream and one request.
@freezed
abstract class AnimePageArgs with _$AnimePageArgs {
  const AnimePageArgs._();

  const factory AnimePageArgs({
    @Default(MediaType.anime) MediaType type,
    @Default(MediaSort.trending) MediaSort sort,
    @Default(1) int page,
    @Default(20) int perPage, // keep <= 25: normalizing big pages is main-thread work on web
    String? search,
    MediaStatus? status,
    MediaSeason? season,
    int? seasonYear,
  }) = _AnimePageArgs;

  /// Null variables are omitted so AniList never sees `search: null`.
  Map<String, dynamic> get variables => {
    'page': page,
    'perPage': perPage,
    'type': type.anilistValue,
    'sort': [sort.wire],
    if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
    if (status != null) 'status': status!.wire,
    if (season != null) 'season': season!.wire,
    if (seasonYear != null) 'seasonYear': seasonYear,
  };
}

/// Shared by [animePageProvider] and the home-page rails.
Stream<SwrResult<AnimePage>> animePageStream(Ref ref, AnimePageArgs args) =>
    swrQuery<AnimePage>(
      ref,
      document: browseMediaDoc,
      operation: 'BrowseMedia',
      variables: args.variables,
      parse: (data) => AnimePage.fromJson(data['Page'] as Map<String, dynamic>),
      // Search results go stale faster than a "top rated" rail.
      ttl: args.search == null
          ? const Duration(minutes: 10)
          : const Duration(minutes: 2),
    );

/// Catalog list (rails, browse, search). Public: works signed out.
/// Emits twice on a cold-but-cached visit: cache (0 ms) then network.
final animePageProvider = StreamProvider.autoDispose
    .family<SwrResult<AnimePage>, AnimePageArgs>(
      animePageStream,
      retry: noProviderRetry,
    );

/// One title. Widgets that need a single field should select it so they only
/// rebuild when that field changes:
///   ref.watch(animeByIdProvider(id).select((a) => a.value?.data.title.best))
///
/// Because it shares the MediaCard fragment with the lists, a card
/// the user already saw opens its detail page straight from cache.
final animeByIdProvider = StreamProvider.autoDispose
    .family<SwrResult<AnimeMedia>, int>(
      (ref, id) => swrQuery<AnimeMedia>(
        ref,
        document: mediaByIdDoc,
        operation: 'MediaById',
        variables: {'id': id},
        parse: (data) =>
            AnimeMedia.fromJson(data['Media'] as Map<String, dynamic>),
        ttl: const Duration(minutes: 30),
      ),
      retry: noProviderRetry,
    );

/// The signed-in user's entry for a title (server truth, SWR). Null data =
/// signed out or not on the user's list.
final trackedEntryProvider = StreamProvider.autoDispose
    .family<SwrResult<MediaListEntry?>, int>((ref, mediaId) {
      final userId = ref.watch(authStateProvider.select((a) => a.value?.id));
      if (userId == null) {
        return Stream.value(
          const SwrResult<MediaListEntry?>(
            null,
            isRefreshing: false,
            fromCache: false,
          ),
        );
      }
      return swrQuery<MediaListEntry?>(
        ref,
        document: myEntryForMediaDoc,
        // User id in the key so freshness is never shared between accounts.
        operation: 'MyEntry:$userId',
        variables: {'id': mediaId},
        parse: (data) {
          final raw = (data['Media'] as Map<String, dynamic>?)?['mediaListEntry'];
          return raw == null
              ? null
              : MediaListEntry.fromJson(raw as Map<String, dynamic>);
        },
        ttl: const Duration(minutes: 2),
      );
    }, retry: noProviderRetry);
