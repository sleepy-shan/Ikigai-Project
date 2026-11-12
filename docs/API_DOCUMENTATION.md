# API documentation

How Ikigai talks to AniList.

## Contents

- [Overview](#overview)
- [Endpoint and transport](#endpoint-and-transport)
- [Authentication (OAuth 2.0)](#authentication-oauth-20)
- [Queries and mutations](#queries-and-mutations)
- [Request and response examples](#request-and-response-examples)
- [Rate limits](#rate-limits)
- [Retry, backoff, and 429 handling](#retry-backoff-and-429-handling)
- [Error handling](#error-handling)
- [Client implementation](#client-implementation)
- [What is not implemented](#what-is-not-implemented)

---

## Overview

AniList exposes a **single GraphQL endpoint**. There is no REST API, no webhooks, and
no server-side component of our own — the browser calls AniList directly.

| Property | Value |
| --- | --- |
| Endpoint | `https://graphql.anilist.co` |
| Method | `POST`, `Content-Type: application/json` |
| Auth | OAuth 2.0 **implicit grant** (`Authorization: Bearer <token>`) — optional |
| Docs | <https://docs.anilist.co/> |
| GraphiQL | <https://docs.anilist.co/guide/getting-started> |
| Nominal rate limit | ~90 requests/minute, degrading to ~30/min under abuse |
| Adult content | Public list queries hard-code `isAdult: false` |

Everything the app fetches goes through **one of two HTTP clients** that map failures
into the same `AppException` taxonomy, so the UI cannot tell them apart.

| Client | File | Used by | Rate gated? |
| --- | --- | --- | --- |
| `AniListHttpClient` (via `graphql_flutter`) | `lib/data/graphql/anilist_http_client.dart` | **Production path** — everything reachable from `gqlCatalogProvider` and `swrQuery()` | **Yes** — 80 req/min sliding window |
| `AniListClient` (hand-written) | `lib/data/anilist/anilist_client.dart` | Auth path (`Viewer` validation) and `MediaRepository`'s fallback when no `transport` is injected | No |

---

## Endpoint and transport

### The link chain

```
GraphQLClient  (lib/data/graphql/graphql_bootstrap.dart)
  cache: GraphQLCache(store: HiveStore → IndexedDB)
  queryRequestTimeout: 25 s          ← carries an in-code "verify" note; see below
  Link:  BearerAuthLink  →  HttpLink(endpoint, httpClient: AniListHttpClient)
```

```dart
Link.from([
  BearerAuthLink(() => auth.accessToken),
  HttpLink(
    AppConfig.aniListEndpoint,
    httpClient: AniListHttpClient(),
    defaultHeaders: {'Accept': 'application/json'},
  ),
])
```

### `BearerAuthLink` (`bearer_auth_link.dart`)

- Takes a **closure** (`String? Function()`), so the token is read **per request**.
  Signing in or out never rebuilds the client or invalidates the cache.
- If the token is `null` or empty, the request is sent with **no `Authorization`
  header at all** — explicitly, rather than relying on the library's null handling.
- Otherwise sets `Authorization: Bearer <token>` via
  `request.updateContextEntry<HttpLinkHeaders>()`.
- The token is never logged.

### Default policies

| Policy | Value |
| --- | --- |
| `watchQuery` fetch policy | `FetchPolicy.cacheAndNetwork` |
| `query` fetch policy | `FetchPolicy.cacheFirst` |
| Error policy (both) | `ErrorPolicy.all` — partial data is still returned alongside errors |
| Cache reread policy | `CacheRereadPolicy.mergeOptimistic` |

> **Unverified assumption.** `GraphQLClient(queryRequestTimeout: …)` carries an
> in-code comment: *"Verify this parameter name against your installed graphql
> version."* It was written without compiling against the resolved package. If a
> graphql upgrade breaks this, the failure will be at construction time.

---

## Authentication (OAuth 2.0)

### Flow type

**Implicit grant** (`response_type=token`). No scopes parameter, **no refresh token**,
no client secret, no backend.

```
┌──────────┐   1. tap "Continue with AniList"   ┌──────────────┐
│  Ikigai  │ ─────────────────────────────────▶ │   AniList    │
│  (web)   │   2. authorize?client_id=…&         │  authorize   │
│          │      response_type=token (same tab) │              │
│          │ ◀─────────────────────────────────  │              │
│          │   3. redirect → /#access_token=…    │              │
│          │   4. capture fragment, store token, │              │
│          │      scrub URL, validate Viewer     │              │
└──────────┘                                    └──────────────┘
```

### Endpoints

| Purpose | URL |
| --- | --- |
| Authorize | `https://anilist.co/api/v2/oauth/authorize?client_id=<id>&response_type=token` |
| Redirect target | Whatever Redirect URL is registered on the AniList developer app |
| Token validation | The same GraphQL endpoint, `Viewer` query |

### Client id

```dart
// lib/core/config/app_config.dart
static const String aniListClientId = String.fromEnvironment(
  'ANILIST_CLIENT_ID',
  defaultValue: '53659',   // public fallback
);
static bool get hasAnilistClient => anilistClientId.isNotEmpty;
```

`String.fromEnvironment` returns `''` when the define is present but empty, so the
getter treats empty as "not configured". Without a client id the sign-in dialog shows
an explanation instead of failing silently.

### Redirect capture and safety rules

`main.dart` inspects `Uri.base` **before** `runApp`:

1. Only the **fragment** (`#access_token=…`) is read. A `?access_token=` **query
   parameter is deliberately ignored** — an attacker who can make a victim open a
   crafted link would otherwise be able to sign the victim into the attacker's
   account.
2. `AniListAuthRepository.markLoginStarted(prefs)` runs **before** redirecting, and
   `acceptRedirect` refuses any token arriving more than **30 minutes**
   (`loginWindow`) later. The marker is consumed either way, so one sign-in yields at
   most one accepted redirect.
3. `clearUrlFragment()` (a web-only `history.replaceState`, no-op stub elsewhere)
   scrubs the token so it never lingers in the address bar or history.
4. If the incoming token differs from a stored one, the cached user record is dropped
   first so a stale avatar/name cannot sit beside a new token.

### Token storage (`SharedPreferences`)

| Key | Value |
| --- | --- |
| `ikigai.anilist.token` | The access token |
| `ikigai.anilist.user` | `AuthUser` JSON `{id, name, avatarUrl}` |
| `ikigai.anilist.tokenExpiresAt` | Epoch ms from `expires_in` — **informational only**, never used to sign out |
| `ikigai.anilist.loginStartedAt` | Epoch ms of the last sign-in tap (30-minute window) |
| `ikigai.profile.<userId>` | `ViewerProfile` snapshot for instant paint |
| `sandwich.anilist.token` / `.user` | Legacy pre-rebrand keys, read once for migration |

### Validation and session lifetime

- `_fetchViewer()` runs a fixed `Viewer { id name avatar { large } }` query.
- **AniList reports an invalid token as HTTP 400**, so `ErrorKind.badRequest` is
  remapped to `ErrorKind.unauthorized` (*"AniList rejected the saved token"*).
- `restore()` on `unauthorized` → `signOut()`.
- `restore()` on transient failures (`network`/`rateLimit`/`server`) → **keeps** the
  cached profile and sets `_needsValidation = true`. Background retries use a fixed
  ladder of **2 s → 5 s → 15 s → 30 s → 60 s** (defined in `lib/state/providers.dart`).
- Because there is no refresh token, **a session ends only when AniList rejects it.**

---

## Queries and mutations

Two documents live in **`lib/data/graphql/anilist_documents.dart`** as parsed
`DocumentNode`s for `graphql_flutter`. Two more live in
**`lib/data/anilist/anilist_queries.dart`** as raw strings for the hand-written client
and `GqlCatalog`.

### The shared `MediaCard` fragment

```graphql
fragment MediaCard on Media {
  id idMal type format status season seasonYear episodes chapters volumes
  duration averageScore meanScore popularity favourites source countryOfOrigin
  startDate endDate siteUrl title coverImage bannerImage description genres
  nextAiringEpisode studios(isMain: true) { id name siteUrl }
}
```

> **Invariant:** never add a user-specific field (`mediaListEntry`, `isFavourite`) to
> this fragment. The response is normalised onto the shared `Media:<id>` cache record,
> which is **not** scoped by account — a user field here would leak across accounts
> signed into the same browser.

### Parsed documents — `anilist_documents.dart`

| Document | Operation | Purpose | Arguments |
| --- | --- | --- | --- |
| `browseMediaDoc` | `BrowseMedia` | Browse / trending / search rails | `$page $perPage $type $sort [MediaSort] $search $status $season $seasonYear $isAdult = false` |
| `mediaByIdDoc` | `MediaById` | Detail page (uses `MediaCard`) | `$id: Int` |
| `myEntryForMediaDoc` | `MyEntryForMedia` | Signed-in user's entry for one title — **needs token** | `$id: Int` |
| `saveMediaListEntryDoc` | `SaveMediaListEntry` | **Mutation** — create *or* update (upsert on `mediaId`) | `$mediaId $status $progress $scoreRaw` |
| `deleteMediaListEntryDoc` | `DeleteMediaListEntry` | **Mutation** — remove one entry | `$id` (the **MediaList** id, not the media id) |

**Only two mutations exist in the entire data layer.**

### Raw documents — `anilist_queries.dart`

| Symbol | Purpose | Key arguments |
| --- | --- | --- |
| `trendingQuery({detail})` | Home trending/popular rails | `$page $perPage $type`, `sort: TRENDING_DESC`, `isAdult: false` |
| `browseQuery({detail})` | Browse with full filter set | `$page $perPage $type $sort $search $genre $status $format $season $seasonYear $source $countryOfOrigin $minScore $genre_in $startDate_greater $startDate_lesser $isAdult = false` |
| `kMediaDetailQuery` | Detail by id (adds tags, relations, recommendations) | `$id: Int` |
| `kViewerQuery` | Token validation | — |
| `kAiringScheduleQuery` | Calendar (anime) | `$page $perPage $airingAt_greater $airingAt_lesser` (epoch seconds), `sort: TIME` |
| `kMangaReleasesQuery` | Calendar (manga) | `$startDate_greater $startDate_lesser`, `type: MANGA`, `sort: POPULARITY_DESC` |
| `kCharacterSearchQuery` / `kStaffSearchQuery` / `kStudioSearchQuery` | Search tabs; empty search ⇒ `FAVOURITES_DESC` | `$page $perPage $search` |
| `kStaffWorksQuery` / `kCharacterWorksQuery` / `kStudioWorksQuery` | Person/studio profiles | `$id $page $perPage` |
| `kNotificationsQuery` | Notifications — **needs token** | `$perPage`, `type_in: [AIRING, RELATED_MEDIA_ADDITION, MEDIA_DATA_CHANGE]` |
| `kViewerProfileQuery` | Profile statistics | `Viewer` + `statistics.anime/manga` + `favourites` |
| `kMediaListCollectionQuery` | Full AniList list — **needs token** | `$userId $type $status` (`null` ⇒ full collection) |
| `kFavouriteAnimeQuery` | Favourites page | `$id $page $perPage` |
| `kViewerActivityQuery` | Recent activity | `$userId $perPage`, `sort: ID_DESC` |

Shared selections: `kMediaListSelection`, `kMediaDetailSelection`,
`kMediaCardSelection` (compact, for people/notifications/list rows).

> `$minScore` is mapped to AniList's `averageScore_greater` field at request-build
> time. The detail query is by id and intentionally does **not** filter `isAdult`.

---

## Request and response examples

### HTTP request shape

```http
POST https://graphql.anilist.co HTTP/1.1
Content-Type: application/json; charset=utf-8
Accept: application/json
Authorization: Bearer <token>          # only when signed in
User-Agent: <flutter http default>

{"query":"query BrowseMedia($page: Int, ...) {...}","variables":{"page":1,"perPage":25,"type":"ANIME"}}
```

### Query — fetch a single user's list entry

```graphql
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
```

Variables: `{ "id": 21 }`

Success response:

```json
{
  "data": {
    "Media": {
      "id": 21,
      "mediaListEntry": {
        "id": 123456789,
        "mediaId": 21,
        "status": "CURRENT",
        "progress": 11,
        "score": 82,
        "updatedAt": 1761900000
      }
    }
  }
}
```

Note `score(format: POINT_100)` — AniList normalises every score format to 0–100,
which the app stores directly and displays divided by 10.

### Mutation — remove a list entry

```graphql
mutation DeleteMediaListEntry($id: Int) {
  DeleteMediaListEntry(id: $id) {
    deleted
  }
}
```

Variables: `{ "id": 123456789 }` — **the `MediaList` entry id**, not the media id.

```json
{ "data": { "DeleteMediaListEntry": { "deleted": true } } }
```

### Mutation — save a list entry

```graphql
mutation SaveMediaListEntry($mediaId: Int, $status: MediaListStatus, $progress: Int, $scoreRaw: Int) {
  SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, score(format: POINT_100, amount: $scoreRaw)) {
    id mediaId status progress score(format: POINT_100) updatedAt
  }
}
```

> `$progress` and `$scoreRaw` are always sent as **absolute** values, never deltas.
> A retried request is therefore idempotent — a duplicate "+1" can never become "+2".

### Error response (HTTP 200 with `errors`)

```json
{
  "errors": [
    { "message": "Invalid token", "status": 401, "locations": [{"line": 2, "column": 3}] }
  ],
  "data": null
}
```

AniList mirrors the GraphQL error's own `status` into `errors[i].status`, and
sometimes returns HTTP 200 with errors in the body. The hand-written client reads the
numeric status from `errors[i]` when the HTTP status is 200.

### Partial data (non-2xx with usable `data`)

AniList occasionally returns **HTTP 400/404 with a partial `data` payload**.
`AniListHttpClient` detects this (`_hasUsableData` — a `data` map with at least one
non-null value) and **re-wraps the response as HTTP 200**, so downstream parsing
succeeds. `AniListClient` does the equivalent: partial `data` wins over sibling
`errors`, which are logged via `dart:developer` as
*"AniList returned partial data with errors: …"*.

---

## Rate limits

| Property | Value |
| --- | --- |
| AniList nominal limit | ~90 req/min (degrading to ~30/min when abused) |
| Our configured budget | **`requestsPerMinute = 80`** — deliberate headroom under 90 |
| Window | **Sliding, 1 minute** (`_window = Duration(minutes: 1)`) |
| Scope | **Per browser tab.** Two open tabs share AniList's real limit. |
| Queue behaviour | Timestamps are reserved **synchronously** before returning, so concurrent waiters cannot race past the gate. When full, sleep `(window − age(oldest)) + 25 ms`, then re-check. |

### Why 80 and not 90

AniList's own ceiling is not a hard contract — it drops to 30 when it decides you are
abusing it, and recovery is slow. Running at 80 leaves room for the auth `Viewer`
calls and the user's own navigations without tripping the limiter.

### You cannot bypass it

`cacheAndNetwork` **alone costs requests; it does not save them** — every visit would
hit AniList. The `FreshnessTracker` (cache-first inside the TTL, cache-and-network
past it) is what actually keeps us under the limit. See
[DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md).

### Header visibility on the web

CORS hides `Retry-After` from browser JavaScript. When the header is unavailable the
client falls back to `5 s × (attempt + 1)` — 5 s, then 10 s — rather than a short
backoff, which would just re-hit the limit.

---

## Retry, backoff, and 429 handling

`AniListHttpClient` (constructor defaults: `maxRetries = 2`, `timeout = 20 s`,
`_maxAutoWait = 60 s`):

| Failure | Behaviour |
| --- | --- |
| **429** | Set `_blockedUntil = now + wait` — **pauses every queued request**, not just this one. `wait = Retry-After ?? 5 s × (attempt+1)`. Retry while `wait ≤ 60 s` **and** `attempt < 2`; otherwise throw `ErrorKind.rateLimit` with `statusCode: 429` and `retryAfter`. |
| `http.ClientException` / **5xx** | Retry while `attempt < 2` with `_backoffDelay(attempt)`: `base = 500 × 2^attempt ms`, jittered **±25 %** (`base × 0.25 × (rand×2 − 1)`). |
| **Timeout** | No retry — immediately `ErrorKind.network`, *"AniList request timed out"*. |
| **400 / 404 / 401 / 403** | Classified (see below), **not** retried. |
| Non-`http.Request` bodies (streaming/multipart) | Skip the retry loop entirely — gate + timeout only. |

The hand-written `AniListClient` mirrors this with `maxRetries = 2`,
`maxAutoRetryWait = 60 s`, and backoff `500 × 2^(attempt−1) ms ±25 %`, retrying only
`network` / `rateLimit` / `server` kinds. A 429 whose `Retry-After` exceeds 60 s is
surfaced immediately rather than held.

---

## Error handling

Everything crosses layer boundaries as **`AppException`** (`lib/core/utils/app_exception.dart`):

```dart
class AppException implements Exception {
  const AppException(this.kind, this.message,
      {this.cause, this.statusCode, this.retryAfter});
}
```

| Field | Meaning |
| --- | --- |
| `kind` | `ErrorKind` enum — carries semantics |
| `message` | **Developer-facing** (status code, GraphQL text). Never shown to users. |
| `statusCode` | HTTP status when there was one |
| `retryAfter` | Server-requested wait for rate limits |
| `userMessage` | **User-facing copy**, derived from `kind` |

### `ErrorKind` and HTTP classification

`AniListHttpClient._classify`:

| Status | `ErrorKind` | Condition |
| --- | --- | --- |
| 429 | `rateLimit` | with `retryAfter` attached |
| 400 | `badRequest` | |
| 404 | `notFound` | |
| 401 | `unauthorized` | **only if a token was sent** |
| 403 | `forbidden` | **only if a token was sent** |
| other non-2xx | `server` | |
| timeout / client exception | `network` | |

The token condition matters: an unauthenticated 401/403 from AniList is usually a
Cloudflare block or a refused anonymous request, not "your session expired", so it is
classified as `server` to avoid signing the user out.

`AniListClient._classify` does the same from **numeric status only**, preferring
`errors[i].status` when HTTP is 200.

### GraphQL error mapping — `toAppError(OperationException)`
(`lib/state/graphql_providers.dart`)

| Source | Result |
| --- | --- |
| Link exception that already **is** an `AppException` | Passed through unchanged |
| Other link exception | `ErrorKind.network` |
| GraphQL `errors[]` | `ErrorKind.server`, messages joined |

### User-facing copy

| `Kind` | Message |
| --- | --- |
| `rateLimit` | *"AniList is rate-limiting requests right now."* + a wait hint — "Wait a moment", "Wait a minute" (≤ 60 s), or "Try again in about N minutes" |
| `validation` | The `message` is passed straight through (developer text is intended) |
| everything else | A generic friendly string derived from the kind |

### Other mappings

| Source | Result |
| --- | --- |
| `AniListAuthRepository._fetchViewer` | 400 on the fixed `Viewer` query → `unauthorized` |
| `LocalTrackingRepository` | failed persist → `storage`; missing entry → `notFound` |
| `MediaRepository` | missing title/studio/staff/character → `notFound`; missing `Viewer` profile → `server` |

---

## Client implementation

### `AniListHttpClient extends http.BaseClient`
(`lib/data/graphql/anilist_http_client.dart`)

Responsibilities, in the order they apply:

1. **Rate gate** — `_acquire()`: sliding 1-minute window, 80 slots, synchronous
   reservation, sleep-and-recheck when full.
2. **Global 429 pause** — `_blockedUntil` is honoured by `_acquire()`, so all queued
   requests wait it out together.
3. **Timeout** — every request wrapped in `.timeout(20 s)`.
4. **Partial-data rescue** — non-2xx with usable `data` re-wrapped as 200.
5. **Retry with jittered backoff** — for `ClientException` / 5xx only.
6. **Classification** — failures become `AppException` before leaving the client.

### `AniListClient` (`lib/data/anilist/anilist_client.dart`)

Hand-written, no rate gate. Retries `network`/`rateLimit`/`server`, honours
`Retry-After ≤ 60 s`, classifies from numeric status (preferring `errors[i].status`),
and prefers partial `data` over sibling `errors`.

### `GqlCatalog` (`lib/state/gql_catalog.dart`)

The **one-shot SWR layer** above the client. `_fetch(doc, operation, vars, ttl)`:

```
isFresh(key, ttl)?  yes → FetchPolicy.cacheOnly     (0 requests)
                    no  → FetchPolicy.networkOnly   (always real)
on data:            touch(key) ONLY if !hasException && isUsable(data)
on network failure: fall back to a cacheOnly stale read, else throw toAppError(...)
```

`raw(document, variables, {token})` is the seam handed to `MediaRepository` as its
`transport`:

- **`token != null` → always `networkOnly`.** Private data must never be answered from
  a cache entry.
- No token → the normal 10-minute freshness window.

A degraded/empty page that still claims `hasNextPage` is **shown but not marked
fresh**, so the next read tries the network again.

### `MediaRepository` (`lib/data/repositories/media_repository.dart`)

Sits above both clients and adds:

- **In-memory LRU cache** — `Map<String, _CacheEntry>`, `maxCacheEntries = 120`,
  default `cacheTtl = 5 min`; expired entries evicted first, then least-recently-used.
- **In-flight dedupe** — `Map<String, Future>`; concurrent widgets racing the same key
  share **one** upstream request. This exists specifically to protect the rate budget.
- **Page caps** — `maxPerPage = 50`, `maxSchedulePages = 24`, `maxMangaPages = 4`,
  `staffUpstreamPages = 3`.
- **Negative caching** — trending/browse/accountList/favourites/activities/
  notifications cache **non-empty** results only.
- **`transport` seam** — when set (it is, in production, with `GqlCatalog.raw`), every
  request goes through it instead of `_client.query`.

---

## What is not implemented

| Not implemented | Consequence |
| --- | --- |
| **Refresh token** | Sessions end only when AniList rejects the token; `tokenExpiresAt` is never enforced locally. |
| **OAuth scopes** | The implicit grant requests none. |
| **Webhooks / subscriptions** | No push, no live updates. Notifications are polled on screen load. |
| **Server-side component** | No backend, no caching proxy, no request batching service. |
| **Request batching** | One HTTP POST per operation. |
| **API version pinning** | AniList has no versioned endpoint; schema changes are absorbed defensively by the mapper. |

---

## Related documents

- Migration history and remaining work → [GRAPHQL_MIGRATION.md](GRAPHQL_MIGRATION.md)
- Cache TTLs and freshness keys → [DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md)
- Provider wiring and retry policy → [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)
- Layering → [ARCHITECTURE.md](ARCHITECTURE.md)
