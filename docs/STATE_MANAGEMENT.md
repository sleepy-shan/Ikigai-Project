# State management

How Ikigai organises state with Riverpod: providers, controllers, async patterns,
caching, sharing, and invalidation.

## Contents

- [Riverpod architecture](#riverpod-architecture)
- [Provider organisation](#provider-organisation)
- [Notifier and controller responsibilities](#notifier-and-controller-responsibilities)
- [State lifecycle](#state-lifecycle)
- [Async state handling](#async-state-handling)
- [Data sharing between screens](#data-sharing-between-screens)
- [State updates and invalidation](#state-updates-and-invalidation)
- [Debouncing and throttling](#debouncing-and-throttling)
- [Error and loading states](#error-and-loading-states)
- [Debounced list synchronisation](#debounced-list-synchronisation)

---

## Riverpod architecture

| Property | Value |
| --- | --- |
| Package | `flutter_riverpod` **3.4.3** / `riverpod` **3.4.3** |
| Provider style | **Hand-written** top-level `final …Provider = …` globals |
| Codegen | **None.** No `riverpod_annotation`, no `riverpod_generator`, no `@riverpod`. |
| Controllers | `Notifier<T>` + `NotifierProvider` / `NotifierProvider.family` |
| Not used anywhere | `StateNotifier`, `StateProvider`, `AsyncNotifier`, `StreamNotifier` |
| Provider count | **41** across **16** files in `lib/state/` |

### Riverpod 3 features actually used

| Feature | Where |
| --- | --- |
| **Unified `Ref` as a bare parameter** | `swrQuery<T>(Ref ref, …)`, `animePageStream(Ref ref, AnimePageArgs args)` |
| **`retry:` provider parameter** | 5 providers, all with `noProviderRetry` |
| **`ref.mounted`** | 6 usages in `tracked_entries_notifier.dart` |
| **`ref.listen` inside a provider** | `graphQLClientProvider` (cache wipe on auth change), `OptimisticEntries` (server entry await), `MyListsController` |
| **`.select(…)`** | Pervasive — narrow rebuilds in `app.dart`, `search_screen`, `media_detail_screen`, `account_button` |
| **`provider.future` / `provider.notifier`** | Awaiting server truth; dispatching controller methods |
| **`.autoDispose` / `.family`** | Detail, rails, people works, tracked entries |
| **`ProviderScope(overrides: …)`** | `main.dart` — the only place infrastructure is bound |

### Why no provider codegen

The project already runs `build_runner` for `freezed`/`json_serializable`. Adding a
second generator increases cold-build time and introduces another class of "forgot to
regenerate" failures, for little gain at this codebase size. Recorded as
[ADR-002](DECISIONS.md).

---

## Provider organisation

All 41 providers, grouped by file. **A** = autoDispose, **F** = family.

### `providers.dart` — infrastructure & auth (4)

| Provider | Type | Depends on / holds |
| --- | --- | --- |
| `sharedPreferencesProvider` | `Provider<SharedPreferences>` | **Throws `StateError` unless overridden in `main()`.** |
| `trackingRepositoryProvider` | `Provider<TrackingRepository>` | `LocalTrackingRepository(prefs)` |
| `authRepositoryProvider` | `Provider<AuthRepository>` | `createAuthRepository(prefs)`; `ref.onDispose` disposes the repo |
| `authStateProvider` | `StreamProvider<AuthUser?>` | Saved session → `restore()` → `userChanges.skip(1)`; background retry `[2,5,15,30,60] s` |

### `graphql_providers.dart` — GraphQL wiring (2)

| Provider | Type | Notes |
| --- | --- | --- |
| `gqlStorageProvider` | `Provider<GqlStorage>` | **Throws unless overridden in `main()`.** |
| `graphQLClientProvider` | `Provider<GraphQLClient>` | `readToken: () => auth.accessToken`; `ref.listen` on the signed-in user id → `cache.store.reset()` + `freshness.clear()` |

Also defines the free functions `toAppError(OperationException)` and
`Duration? noProviderRetry(int, Object) => null`.

### `gql_catalog.dart` (1)

| Provider | Type |
| --- | --- |
| `gqlCatalogProvider` | `Provider<GqlCatalog>` |

### `anime_providers.dart` — streaming SWR (3)

| Provider | Type | F |
| --- | --- | --- |
| `animePageProvider` | `StreamProvider.A<SwrResult<AnimePage>, AnimePageArgs>` | ✓ |
| `animeByIdProvider` | `StreamProvider.A<SwrResult<AnimeMedia>, int>` | ✓ |
| `trackedEntryProvider` | `StreamProvider.A<SwrResult<MediaListEntry?>, int>` | ✓ (operation key `MyEntry:$userId`) |

All three pass `retry: noProviderRetry`.

> **`animePageProvider` and `animeByIdProvider` are not watched by any widget today.**
> The home rails reach the same stream through `mediaRailProvider`, which calls the
> shared `animePageStream` function. They are available API surface, not dead code
> with side effects.

### `media_providers.dart` — read providers (13 + 1 enum)

| Provider | Type |
| --- | --- |
| `aniListClientProvider` | `Provider<AniListClient>` |
| `mediaRepositoryProvider` | `Provider<MediaRepository>` — `transport: ref.watch(gqlCatalogProvider).raw` |
| `mediaRailProvider` | `StreamProvider.F.A<MediaPage, (MediaRail, MediaType)>` — `noProviderRetry` |
| `airingTodayProvider` | `FutureProvider.A<List<AiringScheduleItem>>` |
| `mediaDetailProvider` | `StreamProvider.F.A<Media, int>` — `noProviderRetry` |
| `staffWorksProvider` / `characterWorksProvider` / `studioWorksProvider` | `FutureProvider.F.A<PersonWorks, (int, int)>` |
| `notificationsProvider` | `FutureProvider.A<List<UserNotification>>` |
| `viewerProfileSnapshotProvider` | `Provider<ViewerProfile?>` (prefs-backed, synchronous) |
| `viewerProfileProvider` | `FutureProvider.A<ViewerProfile?>` |
| `accountListProvider` | `FutureProvider.F.A<List<AccountListEntry>, ProfileSection>` |
| `activityProvider` | `FutureProvider.A<List<UserActivity>>` |

`enum MediaRail { trendingAnime, trendingManga, popularThisSeason, airingNow,
allTimePopular, upcoming, topRated, topCompleted, newChapters }`

### Controllers (14)

| File | Providers |
| --- | --- |
| `browse_controller.dart` | `browseControllerProvider` — `NotifierProvider.F<BrowseController, BrowseState, MediaType>`, **not** autoDispose |
| `calendar_controller.dart` | `calendarControllerProvider`, `calendarRemindersProvider` |
| `history_controller.dart` | `historyRepositoryProvider`, `historyControllerProvider` |
| `search_controller.dart` | `searchControllerProvider` |
| `my_lists_controller.dart` | `myListsControllerProvider`, `visibleEntriesProvider`, `myListsCountsProvider`, `continueWatchingProvider` |
| `settings_controller.dart` | `settingsControllerProvider`, `accentControllerProvider`, `sidebarCollapsedProvider`, `themeModeProvider` (derived) |
| `profile_banner_controller.dart` | `profileBannerControllerProvider` |
| `tracked_entries_notifier.dart` | `optimisticEntriesProvider`, `displayEntryProvider`, `entrySyncErrorProvider` |

### Pure code (no providers)

`load_state.dart` (`LoadStatus`, `LoadState<T>`), `swr.dart` (`SwrResult<T>`,
`swrQuery()`), `search_filters.dart` (`SearchFilters`, `SearchFilterKey`).

---

## Notifier and controller responsibilities

### `BrowseController` → `BrowseState`

```dart
class BrowseState {
  BrowseQuery query;  BrowsePreset? preset;  LoadStatus status;
  List<Media> items;  bool hasNextPage;  int? totalItems;  String? errorMessage;
  // getters: isFiltered, currentPage, pageCount, activePreset
}
```

| Concern | How |
| --- | --- |
| Stale-response guard | Monotonic `int _requestId`; every `load()` captures `++_requestId` and returns early if superseded |
| Build | Returns the initial state then `Future.microtask(load)` |
| Page fallback | An empty page with `page > 1` resets to page 1 and reloads (AniList's approximate `total` can overshoot) |
| Filters | `set<Status/Genre/Format/Season/Year/Source/Country/MinScore/Adult/Sort>` each reset `page: 1` and reload |
| Presets | `applyPreset` / `clearPreset` / `clearFilters`; editing any filter nulls `activePreset` |
| Retry | `retry() => load()` |

`copyWith` uses a `const Object _keepPreset` sentinel so a `null` preset can be
distinguished from "not passed".

### `CalendarController` → `CalendarState`

**Two independent status machines** — `status`/`items`/`errorMessage` (anime) and
`mangaStatus`/`mangaItems`/`mangaErrorMessage` (manga) — because the two loads run
concurrently and each must discard only *its own* superseded responses
(`_loadId`, `_mangaLoadId`).

| Concern | How |
| --- | --- |
| Build | Reads `ikigai.calendar.zone` from prefs, then `Future.microtask(load)` |
| Load | `load() = Future.wait([loadAnime(), loadManga()])` |
| Keep-previous-data | Old `items` stay visible while reloading, so the list never flashes empty |
| Manga tab | `setTab` lazily calls `loadManga()` on first open |
| Navigation | `nextWeek` / `previousWeek` / `thisWeek` **no-op while either machine is loading** (throttled) |
| Sorting | `CalendarSort`: air time / popularity / countdown |

Also holds `CalendarTab`, `CalendarZone` (device/utc/jst/sgt/ist with `wall()`,
`epochOfMidnight()`, `offsetLabel`), and `calendarWeekStart(zone, weekOffset)`.

`CalendarRemindersController` is a `Notifier<Set<int>>` persisting media ids under
`ikigai.calendar.reminders`, exposing `toggle(mediaId)`.

### `SearchController` → `SearchState`

The most complex controller: **five independent tab state machines** in one provider.

```dart
class SearchState {
  Map<SearchTab, String> queries;      // per-tab text
  SearchTab tab;
  MediaSort? animeSort, mangaSort;
  SearchFilters animeFilters, mangaFilters;
  TabPage<T> anime, manga, studios, staff, characters;
}
class TabPage<T> { LoadStatus status; List<T> items; int page; bool hasNextPage;
                   bool isAppending; int? total; String? errorMessage; }
```

| Concern | How |
| --- | --- |
| Constants | `_debounce = 400 ms`, `_mediaPerPage = 30`, `_peoplePerPage = 16` |
| Debounce | `Map<SearchTab, Timer> _timers`; **fires immediately when the normalised query is empty**; cancelled in `ref.onDispose` |
| Stale guard | `Map<SearchTab, int> _searchIds` monotonic ids |
| Criteria pinning | `Map<SearchTab, ({query, sort, filters})> _params` — further pages always use what the current result set was requested with, never newer text |
| Idempotence | `_restart(tab, force)` no-ops when query+sort+filters are unchanged and status is neither `error` nor `initial` |
| Shared loader | `_fetchInto<T>()` — sets `status` + `isAppending`, guards with `_nextId`, **de-duplicates appended items by id** (AniList rankings shift between pages) |
| Sort resolution | `resolveSort` → `searchMatch` when text present with no explicit sort, else `popularity`; falls back to `popularity` when text clears |
| Filter preview | `previewCount(tab, filters)` returns `page.total`, swallows errors → `null` |
| Normalisation | `normalizeSearchText` = trim + collapse inner whitespace |

### `MyListsController` → `MyListsState`

| Concern | How |
| --- | --- |
| State | `status`, `entries`, `filter`, `sort`, `errorMessage` + computed `visibleEntries`, `countFor`, `entryFor` |
| Build | Subscribes to `_repo.watchEntries().listen(…)`; `ref.onDispose` cancels; initial state is `loading` because the stream emits immediately |
| Mutations | `addTo`, `setStatus`, `setProgress`, `incrementProgress`, `setScore`, `remove`, `clearAll`, `refresh`, `setFilter`, `setSort`, `importFromAniList` |
| Mirroring | `_mirror(…)` — after each local edit, if `accessToken != null`, fire-and-forget `optimisticEntriesProvider.notifier.applyEdit(…)` |
| Failure policy | **"A sync failure never fails the local edit"** — it surfaces through `entrySyncErrorProvider` |
| Import | Throws `AppException(ErrorKind.unauthorized)` when signed out; returns the count added |
| Memoisation | `visibleEntriesProvider` uses 3× `select` so filter/sort changes rebuild only the list |

### `HistoryController` → `List<HistoryEntry>`

State is a plain list (newest first) seeded from `_repo.readAll()`. `record(Media)`,
`remove(entry)`, `clear()` each reassign `state` from the list the repository returns.

### Settings trio

| Controller | State | Prefs key | Notes |
| --- | --- | --- | --- |
| `SettingsController` | `ThemePreference {system, light, dark}` | `ikigai.theme` (legacy `sandwich.theme`) | Default `system` |
| `AccentController` | `AppAccent` | `ikigai.accent` (legacy `sandwich.accent`) | `AppAccent.fromName` migrates pre-rebrand names (`vermilion → lagoon`, …) |
| `SidebarController` | `bool` | `ikigai.sidebar.collapsed` | **Default `true`** (collapsed) |
| *(derived)* `themeModeProvider` | `ThemeMode` | — | `select`-driven |

Writes are **state first, then awaited `prefs.setX`**.

### `OptimisticEntries` → `Map<int, MediaListEntry>`

See [Debounced list synchronisation](#debounced-list-synchronisation).

---

## State lifecycle

### Bootstrap overrides

```dart
// lib/main.dart
runApp(ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    gqlStorageProvider.overrideWithValue(gql),
  ],
  child: const IkigaiApp(),
));
```

Both overridden providers **throw if read without an override** — that is deliberate,
so a mis-wired test or entry point fails loudly instead of silently using a null
store.

### Disposal

| Pattern | Where |
| --- | --- |
| `ref.onDispose(client.close)` | `aniListClientProvider` |
| `ref.onDispose(repo.dispose)` | `authRepositoryProvider` |
| `ref.onDispose(observable.close)` | `swrQuery()` |
| `ref.onDispose(timer.cancel)` | search debounce timers, optimistic sync timers |
| `ref.onDispose(sub.cancel)` | `MyListsController` stream subscription |

### Auth-driven cache invalidation

`graphQLClientProvider` listens to `authStateProvider.select((a) => a.value?.id)`:

```dart
// user id changed OR signed out
client.cache.store.reset();
storage.freshness.clear();
```

The wipe happens on **user change or sign-out**, not on guest→first-sign-in, because
guest data is public metadata that is safe to reuse for the first account. The
optimistic overlay is cleared separately: `OptimisticEntries` listens to the same id
and cancels timers + resets state — *"the overlay belongs to one account."*

### Background auth validation

`authStateProvider` is an `async*` stream: emit the saved session immediately →
`restore()` → follow `userChanges.skip(1)`. On a transient failure it retries with
`_authRetryDelays = [2, 5, 15, 30, 60] s` while keeping the cached profile on screen.
Only a definitive `unauthorized` signs out.

---

## Async state handling

Three distinct patterns coexist. They are **not** interchangeable — each fits a
different shape of state.

### Pattern 1 — `AsyncValue`

**Used by:** every `StreamProvider` / `FutureProvider` (home rails, media detail,
notifications, profile, account lists, activity, person works, auth state).

**Rendered with:** `async.when(…)`, or guards like
`auth.isLoading && !auth.hasValue`.

**Retry:** `ref.invalidate(provider)` wired to `onRetry:` callbacks.

### Pattern 2 — `LoadStatus` inside a custom state class

**Used by:** browse, calendar, search, my-lists — screens that need **extra fields**
(filters, pagination, sort, per-tab state) alongside loading status.

```dart
enum LoadStatus { initial, loading, success, error }
```

**Rendered with:** an explicit `switch (state.status)` calling controller methods
(`controller.retry()`, `runSearch()`, `loadMore()`).

**Errors are pre-digested** to `String errorMessage` via `AppException.userMessage`
before they reach the widget, with generic fallbacks such as
`"Could not load titles: $error"`.

> **`LoadState<T>` itself is barely used.** `StateView<T>` in
> `lib/ui/components/state_views.dart` is the only consumer of the full class — and
> **`StateView` is never instantiated anywhere**. Screens embed the `LoadStatus` enum
> directly in their own state classes and render with `SliverLoading` / `SliverError`
> / `SliverEmpty` from `sliver_headers.dart`.

### Pattern 3 — `SwrResult<T>`

**Used by:** `swrQuery()` consumers — rails, detail, tracked entry.

```dart
class SwrResult<T> {
  final T? data;          // may be null on the first emission
  final bool isRefreshing; // "subtle indicator, NOT a full-screen spinner"
  final bool fromCache;    // the 0 ms paint
  final Object? refreshError; // revalidation failed but old data exists
}
```

**Mechanism** — `swrQuery()` uses `client.watchQuery`, **not** `client.query`:

| Emission | Meaning |
| --- | --- |
| 1st | Cache hit (0 ms paint) |
| 2nd | Network result |
| later | Any subsequent cache change |

Fetch policy: `cacheFirst` while `FreshnessTracker` says the key is fresh, else
`cacheAndNetwork`. `errorPolicy: all`,
`cacheRereadPolicy: mergeOptimistic`, `fetchResults: true`.

Error behaviour:

| Situation | Result |
| --- | --- |
| `data == null` and still `isLoading` | `continue` — stay loading |
| Have a previous value | Yield `SwrResult(last, refreshError: error)` — keep showing data |
| No previous value | `throw` `toAppError(error)`, or `StateError('Empty GraphQL result')` |

> **Honest limitation:** `mediaRailProvider` maps `SwrResult` away and
> `mediaDetailProvider` maps it to a plain `Media`, so **`isRefreshing`, `fromCache`,
> and `refreshError` are currently never read by any widget.** The subtle refresh
> indicator and the "keep old data + offer retry" affordance they were designed for
> are not shown. Tracked as
> [KI-008](KNOWN_ISSUES.md).

### `noProviderRetry`

```dart
/// Riverpod 3 retries failed providers automatically (exponential backoff).
/// AniListHttpClient already retries 429/5xx, so provider-level retry would
/// multiply requests against a rate limit. Opt every GraphQL provider out.
Duration? noProviderRetry(int retryCount, Object error) => null;
```

| Opted out (5) | Not opted out (retry manually) |
| --- | --- |
| `animePageProvider`, `animeByIdProvider`, `trackedEntryProvider` | `airingTodayProvider`, `*WorksProvider` ×3, `notificationsProvider` |
| `mediaRailProvider`, `mediaDetailProvider` | `viewerProfileProvider`, `accountListProvider`, `activityProvider`, `authStateProvider`, all `NotifierProvider`s |

Real network retries live in `AniListHttpClient` (sliding window, 429 pause, jittered
backoff), **not** in Riverpod. The asymmetry is intentional: data reached through
`swrQuery`/`GqlCatalog` already has transport-level retries, while `FutureProvider`s
over `MediaRepository` rely on its in-flight dedupe plus manual `invalidate`.

---

## Data sharing between screens

| Provider | Shared across | Why it survives navigation |
| --- | --- | --- |
| `myListsControllerProvider` | Detail page, My Lists, Home "continue" rail | Not autoDispose — the single source of truth for entry state everywhere |
| `browseControllerProvider(MediaType)` | Browse ↔ Media detail | **Not autoDispose** — *"a lineup that is already applied and untouched is left alone, so coming back from a title page keeps the page the reader was on"* |
| `searchControllerProvider` | Header field, tabs, filter chips, results, load-more footer | Not autoDispose; the screen uses `select(_loadSignature)` (auto top-up) and `select(_viewKey)` (scroll to top on a new result set) |
| `historyControllerProvider` | Detail screen records; History screen renders/removes/clears | Not autoDispose |
| `entrySyncErrorProvider` | Any syncing screen → app shell snackbar | Listened **once**, centrally, in `app_shell.dart` |
| `calendarControllerProvider` | Calendar screen only | Not autoDispose; persists zone + week offset |

### Deep links → provider state

| Query param | Restored into |
| --- | --- |
| `?rail=` | `BrowsePreset.fromSlug()` → `browseControllerProvider` |
| `?tab=` | `CalendarScreen(initialTab)` |
| `?q=` | `searchControllerProvider.openWithQuery()` |

---

## State updates and invalidation

### Complete `ref.invalidate` inventory

| File | Call | Refreshes |
| --- | --- | --- |
| `state/tracked_entries_notifier.dart` | `ref.invalidate(trackedEntryProvider(mediaId))` | The user's entry after a delete or a new-entry save |
| `ui/screens/profile_screen.dart` | `ref.invalidate(viewerProfileProvider)` | Profile stats on pull/refresh |
| `ui/screens/profile_list_screen.dart` | `ref.invalidate(accountListProvider(section))` | One list section |
| `ui/screens/person_works_screen.dart` ×3 | `staffWorksProvider` / `characterWorksProvider` / `studioWorksProvider` | Person works on retry |
| `ui/screens/notifications_screen.dart` | `ref.invalidate(notificationsProvider)` | Manual notification refresh |
| `ui/screens/media_detail_screen.dart` | `ref.invalidate(mediaDetailProvider(mediaId))` | Detail after an edit |
| `ui/screens/home_screen.dart` ×2 | `ref.invalidate(mediaRailProvider((rail, type)))` | A single rail on retry |

### `freshness.forget` before `invalidate`

```dart
freshness.forget(FreshnessTracker.keyFor('MyEntry:$userId', {'id': mediaId}));
ref.invalidate(trackedEntryProvider(mediaId));
```

Without forgetting the stamp first, `invalidate` would be answered by the **now
outdated cache** for up to the TTL. This ordering matters and is easy to break.

### Update ordering rules

1. **Local writes:** update controller state first, then await the preference write.
2. **Remote writes:** set the overlay first (optimistic), then flush, then clear the
   overlay on confirmed success.
3. **Concurrency:** every fetch is guarded by a monotonic id; only the latest response
   is applied.

---

## Debouncing and throttling

| Where | Delay | Trigger | Notes |
| --- | --- | --- | --- |
| Search text | **400 ms** | `onQueryChanged(tab, value)` | Per-tab `Timer`s; **fires immediately when the query normalises to empty**; cancelled on submit/clear/`openWithQuery`; cancelled in `ref.onDispose` |
| Optimistic list sync | **500 ms** | Each progress/status/score edit | *"Ten quick taps cost one request, not ten."* |
| Filter count preview | **350 ms** | `previewCount` in the filter editor | Uses `Debouncer` (default **400 ms**) with a shorter delay |
| Calendar week navigation | *throttled* | `nextWeek`/`previousWeek`/`thisWeek` | No-op while either status machine is loading |
| Auth validation retry | **2 → 5 → 15 → 30 → 60 s** | Transient failure | Fixed ladder in `providers.dart` |

**`SearchFilters` itself has no debouncing.** It is a pure `@immutable` value type with
`==`/`hashCode` — *"the panel edits a draft copy and hands the whole thing back on
'Apply', so one apply is one network request."*

---

## Error and loading states

| Layer | Mechanism |
| --- | --- |
| Transport | `AniListHttpClient` / `AniListClient` throw `AppException` |
| Provider boundary | `toAppError(OperationException)` converts GraphQL failures |
| Controller | Catches `AppException` → `state.errorMessage = e.userMessage`; other `catch` → a formatted generic string |
| Widget | `switch (status)` / `async.when` → `SliverError` / `SliverEmpty` / retry button |
| Background sync | `entrySyncErrorProvider.report(e)` → app-shell listener → snackbar |

**Rule:** `AppException.message` is developer-facing and must never reach the UI;
`AppException.userMessage` is the only user-facing copy (except for
`ErrorKind.validation`, which passes `message` through by design).

### Known gap

`EntrySyncError` exposes `report(e)` but **has no clear/dismiss method** — state is
never reset to `null`, and the shell snackbar only fires on *change*, so a previously
reported error can go stale. Tracked as [KI-009](KNOWN_ISSUES.md).

---

## Debounced list synchronisation

`OptimisticEntries` (`tracked_entries_notifier.dart`) — the most subtle piece of
state in the app.

### The overlay model

```
displayEntryProvider(mediaId)  =  overlay[mediaId]   ??   server entry
```

The UI watches **`displayEntryProvider`**, never `optimisticEntriesProvider` directly.
Because the server state underneath is never mutated, **rollback is simply deleting
the overlay entry** — no snapshot bookkeeping.

### `incrementProgress(mediaId, totalUnits)` → `bool`

1. Throws `AppException(ErrorKind.unauthorized)` when signed out.
2. **Refuses when the server entry has not loaded** (`server.hasValue`) — *"never build
   on a guess"*, because a local progress of 1 must not overwrite a real 11.
3. Clamps to `totalUnits`; auto-completes when `next >= total`.
4. Writes the optimistic state, then `_schedule(mediaId)`.

### `applyEdit({mediaId, progress, status, score10})`

Guest → no-op. Signed in → **awaits server truth** via
`ref.listen(trackedEntryProvider(mediaId), …)` + `await .future` (keeping the
autoDispose provider alive), then overlays only the fields passed. Scores are
converted `score10 × 10` → AniList's `POINT_100`.

### `_flush(mediaId)`

| Step | Behaviour |
| --- | --- |
| In flight? | Re-schedule instead of starting a second call (**coalescing**) |
| Mutate | `saveMediaListEntryDoc` with **absolute** `progress`, `status.wire`, `scoreRaw` |
| Success | Remove the overlay **only if `state[mediaId] == pending`** — a newer edit made during the round-trip is preserved |
| Failure | Roll back the same way, report to `entrySyncErrorProvider` |
| Was new? | `_refetchServerEntry(mediaId)` |

### `removeEntry(mediaId)`

Cancels the queued timer → deletes the overlay → awaits the server entry **to get the
`MediaList` id** → `deleteMediaListEntryDoc` → `_refetchServerEntry`. Errors go to
`entrySyncErrorProvider`.

---

## Related documents

- Layering and data flow → [ARCHITECTURE.md](ARCHITECTURE.md)
- `FreshnessTracker` and cache keys → [DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md)
- Rate limits and retries → [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- Why these choices → [DECISIONS.md](DECISIONS.md)
- Known gaps in this area → [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
