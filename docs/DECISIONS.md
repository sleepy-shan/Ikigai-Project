# Architecture decision records

Why Ikigai is built the way it is. Each record captures the context, the decision,
alternatives considered, the reasoning, and the **consequences — including the
downsides**.

## Index

| ID | Decision | Status |
| --- | --- | --- |
| [ADR-001](#adr-001--flutter-web-as-the-only-target-platform) | Flutter Web as the only target platform | Accepted |
| [ADR-002](#adr-002--riverpod-3-with-hand-written-providers-no-codegen) | Riverpod 3 with hand-written providers, no codegen | Accepted |
| [ADR-003](#adr-003--graphql_flutter-plus-a-hand-written-rate-limited-http-client) | `graphql_flutter` + a hand-written rate-limited HTTP client | Accepted |
| [ADR-004](#adr-004--stale-while-revalidate-with-a-freshness-tracker) | Stale-while-revalidate with a freshness tracker | Accepted |
| [ADR-005](#adr-005--two-storage-tiers-shared_preferences-and-hive) | Two storage tiers: `shared_preferences` and Hive | Accepted |
| [ADR-006](#adr-006--implicit-grant-oauth-with-fragment-only-capture) | Implicit-grant OAuth with fragment-only capture | Accepted |
| [ADR-007](#adr-007--optimistic-overlay-for-list-mutations) | Optimistic overlay for list mutations | Accepted |
| [ADR-008](#adr-008--hand-written-domain-models-freezed-only-for-graphql) | Hand-written domain models; freezed only for GraphQL | Accepted |
| [ADR-009](#adr-009--guest-mode-is-first-class-no-route-guards) | Guest mode is first-class — no route guards | Accepted |
| [ADR-010](#adr-010--local-first-tracking-with-add-only-import) | Local-first tracking with add-only import | Accepted |
| [ADR-011](#adr-011--ci-tracks-flutter-stable-unpinned) | CI tracks Flutter `stable`, unpinned | Accepted — **disputed** |
| [ADR-012](#adr-012--flutter-analyze-as-the-sole-ci-quality-gate) | `flutter analyze` as the sole CI quality gate | Accepted — **technical debt** |

---

## ADR-001 — Flutter Web as the only target platform

**Context.** A catalogue app with no backend of its own, wanting zero-cost hosting and
a single codebase. The original MVP shipped as Flutter Web and stayed that way.

**Decision.** Build and deploy only the web target. `.metadata` records migrations for
`root` and `web`; no `android/`, `ios/`, `windows/`, `linux/`, or `macos/` directories
exist.

**Alternatives considered**
- *React / Vue SPA* — a larger ecosystem for the web, but splits the team across two
  languages and loses `CustomPainter` for the logo, aurora background, and animated
  banners.
- *Flutter multi-platform from day one* — higher up-front cost before the product
  shape was known.

**Rationale.** One language for UI, state, and data; `flutter build web` produces a
self-contained bundle any static host can serve; ~90 Dart files with no
platform-specific code.

**Consequences**
- ✅ Trivial deployment — a static directory, no server or runtime.
- ✅ Canvas-quality vector graphics without image assets.
- ❌ **No isolates on web** — `compute()` cannot move JSON parsing off the main
  thread; performance work is limited to small pages and narrow rebuilds.
- ❌ Adding a platform later requires `flutter create .` **plus** solving the OAuth
  fragment redirect, which currently assumes a browser returning to the app origin.
- ❌ Flutter's default web renderer is used; no renderer tuning exists.

---

## ADR-002 — Riverpod 3 with hand-written providers, no codegen

**Context.** The app needs ~40 providers spanning infrastructure, async data, and
user-driven controllers.

**Decision.** `flutter_riverpod 3.4.3`, all providers written by hand as top-level
`final …Provider = …` globals. Controllers are `Notifier<T>` + `NotifierProvider`.
**No `riverpod_annotation` / `riverpod_generator`.**

**Alternatives considered**
- *Riverpod codegen (`@riverpod`)* — type-safe generated providers, at the cost of a
  second generator.
- *Bloc* — explicit event/state plumbing; much more boilerplate per feature.
- *Provider* — older API, no compile-time-safe `ref`, `BuildContext`-coupled reads.
- *GetX* — service locator + routing + reactive state in one; tightly coupled and
  hard to test in isolation.
- *`StateNotifier`* — superseded by `Notifier` in Riverpod 3.

**Rationale.** The project already runs `build_runner` for `freezed`/`json_serializable`
(ADR-008). Adding a second generator increases cold-build time and creates another
class of "forgot to regenerate" failures. At 41 providers, hand-written declarations
are still legible.

**Consequences**
- ✅ One generator pass instead of two.
- ✅ Provider declarations are plain Dart — greppable, no generated indirection.
- ✅ Riverpod 3 features still available: unified `Ref`, the `retry:` parameter,
  `ref.mounted`, `ref.listen` inside providers.
- ❌ No codegen-level safety for provider signatures or autoDispose leaks.
- ❌ Provider wiring is not compiler-verified against unused/incorrect overrides.
- ❌ Adding a generator later means touching every provider.

---

## ADR-003 — `graphql_flutter` plus a hand-written rate-limited HTTP client

**Context.** AniList is GraphQL-only with a ~90 req/min limit that degrades to ~30
when it decides you are abusing it. `graphql_flutter` provides caching and link
composition but knows nothing about AniList's limits. CORS hides `Retry-After` in
browsers.

**Decision.** Use `graphql_flutter` for the client, cache, and link chain, and push
the entire transport concern into a custom `http.BaseClient` — `AniListHttpClient` —
which owns a sliding-window rate gate, a global 429 pause, jittered exponential
retries, timeouts, and partial-data rescue. Keep the older hand-written
`AniListClient` for the auth path and as a fallback transport.

**Alternatives considered**
- *Raw `http` only* — maximum control, but reimplements normalised caching,
  `watchQuery` streams, and fetch policies.
- *`dio` interceptors* — another dependency for behaviour a `BaseClient` already
  provides; the project uses `http` throughout.
- *Rate limiting in the repository* — would be bypassed by any direct provider read,
  and cannot pause *other* in-flight requests on a 429.

**Rationale.** The library's strengths and AniList's constraints live at different
layers. A `BaseClient` sits beneath everything, so **one gate covers every request**,
and a 429 can pause the whole queue rather than one call.

**Consequences**
- ✅ Rate logic is isolated and testable without GraphQL in the loop.
- ✅ Failures surface as `AppException`, so existing error UI never cared that the
  transport changed.
- ✅ Partial-data-on-non-2xx responses are rescued transparently.
- ❌ **Two HTTP paths coexist** to maintain (`graphql/` production, `anilist/` auth +
  fallback).
- ❌ A dependency upgrade can invalidate assumptions written without compiling
  against it (see [GRAPHQL_MIGRATION.md — Verify first](GRAPHQL_MIGRATION.md#verify-first)).
- ❌ Per-tab scope means two open tabs share the real limit.

---

## ADR-004 — Stale-while-revalidate with a freshness tracker

**Context.** GraphQL caching policies are per-request choices. `cacheAndNetwork` always
paints fast but **always costs a request**; `cacheFirst` never revalidates and goes
stale; `networkOnly` is correct but slow. AniList's rate limit makes "always fetch" a
production outage waiting to happen.

**Decision.** Record a **last-successful-fetch timestamp per operation+variables** in a
separate Hive box, and choose the fetch policy from it:

```
fresh  → FetchPolicy.cacheOnly        (0 ms, 0 requests)
stale  → FetchPolicy.cacheAndNetwork  (cache paint, then revalidate)
```

Touch the stamp **only on a clean, usable network result.**

**Alternatives considered**
- *`cacheAndNetwork` everywhere* — simple, but every page visit burns rate budget.
- *Long fixed TTLs* — crude; a 30-minute detail TTL and a 2-minute search TTL express
  real differences in volatility.
- *Server-side cache* — no backend exists (ADR-001).
- *ETag/If-None-Match* — not exposed by AniList's GraphQL endpoint.

**Rationale.** This is the mechanism that actually keeps the app under the rate limit.
It also gives a genuinely better UX: 0 ms paint inside the TTL, background refresh
after it.

**Consequences**
- ✅ 0 ms first paint from persisted cache; requests scale with real staleness.
- ✅ Degraded/empty responses are shown but **not** marked fresh, so the system
  self-heals on the next read.
- ❌ A third storage box to version alongside the response cache.
- ❌ Key derivation must be deterministic (sorted variables, FNV-1a 32-bit for Hive's
  ASCII/255-char key limit).
- ❌ `SwrResult`'s `isRefreshing` / `refreshError` were built to make revalidation
  visible — **the UI does not read them yet**, so refreshes are silent.

---

## ADR-005 — Two storage tiers: `shared_preferences` and Hive

**Context.** The app persists credentials, user-owned lists, settings, and a
high-churn normalised response cache, entirely in the browser.

**Decision.** Split by data kind: `shared_preferences` (localStorage) for user data and
settings; Hive via `graphql_flutter` (IndexedDB) for the GraphQL response cache and
freshness stamps. Tokens go in neither cache — only in preferences.

**Alternatives considered**
- *Everything in `localStorage`* — a ~5 MB synchronous string store; bulk cache deletes
  and high churn are a poor fit, and mixing credentials with cache complicates wiping.
- *Everything in Hive* — Hive boxes are held fully in memory and are **not
  multi-tab safe**; bad properties for credentials.
- *Drift / sqflite / Isar* — **rejected because there are no relational queries.**
  Every read is "a page of entities" or "my list". An ORM adds codegen, a migration
  story, and on web a WASM/IndexedDB bridge for zero query benefit.

**Rationale.** Isolating the cache lets it be wiped wholesale when the signed-in user
changes without touching the token or settings. Preferences give inspectable,
long-lived, small JSON.

**Consequences**
- ✅ `store.reset()` clears the entire cache in one call on user change.
- ✅ Legacy `sandwich.*` → `ikigai.*` migration is a simple read-once fallback.
- ❌ **Two blocked-storage fallbacks to maintain** (mock preferences; in-memory
  GraphQL store) — both required so a private-mode browser still boots.
- ❌ Full-document JSON writes for tracking; no query ability.
- ❌ No schema migration tooling — keys are versioned manually (`ikigai.tracking.v1`).

---

## ADR-006 — Implicit-grant OAuth with fragment-only capture

**Context.** Optional AniList sign-in with no backend.

**Decision.** Use OAuth 2.0 **implicit grant** (`response_type=token`), no scopes, no
refresh token. Capture the token **only from the URL fragment**; ignore
`?access_token=` in the query string entirely. Enforce a 30-minute sign-in window and
scrub the fragment immediately.

**Alternatives considered**
- *Authorization code + PKCE* — the modern recommendation, but the public client flow
  still wants a backend or a token exchange to be meaningful, and none exists.
- *Manual token paste* — worse UX and trains users to handle secrets.
- *Backend token exchange* — would require the server this project deliberately does
  not have (ADR-001).

**Rationale.** The implicit grant is the only flow that works from a purely static
host. Reading only the fragment closes a real attack: with query-param acceptance, an
attacker could craft a link that signs a victim into the **attacker's** account.

**Consequences**
- ✅ No client secret anywhere; nothing to rotate or leak.
- ✅ Anti-CSRF posture: fragment-only + a 30-minute one-shot login window.
- ✅ The token never remains in the address bar or history.
- ❌ **No refresh token** — `tokenExpiresAt` is stored but never enforced; a session
  ends only when AniList rejects the token (HTTP 400 on `Viewer` → `unauthorized`).
- ❌ Redirects must return to a registered origin, which complicates adding native
  platforms later.
- ❌ Transient validation failures must be distinguished from real sign-outs, giving
  a 2 s → 5 s → 15 s → 30 s → 60 s retry ladder.

---

## ADR-007 — Optimistic overlay for list mutations

**Context.** Progress/status/score edits must feel instant, but the server is a remote
system that can fail, be rate-limited, or already hold different values.

**Decision.** Keep a **separate overlay map** of pending entries. The UI reads
`displayEntryProvider` = `overlay ?? serverEntry`. Mutations send **absolute** values
(not deltas), debounced 500 ms, coalesced while in flight, and **refused until the
server entry has loaded**. Rollback is deleting the overlay entry.

**Alternatives considered**
- *Write-through cache mutation* — mutate the normalised `Media:<id>` record directly.
  Rollback then needs a snapshot, and it pollutes a shared, account-agnostic record.
- *Refetch-only (pessimistic)* — correct but visibly laggy on every tap.
- *Send `+1` deltas* — idempotent-looking but **not** retry-safe: a duplicate request
  double-increments.
- *Snapshot before each edit* — extra bookkeeping for no benefit if server state is
  never touched.

**Rationale.** Because the server state underneath is never mutated, rollback is one
map delete. Absolute values make retries safe. Waiting for the server entry first
prevents a local progress of 1 from overwriting a real 11.

**Consequences**
- ✅ Instant UI feedback; trivial rollback; idempotent retries.
- ✅ Edits made during a round trip are preserved (overlay cleared only if unchanged).
- ❌ **A tap in the final 500 ms before tab close is lost** — the timer is cancelled
  without a final flush.
- ❌ Sync failures cannot fail the local edit, so they surface separately via
  `entrySyncErrorProvider` → snackbar — and that provider has **no dismiss**, so a
  stale error can persist.
- ❌ Adds a whole provider trio (`optimisticEntries`, `displayEntry`,
  `entrySyncError`) to reason about.

---

## ADR-008 — Hand-written domain models; freezed only for GraphQL

**Context.** Two JSON surfaces: AniList's GraphQL schema, and the app's own legacy
wire formats (snake_case keys, sentinel `copyWith`, defensive parsing).

**Decision.** Use `freezed` + `json_serializable` **only** for `data/graphql/models/`.
All of `data/models/` uses hand-written `toJson`/`fromJson`.

**Alternatives considered**
- *freezed everywhere* — less typing, but fights sentinel-based `copyWith`, snake_case
  keys, and `tryFromJson` tolerance.
- *json_serializable everywhere* — same friction, less help than freezed.
- *Dart 3 sealed classes / patterns* — would drop the `freezed_annotation` dependency,
  but `build_runner` output is already established and converters are written.

**Rationale.** The GraphQL models are mechanical mappings from a fixed schema, where
codegen removes real typing risk and enum drift is handled by converters that fall
back to `unknown`. The domain models encode product rules and tolerance for messy
input — exactly the cases codegen makes awkward.

**Consequences**
- ✅ AniList adding an enum value degrades instead of crashing.
- ✅ Legacy `sandwich.*`-era formats stay readable.
- ❌ **Two JSON idioms to maintain**, plus a bridge (`AnimeMedia.toMedia()`).
- ❌ Generated files are git-ignored, so a fresh clone does not compile until
  `build_runner` runs.

---

## ADR-009 — Guest mode is first-class; no route guards

**Context.** Discovery is the core value; sign-in only adds list synchronisation and
profile statistics.

**Decision.** No `GoRouter` redirect/guard exists. Every route is public. Sign-in is a
voluntary dialog.

**Alternatives considered**
- *Redirect unauthenticated users to `/`* — blocks the primary use case.
- *Soft guards (show the page, prompt for data)* — what the app does anyway, but
  implemented per screen rather than centrally.

**Rationale.** Forcing sign-in to browse a public catalogue would be hostile. AniList
metadata needs no token.

**Consequences**
- ✅ Anyone can use the full discovery experience immediately.
- ✅ Deep links always resolve, even for logged-out visitors.
- ❌ **Every auth-gated screen must handle signed-out state itself** — profile,
  notifications, lists. This is repeated per screen rather than enforced centrally.
- ❌ Nothing prevents a UI regression from silently assuming `accessToken != null`.

---

## ADR-010 — Local-first tracking with add-only import

**Context.** Users need a watchlist with or without an account, and syncing must not
destroy data.

**Decision.** The local list (`ikigai.tracking.v1`) is **the UI source of truth**.
Signed-in edits *mirror* to AniList with absolute values, debounced. **Import from
AniList only adds missing titles** — never overwrites, never deletes.

**Alternatives considered**
- *Full bidirectional sync* — requires conflict resolution (last-write-wins? field
  merge?), tombstones for deletions, and a connection queue. Far more complexity than
  the feature warrants.
- *AniList-only when signed in* — makes sign-in a hard requirement (violating
  ADR-009) and loses the list on sign-out.
- *Push deletions* — a local delete would remove a server entry the user may have
  created elsewhere; irreversible.

**Rationale.** The safe default is "never lose the user's data". Add-only import can
be annoying (re-deleted titles return) but is never destructive.

**Consequences**
- ✅ Guests get a full-featured list with zero setup.
- ✅ No conflict resolution, no tombstones, no connection queue.
- ✅ Local edits never fail because a sync failed.
- ❌ **Local deletions are never pushed** to AniList.
- ❌ An edit is skipped entirely if the server entry cannot be read — nothing is sent
  on a guess.
- ❌ Sync logic lives in `OptimisticEntries`, **outside** `TrackingRepository`, so the
  repository interface does not express the full behaviour.

---

## ADR-011 — CI tracks Flutter `stable`, unpinned

**Context.** The deploy workflow uses `subosito/flutter-action@v2` with
`channel: stable` and `cache: true`, and no version constraint.

**Decision.** Always build against the latest stable Flutter.

**Alternatives considered**
- *Pin an exact version (`flutter-version: 3.47.9`)* — reproducible; requires a
  deliberate upgrade process.
- *Pin a major channel (`3.47.x`)* — a middle ground.

**Rationale.** For a solo/fast-moving project, staying current avoids maintaining a
pin and keeps security/tooling updates automatic.

**Consequences**
- ✅ No pin maintenance; always-current toolchain.
- ❌ **Builds are not reproducible** — the same commit can build with a different
  Flutter version tomorrow.
- ❌ A breaking Flutter release can take the pipeline down with **no repository change
  at all**.
- ❌ Local/CI drift: developers on 3.47.9 may not match CI.
- ❌ Harder to bisect a regression introduced by a toolchain change.

> **Status: accepted, but disputed.** If CI ever breaks without a code change, the
> first suspect is this decision. Pinning costs one line and a quarterly bump.

---

## ADR-012 — `flutter analyze` as the sole CI quality gate

**Context.** CI runs `pub get` → `build_runner` → `flutter analyze` → build. The
`flutter test` step is **commented out**, with a comment explaining it *"guards the
auth/session regressions (browser refresh, rate-limited validation, stale profile
snapshot) before anything is deployed."*

**Decision.** Ship with static analysis only. No tests, no custom lints, no
`dart format --set-exit-if-changed`, no coverage threshold.

**Alternatives considered**
- *Restore the 20-file suite* — it exists in history (`git checkout 0a4be39^ -- test/`)
  but has bit-rotted across 19 days of development and would need repair.
- *Write a minimal smoke test first* — cheap, but the CI step is commented out
  regardless.
- *Add coverage gates immediately* — meaningless against 0 % coverage.

**Rationale.** The suite was removed on 2026-10-29 (`chore: stop tracking test folder`).
This ADR exists to make the resulting exposure **explicit rather than implicit**.

**Consequences**
- ✅ Fast, simple pipeline; no flaky-test risk.
- ❌ **No regression safety net.** Auth, rate limiting, pagination, and the tracking
  status rules can all break silently.
- ❌ The exact classes of bug the workflow comment names are unprotected.
- ❌ Nothing prevents a formatting or lint regression beyond stock `flutter_lints`.
- ❌ Reviewers cannot lean on CI for behavioural verification.

> **Status: accepted, flagged as technical debt.** Tracked as
> [KI-001](KNOWN_ISSUES.md). Recommended order: restore the suite → fix what no longer
> compiles → uncomment `flutter test` → *then* add coverage thresholds.

---

## Decisions not yet made

Open questions with no ADR yet:

| Question | Options | Notes |
| --- | --- | --- |
| **Platform targets beyond web** | Stay web-only · add Android · add iOS | Native builds also need an OAuth redirect story ([DEPLOYMENT.md](DEPLOYMENT.md)) |
| **Test strategy going forward** | Restore the historical suite · rewrite · start minimal | See [TESTING.md](TESTING.md) |
| **Flutter version pinning** | Revisit ADR-011 if CI breaks without a code change | |
| **Notification delivery** | Local notifications · web push · nothing | Calendar reminders currently only persist a marker ([KI-003](KNOWN_ISSUES.md)) |
| **Accent colour UI** | Re-add the picker · remove the accent provider entirely | Currently applied with no way to change it ([KI-004](KNOWN_ISSUES.md)) |
| **Dead code** | Delete `filters_sheet.dart`, `StateView`, unused providers · wire them up | [KI-005](KNOWN_ISSUES.md), [KI-006](KNOWN_ISSUES.md), [KI-007](KNOWN_ISSUES.md) |
| **OAuth flow modernisation** | Stay implicit · move to PKCE with a backend | Constrained by ADR-001 (no backend) |
| **Commit message standard** | Formalise conventional commits · keep free-form | See [CONTRIBUTING.md](../CONTRIBUTING.md) |

---

## Writing a new ADR

1. Copy the structure: **Context · Decision · Alternatives considered · Rationale ·
   Consequences** (both ✅ and ❌) · **Status**.
2. Add a row to the index.
3. Link it from the relevant document.
4. If it supersedes an earlier record, mark that one **Superseded** and link forward —
   **never delete a decision record.**
