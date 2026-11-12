# GraphQL migration

An implementation record: what the data layer looked like before, what replaced it,
what shipped, and what did not.

> **Status: shipped.** All network traffic now goes through the GraphQL client.
> This document was rewritten from the original pre-implementation *blueprint* so that
> completed work and remaining work are clearly separated.

## Contents

- [Migration status at a glance](#migration-status-at-a-glance)
- [Previous implementation](#previous-implementation)
- [Migration objectives](#migration-objectives)
- [New GraphQL architecture](#new-graphql-architecture)
- [Query and mutation implementation](#query-and-mutation-implementation)
- [Repository and client changes](#repository-and-client-changes)
- [Caching implementation](#caching-implementation)
- [Authentication integration](#authentication-integration)
- [Migration challenges](#migration-challenges)
- [Flutter Web caveats](#flutter-web-caveats)
- [Known limitations](#known-limitations)
- [Remaining tasks](#remaining-tasks)
- [Verify first](#verify-first)

---

## Migration status at a glance

| Area | Status | Detail |
| --- | --- | --- |
| Home rails | ✅ Shipped | `animePageStream` using the `MediaCard` fragment |
| Browse, Search, Calendar, "airing today" | ✅ Shipped | `GqlCatalog` (`lib/state/gql_catalog.dart`) |
| Media detail | ✅ Shipped | `mediaDetailProvider` — `StreamProvider`, SWR, 30-minute TTL |
| Staff / character / studio pages, notifications, viewer profile, activity, AniList list, favourites | ✅ Shipped | `MediaRepository` through `MediaRepository.transport = GqlCatalog.raw` |
| Rate limiting (80 req/min sliding window) | ✅ Shipped | `AniListHttpClient` |
| 429 pause + jittered retries | ✅ Shipped | `AniListHttpClient` / `AniListClient` |
| Persisted response cache (IndexedDB) | ✅ Shipped | `GraphQLCache(HiveStore)`, boxes `ikigai_gql_v1` / `ikigai_gql_meta_v1` |
| Freshness-gated fetch policy | ✅ Shipped | `FreshnessTracker` |
| Signed-in list mirroring | ✅ Shipped | `OptimisticEntries` — debounced, absolute values |
| Import from AniList | ✅ Shipped | Add-only |
| Sync failure feedback | ✅ Shipped | Snackbar in `AppShell` + "syncing to AniList…" label |
| "My Lists" as a full `MediaListCollection` SWR provider | ❌ **Not done** | Reachable only through `MediaRepository.accountList` |
| Hybrid tracking (guest = local, user = AniList) behind `TrackingRepository` | ❌ **Not done** | Sync happens outside the repository, in the notifier |
| Flush a tap in the last 500 ms before tab close | ❌ **Not done** | Timer cancelled without a final drain |
| Stale Hive box deletion | ❌ **Not done** | Doc comment says to; code does not |

---

## Previous implementation

Before the migration, three separate mechanisms handled data:

```
UI screens
   │
   ▼
MediaRepository
   ├─ hand-written AniListClient      ← retry, backoff, Retry-After, partial-data
   ├─ in-memory Map cache             ← 5-minute TTL, LRU capped at 120
   └─ in-flight Future dedupe map     ← one upstream request per key
   │
   ▼
https://graphql.anilist.co  (raw JSON over http)

Tracking:  LocalTrackingRepository  →  localStorage   (local only, no sync)
```

**What worked:** the client's retry/backoff/`Retry-After` handling, partial-data
handling, and the in-memory cache with in-flight dedupe.

**What did not:** nothing survived a reload; the cache was lost every navigation
session; every cold read hit AniList; and **there was no AniList list synchronisation
at all** — tracking was purely local.

---

## Migration objectives

1. **Unify on `graphql_flutter`** — normalised caching, `watchQuery` streams, and
   fetch policies instead of hand-rolled JSON plumbing.
2. **Persist the cache** across reloads so cold starts paint instantly.
3. **Protect the rate limit** deterministically, with a freshness gate rather than
   blind `cacheAndNetwork`.
4. **Add the first real AniList list sync** — mutations, optimistic UI, rollback.
5. **Replace the fetch/cache/model layers without rewriting the widgets** — so the
   UI could migrate screen by screen.

---

## New GraphQL architecture

```
UI (existing screens)
  │  ref.watch(animePageProvider(args)) / displayEntryProvider(id)
  ▼
Riverpod: anime_providers.dart, tracked_entries_notifier.dart
  │  swrQuery(): watchQuery stream — cache emission, then network emission
  ▼
GraphQLClient (graphql_bootstrap.dart)
  ├─ GraphQLCache(HiveStore)      ← IndexedDB on web, versioned box
  ├─ BearerAuthLink               ← header present only while a token exists
  └─ HttpLink(AniListHttpClient)  ← rate gate, 429 pause, retries, AppException
  ▼
https://graphql.anilist.co
```

| Piece | File | Role |
| --- | --- | --- |
| `buildGraphQLClient()` | `graphql_bootstrap.dart` | Link chain, cache, default policies |
| `openGqlStorage()` | `graphql_bootstrap.dart` | Opens both Hive boxes; **never throws** |
| `FreshnessTracker` | `graphql_bootstrap.dart` | Per-query last-success timestamps |
| `AniListHttpClient` | `anilist_http_client.dart` | Rate gate, 429 pause, retries, partial-data rescue |
| `BearerAuthLink` | `bearer_auth_link.dart` | Per-request token injection |
| Parsed documents | `anilist_documents.dart` | `DocumentNode`s + the shared `MediaCard` fragment |
| `GqlCatalog` | `lib/state/gql_catalog.dart` | One-shot SWR reads + the `raw` transport |

Two HTTP paths remain by design: this chain is the **production path**, while the
hand-written `AniListClient` still serves the auth `Viewer` validation and acts as
`MediaRepository`'s fallback when no transport is injected. Both map failures into the
same `AppException` taxonomy, so the UI cannot tell them apart.

---

## Query and mutation implementation

### Parsed documents (`anilist_documents.dart`)

| Document | Kind | Notes |
| --- | --- | --- |
| `browseMediaDoc` | query | Browse/search/rails; `isAdult: Boolean = false` |
| `mediaByIdDoc` | query | Detail; uses `MediaCard` |
| `myEntryForMediaDoc` | query | Signed-in user's entry; **needs token** |
| `saveMediaListEntryDoc` | **mutation** | Upsert on `mediaId`; sends **absolute** progress |
| `deleteMediaListEntryDoc` | **mutation** | Needs the **MediaList** id, not the media id |

**Only two mutations exist.**

### Raw documents (`anilist_queries.dart`)

`trendingQuery`, `browseQuery`, `kMediaDetailQuery`, `kViewerQuery`,
`kAiringScheduleQuery`, `kMangaReleasesQuery`, the character/staff/studio search and
works queries, `kNotificationsQuery`, `kViewerProfileQuery`,
`kMediaListCollectionQuery`, `kFavouriteAnimeQuery`, `kViewerActivityQuery` — all
routed through the same client via `MediaRepository.transport`.

### The `MediaCard` fragment invariant

```graphql
fragment MediaCard on Media { id idMal type format status … studios(isMain: true) }
```

**Never put a user-specific field (`mediaListEntry`, `isFavourite`) in it.**
graphql_flutter normalises responses onto `Media:<id>` records that are **not**
account-scoped — a user field in the shared fragment would leak across accounts signed
into the same browser. User entries use the separate `myEntryForMediaDoc` query
instead, and the cache is wiped when the signed-in user changes.

### Migration mechanics for widgets

`AnimeMedia.toMedia()` returns the existing `Media`, so **widgets kept their current
model while providers changed underneath**. That adapter was the reason the migration
could proceed screen by screen rather than as a flag day.

---

## Repository and client changes

| Before | After |
| --- | --- |
| `MediaRepository` called `AniListClient.query` directly | `MediaRepository.transport` (injected as `GqlCatalog.raw`) sends every request through the rate-gated GraphQL client; `AniListClient` remains only as fallback when no transport is set |
| In-memory 5-min LRU + in-flight dedupe | **Kept** — sits above the GraphQL cache as a third tier |
| `LocalTrackingRepository` the only list path | **Kept as the UI source of truth**; signed-in edits are mirrored by `OptimisticEntries` |
| Freezed models unused by the app | `AnimeMedia`, `MediaListEntry` now carry the GraphQL payloads, bridged to `Media`/`MediaEntry` |

**`MediaRepository` was deliberately kept as a thin layer (mapping + in-memory cache),
not deleted.** Removing it would have meant moving business rules like page caps,
negative caching, and staff-works merging into the state layer.

Requests carrying a **token always go to the network** — private data is never
answered from a cache entry. Public requests follow a 10-minute freshness window
inside `GqlCatalog.raw`.

---

## Caching implementation

### Three tiers

| Tier | Store | TTL / size | Survives reload |
| --- | --- | --- | --- |
| `MediaRepository._cache` | memory | 5 min, 120 entries, LRU | No |
| `GraphQLCache` | Hive → IndexedDB | no TTL of its own — governed by freshness | **Yes** |
| `FreshnessTracker` | Hive box `ikigai_gql_meta_v1` | per-operation TTL | **Yes** |

### Freshness gating

```
FreshnessTracker.isFresh(key, ttl)?
   YES → FetchPolicy.cacheOnly      ← 0 ms paint, 0 requests
   NO  → FetchPolicy.cacheAndNetwork ← cache emission, then network
```

`touch(key)` runs **only on a clean network result** (`!hasException && isUsable`).
A degraded or empty page is shown but **not** marked fresh, so the next read retries
the network.

**This is the whole point of the design:** `cacheAndNetwork` alone *costs* requests —
every visit would hit AniList. The freshness window is what keeps the app under the
rate limit. You cannot "bypass" AniList's limit; this keeps you under it.

### TTLs in use

| Operation | TTL |
| --- | --- |
| `swrQuery` default | 5 min |
| Browse (no search) | 10 min |
| Browse **with search** | 2 min |
| Media detail (`MediaById` / `MediaDetail`) | 30 min |
| `MyEntry:$userId` | 2 min |
| `GqlCatalog.raw` (tokenless) | 10 min |
| Airing schedule | 5 min |
| Manga releases | 30 min |

### Key format

```
FreshnessTracker.keyFor(operation, variables)
   = '$operation:${fnv1a32Hex(sortedJson(variables))}'
```

Variables are sorted, JSON-encoded, UTF-8, and hashed with **FNV-1a 32-bit** because
Hive keys must be **ASCII and ≤ 255 characters** — a hash guarantees both regardless
of how long a query string gets.

### Invalidation

- **User changes / signs out** → `client.cache.store.reset()` + `freshness.clear()`.
  *Not* applied on guest → first sign-in (guest data is public metadata).
- **After a delete or new entry** → `freshness.forget('MyEntry:$userId')` **then**
  `ref.invalidate(trackedEntryProvider(id))`. The order is mandatory: invalidate alone
  would be answered by the now-outdated cache for up to the TTL.
- **Fragment/model shape change** → bump `kGqlBox` / `kMetaBox` (`…_v2`). Stale boxes
  are simply never opened again.

---

## Authentication integration

- `BearerAuthLink` reads the token from a **closure per request**, so sign-in/out
  never rebuilds the client or the cache.
- Null/empty token ⇒ **no `Authorization` header at all**.
- `graphql_providers.dart` listens to `authStateProvider` for the signed-in **user id**
  and wipes cache + freshness on change or sign-out.
- The OAuth flow itself is unchanged from before the migration — implicit grant,
  fragment-only capture, 30-minute login window. See
  [API_DOCUMENTATION.md](API_DOCUMENTATION.md#authentication-oauth-20).

---

## Migration challenges

### 1. `watchQuery`, not `client.query`

With `cacheAndNetwork`, `client.query` resolves **with the network result**, so the
instant cache paint is lost. `swrQuery()` therefore uses `client.watchQuery` and is a
**stream**: cache emission first, network emission second, then later cache changes.

### 2. `cacheAndNetwork` alone costs requests; it does not save them

Every visit would hit AniList. `FreshnessTracker` records the last successful fetch
per query and uses `cacheFirst` inside the TTL, `cacheAndNetwork` after it. **That is
what actually protects the rate limit.**

### 3. Rate limiting had to live below the library

It sits in `AniListHttpClient` as an `http.BaseClient`: an 80 req/min sliding window
**per tab**, one 429 pausing **all** queued requests, and failures thrown as the
existing `AppException` so current error UI keeps working untouched.

### 4. Keeping user data out of the shared fragment

Described above — the cross-account cache leak was the single most dangerous
correctness trap in the design.

### 5. Optimistic updates use an overlay, not mutated server state

Rollback is **deleting the overlay entry** — no snapshot bookkeeping, because the
server state underneath was never mutated. Taps are debounced into one
**absolute-progress** mutation, and taps are **refused until the server entry has
loaded** (otherwise local progress 1 would overwrite a real 11).

### 6. Riverpod 3 retries failed providers automatically

Every GraphQL provider passes **`retry: noProviderRetry`**, because
`AniListHttpClient` already retries 429/5xx — provider-level retry would multiply
requests against a rate limit.

### 7. Two model idioms had to coexist

freezed for the GraphQL layer, hand-written JSON for the domain models, joined by
`AnimeMedia.toMedia()`. Doing it the other way (freezing everything) would have meant
rewriting legacy wire formats and sentinel-based `copyWith` semantics for no gain.

---

## Flutter Web caveats

**The stutter part.**

- **Dart isolates do not exist on web**, so `compute()` cannot move JSON parsing off
  the main thread. The real levers are: small pages (`perPage <= 25`), no
  relations/recommendations in list queries, `select()` so only the changed widget
  rebuilds, and `ListView.builder`/slivers.
- graphql_flutter **normalises every response into `Type:id` records on the main
  thread**. Fast for cards; noticeable for huge payloads.
- **Hive loads an opened box into memory and is not multi-tab safe.** Fine for a
  cache; never store tokens or the only copy of user data in it. If IndexedDB is
  blocked, `openGqlStorage()` falls back to an in-memory cache.
- The rate-limit window is **per browser tab** — two open tabs share AniList's real
  limit.
- **CORS hides `Retry-After`**, so 429 waits fall back to `5 s × (attempt+1)`.

---

## Known limitations

| Limitation | Impact |
| --- | --- |
| **Import never overwrites or removes local entries** | A locally deleted title comes back on the next import. Deliberate — it prevents data loss. |
| **Import does not delete titles that exist only locally** | No destructive sync. |
| **A local edit made while a title's AniList entry cannot be read is not synced** | Nothing is sent on a guess; the local edit stands. |
| **A tap in the last 500 ms before the tab closes is not flushed** | The debounce timer is cancelled without a final drain. |
| **`MediaRepository` is kept as a thin layer, not deleted** | Two cache tiers remain; slight extra complexity. |
| **`AniListClient` is still used as fallback when no transport is set** | Two HTTP paths to maintain. |
| **No OAuth refresh token** | Sessions end only when AniList rejects the token. |
| **Per-tab rate limiting** | Extra tabs can jointly exceed the real limit. |
| **Hive is not multi-tab safe** | Concurrent tabs can race cache writes. |

---

## Remaining tasks

Not part of the shipped migration:

1. **"My Lists" as a full `MediaListCollection` SWR provider.** Reachable today only
   via `MediaRepository.accountList`; it can be large, so it would need paging or
   status filtering.
2. **Hybrid tracking behind `TrackingRepository`.** Guests use
   `LocalTrackingRepository`; signed-in users currently sync *outside* the repository,
   in `OptimisticEntries`. A second `TrackingRepository` implementation that talks to
   AniList directly would unify the path.
3. **Flush pending taps on tab close** (`visibilitychange` / `pagehide` drain).
4. **Delete stale Hive boxes in `openGqlStorage()`** — the doc comment says to; the
   code only opens the two current boxes.
5. **Consume `SwrResult.isRefreshing` / `fromCache` / `refreshError` in the UI** — the
   fields are populated but no widget reads them yet, so the subtle refresh indicator
   and the "old data + retry" affordance never appear.
6. **Clear `entrySyncErrorProvider`** — it has `report()` but no dismiss, so a stale
   error can persist.

---

## Verify first

API assumptions written **without compiling against the resolved package versions**.
If a dependency upgrade breaks the build, check these first:

- [ ] `GraphQLClient(queryRequestTimeout: …)` exists in the installed `graphql` version —
      the call site carries an in-code comment *"Verify this parameter name against your
      installed graphql version."*
- [ ] `WatchQueryOptions(parserFn: …)` and `QueryResult.parsedData`
- [ ] `HttpLinkHeaders` / `updateContextEntry` are re-exported by `graphql_flutter`
- [ ] `LinkException.originalException` is how `toAppError` unwraps link failures
- [ ] `Hive.openBox<int>` works alongside graphql's own box after `initHiveForFlutter`
- [ ] Resolve one Hive version: `flutter pub deps | grep -i hive`
      (`hive_ce 2.22.0` today)

---

## Related documents

- Endpoints, rate limits, error mapping → [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- Cache keys, TTLs, storage → [DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md)
- Providers and SWR → [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)
- Tracking feature behaviour → [FEATURES.md](FEATURES.md)
- Decision records → [DECISIONS.md](DECISIONS.md)
