# Database and storage

How Ikigai persists data, caches remote responses, and keeps everything consistent.

## Contents

- [Storage architecture](#storage-architecture)
- [Local storage: SharedPreferences](#local-storage-sharedpreferences)
- [GraphQL cache: Hive / IndexedDB](#graphql-cache-hive--indexeddb)
- [Cache management](#cache-management)
- [Cache expiration and invalidation](#cache-expiration-and-invalidation)
- [Data models and relationships](#data-models-and-relationships)
- [Persistence strategy](#persistence-strategy)
- [Offline data handling](#offline-data-handling)
- [Data synchronisation](#data-synchronisation)

---

## Storage architecture

Ikigai has **no server-side database**. All durable state lives in the browser, split
across two stores by *what kind of data it is*, plus several memory-only caches.

```
┌───────────────────────────────────────────────────────────────────────┐
│                              Browser                                   │
│                                                                        │
│  localStorage  ◀── shared_preferences ──▶  user data & settings        │
│    • OAuth token, profile snapshot                                     │
│    • tracking list, history                                            │
│    • theme/accent/sidebar, calendar zone+reminders, banner             │
│                                                                        │
│  IndexedDB     ◀── Hive (hive_ce) ─────▶  GraphQL response cache       │
│    • box ikigai_gql_v1      normalised entities                        │
│    • box ikigai_gql_meta_v1 freshness timestamps                       │
│                                                                        │
│  Memory only                                                             │
│    • MediaRepository LRU (120 entries, 5-min TTL)                       │
│    • MediaRepository in-flight Future dedupe map                        │
│    • FreshnessTracker fallback map                                      │
│    • Auth session fields (_user, _token)                                │
│    • AniListHttpClient sliding window + _blockedUntil                   │
└───────────────────────────────────────────────────────────────────────┘
```

### Why two stores

| Store | Holds | Why here |
| --- | --- | --- |
| `shared_preferences` → **localStorage** | Small, long-lived, user-owned JSON | Human-inspectable, survives reloads, tiny payloads, simple synchronous-enough API |
| Hive → **IndexedDB** | High-churn normalised GraphQL responses | Namespaced boxes, bulk `store.reset()`, not string-quota limited like localStorage |

**Why not an ORM (Drift / sqflite / Isar):** there are no relational queries. Every
read is either "a page of entities" or "my list". An ORM would add codegen, a schema
migration story, and on web a WASM/IndexedDB bridge — for no query benefit.

**Why tokens are not in Hive:** Hive holds an opened box fully in memory and is **not
multi-tab safe**. User credentials belong in localStorage, isolated from a cache that
gets wiped wholesale whenever the signed-in user changes.

### Blocked-storage fallbacks

Private mode, storage-partitioned contexts, and corporate policies can block either
store. **Both entry points degrade instead of crashing:**

```dart
// main.dart
final prefs = await _loadPreferences();
//  on failure → SharedPreferences.setMockInitialValues({})
//  Without this fallback main() would throw before runApp,
//  leaving a white screen.

// graphql_bootstrap.dart
final store = await openGqlStorage();
//  on failure → InMemoryStore() + FreshnessTracker(null) (persistent: false)
```

`openGqlStorage()` **never throws**. This is a deliberate boot-safety property.

---

## Local storage: SharedPreferences

### Complete key inventory

| Key | Owner | Value | Purpose |
| --- | --- | --- | --- |
| `ikigai.anilist.token` | `auth_repository.dart` | string | OAuth access token |
| `ikigai.anilist.user` | `auth_repository.dart` | JSON `{id, name, avatarUrl}` | Cached `AuthUser` for instant paint |
| `ikigai.anilist.tokenExpiresAt` | `auth_repository.dart` | epoch ms | **Informational only** — never used to sign out |
| `ikigai.anilist.loginStartedAt` | `auth_repository.dart` | epoch ms | Enforces the 30-minute redirect window |
| `ikigai.profile.<userId>` | `auth_repository.dart` | JSON `ViewerProfile` | Profile snapshot; cleared on sign-out |
| `ikigai.tracking.v1` | `tracking_repository.dart` | JSON array | **The user's list** (local source of truth) |
| `ikigai.tracking.v1.corrupt-backup` | `tracking_repository.dart` | raw string | Preserved unreadable store, written before any replacement |
| `ikigai.history.v1` | `history_repository.dart` | JSON array | Last 50 opened titles, newest first |
| `ikigai.theme` | `settings_controller.dart` | `system\|light\|dark` | Theme mode |
| `ikigai.accent` | `settings_controller.dart` | accent name | Accent seed |
| `ikigai.sidebar.collapsed` | `settings_controller.dart` | bool (default `true`) | Sidebar state |
| `ikigai.calendar.zone` | `calendar_controller.dart` | zone name | Timezone selection |
| `ikigai.calendar.reminders` | `calendar_controller.dart` | string list of media ids | Reminder **markers** (no delivery) |
| `ikigai.profile.banner` | `profile_banner_controller.dart` | JSON `ProfileBanner` | Banner preset choice |

**Legacy `sandwich.*` keys** (pre-Ikigai rebrand):

| Legacy key | Read | Written |
| --- | --- | --- |
| `sandwich.anilist.token`, `sandwich.anilist.user` | once, for migration | never (deleted on write/sign-out) |
| `sandwich.theme`, `sandwich.accent` | as fallback | never |
| `sandwich.tracking.v1` | once, for migration | never |

Migration is **read-once-then-abandon**: the legacy value is read only when the
`ikigai.*` key is absent, and subsequent writes use the new key. Accent names get the
same treatment via `AppAccent.fromName`, which maps `vermilion → lagoon`,
`ink → slate`, `stone/sage/…` to their closest modern equivalent.

---

## GraphQL cache: Hive / IndexedDB

### Boxes

```dart
const String kGqlBox  = 'ikigai_gql_v1';       // normalised response cache
const String kMetaBox = 'ikigai_gql_meta_v1';  // freshness timestamps
```

Opened by `openGqlStorage()` via `initHiveForFlutter()` (graphql_flutter's own Hive
initialisation; on web Hive uses **IndexedDB**).

**Versioning convention:** the `_v1` suffix is part of the name. **Bump it whenever
the `MediaCard` fragment or the freezed models change shape** — stale boxes are then
simply never read again.

> **Gap:** the doc comment on `openGqlStorage` suggests stale boxes should be deleted
> there, but **no box deletion is implemented** — only the two `open` calls. Old
> versioned boxes accumulate. Tracked as [KI-010](KNOWN_ISSUES.md).

### Fallback store

If opening either box fails, `FreshnessTracker(null)` and an `InMemoryStore()` are
used with `persistent: false` — the app works, but the cache is lost on reload.

### Constraints to respect

- An opened Hive box is **held fully in memory** → keep list pages ≤ 25 items and
  leave relations/recommendations out of list queries.
- **Not multi-tab safe** — concurrent tabs can race writes.
- **Never store tokens or the only copy of user data in Hive.**

### `FreshnessTracker`

Remembers *when* each query last succeeded on the network.

| Aspect | Detail |
| --- | --- |
| Key | `FreshnessTracker.keyFor(operation, variables)` → `'$operation:$fnv1a32Hex'` |
| Variables hashing | Sorted, JSON-encoded, UTF-8, **FNV-1a 32-bit** (`0x811c9dc5` / `0x01000193`) |
| Why FNV-1a 32-bit | Hive keys must be **ASCII and ≤ 255 characters** — a hash guarantees both |
| Value | `{'at': <epoch millis>}` in the meta box |
| In-memory mirror | `Map<String, int> _mem`, used when there is no persistent store |
| API | `isFresh(key, ttl)` · `touch(key)` (fire-and-forget write) · `forget(key)` (force next read to network) · `clear()` |

`isFresh` is `age >= 0 && age < ttl.inMilliseconds` — a clock skew into the future is
treated as **stale**, not fresh.

---

## Cache management

### In-memory repository cache

`MediaRepository` keeps a second, smaller cache above the GraphQL layer:

| Property | Value |
| --- | --- |
| Structure | `Map<String, _CacheEntry>` |
| Max entries | **120** (`_maxCacheEntries`) |
| Default TTL | **5 minutes** (`cacheTtl`, constructor-overridable) |
| Eviction | Expired entries first, then least-recently-used |
| Reset | `clearCache()` |

**In-flight dedupe:** a parallel `Map<String, Future>` means concurrent widgets
requesting the same key share **one** upstream request. This exists specifically to
protect the 90 req/min budget from navigation races.

**Negative caching:** `trending`, `browse`, `accountList`, `favourites`,
`activities`, and `notifications` cache **non-empty results only** — an empty page
that still claims `hasNextPage` is treated as a degraded response and left uncached.

### Cache key shapes

```
trending:$type:$page:$perPage
detail:$id
browse:$type:$page:$perPage|$sort|$search|…        (every active filter)
airing:$from:$to:$page:$perPage
viewerProfile:$userId
accountList:$userId:$type:$status|ALL
notifications:$userId:$perPage
staffAll:$id                                       (merged staff works, sliced per page)
Raw:$fnv(documentHash)                             (GqlCatalog generic path)
MyEntry:$userId                                    (signed-in user's entry)
```

---

## Cache expiration and invalidation

### TTL table

| Operation | TTL | Where |
| --- | --- | --- |
| `swrQuery` default | **5 min** | `swr.dart` |
| `BrowseMedia` / `GqlCatalog.browse` (no search) | **10 min** | `anime_providers.dart`, `gql_catalog.dart` |
| `BrowseMedia` / `GqlCatalog.browse` **with search** | **2 min** | same |
| `MediaById` / `MediaDetail` | **30 min** | `anime_providers.dart`, `media_providers.dart` |
| `MyEntry:$userId` (user's list entry) | **2 min** | `anime_providers.dart` |
| `GqlCatalog.raw` (repository transport, tokenless) | **10 min** | `gql_catalog.dart` |
| `GqlCatalog.airingScheduleAll` | **5 min** | `gql_catalog.dart` |
| `GqlCatalog.mangaReleases` | **30 min** | `gql_catalog.dart` |
| `MediaRepository` in-memory | **5 min** | `media_repository.dart` |

### Decision rule

```
read requested
   │
   ├─ FreshnessTracker.isFresh(key, ttl)?
   │      YES → FetchPolicy.cacheOnly      ← zero requests, 0 ms paint
   │      NO  → FetchPolicy.cacheAndNetwork ← stale-while-revalidate
   │
   └─ request carries a token?
          → always networkOnly              ← private data never from cache
```

- **`cacheAndNetwork` alone costs requests; it does not save them.** The freshness
  window is what keeps the app under AniList's rate limit.
- `touch(key)` runs **only on a clean network result** — `!hasException &&
  isUsable(data)`. A degraded empty page is displayed but **not** marked fresh, so the
  next read retries the network.
- On network failure with a usable cache, `GqlCatalog` falls back to a `cacheOnly`
  stale read rather than failing.

### Invalidation triggers

| Trigger | What is invalidated |
| --- | --- |
| Signed-in user id changes, or sign-out | `client.cache.store.reset()` **+** `freshness.clear()` (guest → first sign-in is *not* wiped — guest data is public) |
| After a delete or a new-entry save | `freshness.forget('MyEntry:$userId')` **then** `ref.invalidate(trackedEntryProvider(id))` — the order is mandatory, or the invalidate is answered by the outdated cache |
| Manual refresh buttons | `ref.invalidate` on the specific provider (profile, list section, notifications, detail, rail, person works) |
| Fragment / model shape change | **Bump `kGqlBox` / `kMetaBox` version suffix** — stale boxes are never opened again |
| Explicit | `MediaRepository.clearCache()`, `FreshnessTracker.clear()` |

---

## Data models and relationships

### Two model layers

| Layer | Location | Style | Used by |
| --- | --- | --- | --- |
| **Domain models** | `lib/data/models/` | **Plain Dart, hand-written `toJson`/`fromJson`** — no codegen | Everything outside `data/graphql` |
| **GraphQL models** | `lib/data/graphql/models/` | **freezed + json_serializable** | The GraphQL transport layer only |

The bridge is `AnimeMedia.toMedia()` — *"delete this once the UI consumes
`AnimeMedia` directly"* (that migration has not happened; widgets still take `Media`).

### Domain models

| File | Types | Notes |
| --- | --- | --- |
| `media.dart` (316 L) | `Media`, `MediaTag`, `NextAiringEpisode`, `MediaEdge`, `MediaPage` + enums `MediaType`, `MediaFormat`, `MediaStatus`, `MediaSeason`, `MediaSort`, `MediaSource` | Also `kCountries`, `kGenres` (18), `kScoreThresholds` |
| `media_entry.dart` (180 L) | `MediaEntry`, `ListStatus` | Wire: `CURRENT/PLANNING/COMPLETED/PAUSED/DROPPED`; **snake_case JSON keys**; `const Object _Unset` sentinel so `copyWith` can clear a field |
| `history_entry.dart` (57 L) | `HistoryEntry` | Denormalised title/cover so history paints offline; `tryFromJson` |
| `account.dart` (381 L) | `NotificationKind`, `UserNotification`, `GenreStat`, `ProfileSection`, `ScoreFormat`, `AccountListEntry`, `ActivityKind`, `UserActivity`, `ViewerProfile` | `ViewerProfile` has prefs-snapshot `toJson`/`fromJson` |
| `airing_schedule.dart` (48 L) | `AiringScheduleItem` | `airingAt` in epoch **seconds**; `platform` from the first streaming link |
| `people.dart` (167 L) | `SearchCharacter/Staff/Studio`, `*Page`, `PersonProfile`, `PersonWorks` | |
| `profile_banner.dart` (57 L) | `BannerPreset`, `ProfileBanner` | Website-only preference, unrelated to AniList |

### GraphQL models (freezed)

| File | Types |
| --- | --- |
| `anime_media.dart` | `MediaTitle`, `CoverImage`, `FuzzyDate` (`.iso`), `AiringInfo`, `StudioNode`, `StudioConnection`, **`AnimeMedia`**, `PageInfo`, `AnimePage` + converters `MediaTypeConverter`, `MediaFormatConverter`, `MediaStatusConverter`, `MediaSeasonConverter` |
| `media_list_entry.dart` | `@JsonEnum MediaListStatus` (`CURRENT/PLANNING/COMPLETED/DROPPED/PAUSED/REPEATING`), **`MediaListEntry`** (`id?`, `mediaId`, `status`, `progress`, `score`, `updatedAt`, `bool get isNew => id == null`) |

All four converters **fall back to `unknown` rather than throwing**, so an AniList
schema addition degrades instead of crashing the app.

### Relationships

```
AuthUser (ikigai.anilist.user)
   └── 1:1 ── ViewerProfile (ikigai.profile.<userId>)

Media (domain, remote)
   ├── 1:0..1 ── MediaEntry      local tracking   (keyed media_id, in ikigai.tracking.v1)
   ├── 1:0..1 ── HistoryEntry    recency          (keyed media_id, in ikigai.history.v1)
   ├── 1:0..1 ── MediaListEntry  AniList server   (overlay in memory, never persisted)
   ├── * ── MediaEdge            relations (derived from the detail payload)
   └── 1:0..1 ── AiringSchedule  next airing episode

AnimeMedia (freezed)  ──toMedia()──▶  Media (domain)   ← one-way bridge
MediaListEntry (freezed) ──_toRemote/_fromRemote──▶ MediaEntry (domain)
```

**Join key is always `mediaId`** — there is no local database with foreign keys, so
every relationship is a lookup by id.

**Codegen note:** `*.g.dart` and `*.freezed.dart` are **git-ignored**. Generated files
exist only after `dart run build_runner build --delete-conflicting-outputs`, which is
why a fresh clone does not compile.

---

## Persistence strategy

| Principle | Implementation |
| --- | --- |
| **State first, storage second** | Controllers assign `state`, then `await prefs.setX(…)`. The UI never waits on I/O. |
| **Fail loudly on write** | A `setString` returning `false` throws `AppException(ErrorKind.storage, 'Could not persist entries')` — a silently lost watchlist is worse than an error. |
| **Full-document writes** | Tracking is one JSON array write, not incremental — simple and atomic enough at this size. |
| **Tolerant reads** | Bad history records are dropped via `tryFromJson`; a `FormatException` yields `[]` rather than crashing. |
| **Never destroy unreadable data** | If the tracking store is unreadable, its raw contents are copied to `ikigai.tracking.v1.corrupt-backup` **before** any write replaces it. |
| **Cap and evict** | History capped at 50; repository cache capped at 120 with LRU eviction. |
| **Derived, not stored** | Counts, filtered lists, and visible entries are computed in providers (`myListsCountsProvider`, `visibleEntriesProvider`) rather than persisted. |

---

## Offline data handling

| Works offline / before network | Does not work offline |
| --- | --- |
| Tracking: add, edit, remove, status, progress, score (local store) | Any read past its TTL |
| History: read, record, remove, clear | Signed-in token validation |
| Settings: theme, accent, sidebar, banner preset | Profile statistics (snapshot paints, then fails to revalidate) |
| Calendar zone + reminder markers | Notifications, activity, account lists |
| Cached GraphQL responses **inside their TTL** (0 ms paint) | Search / browse with no warm cache |
| Profile snapshot (`ViewerProfile`) paints immediately | Sign-in (requires the OAuth round trip) |

### Honest limitations

- **No offline write queue.** Local writes go straight to localStorage. There is no
  outbox, no retry-on-reconnect, no background sync worker.
- **A tap in the last 500 ms before the tab closes is not flushed** — the debounced
  sync timer is cancelled on disposal without a final drain.
- **No conflict resolution** because there is no queue to conflict.
- **Service worker / PWA offline shell: not implemented.** `manifest.json` makes the
  app installable, but there is no service worker, so a cold offline load fails.
- Guest mode is unaffected by any of this for cached content — it is the reason the
  app remains usable without an account.

---

## Data synchronisation

Signed-in list changes mirror to AniList. The rules:

| Rule | Why |
| --- | --- |
| **The local list is the UI source of truth** | The UI never waits on AniList to reflect an edit |
| **Absolute values, never `+1`** | A retried mutation is idempotent — a duplicate tap cannot become `+2` |
| **Debounced 500 ms** | Ten quick taps cost one request |
| **Coalesce while in flight** | A second flush is scheduled, not started |
| **Await the server entry before the first edit** | A local progress of 1 must never overwrite a real 11 |
| **Rollback = delete the overlay** | Server state was never mutated, so no snapshot is needed |
| **Clear the overlay only if it still equals what was sent** | Preserves edits made during the round trip |
| **Sync failure never fails the local edit** | Reported via `entrySyncErrorProvider` → snackbar instead |
| **Import is add-only** | Never overwrites or deletes local entries |
| **No send on a guess** | If a title's AniList entry cannot be read, the edit is not synced |

Known limits are documented in
[GRAPHQL_MIGRATION.md](GRAPHQL_MIGRATION.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

---

## Related documents

- Endpoints and rate limits → [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- Provider wiring → [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)
- Why two stores → [DECISIONS.md](DECISIONS.md)
- Known storage gaps → [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
