# Tech stack

Why each technology was chosen, what it is used for, and what the trade-offs are.

## Snapshot

| Layer | Technology | Pinned version (from `pubspec.lock`) |
| --- | --- | --- |
| Framework | Flutter (stable channel) | **3.47.9** (framework rev `c197ca5199`, 2026-10-29) |
| Language | Dart SDK constraint | `^3.13.5` (resolved **3.13.7**) |
| State management | `flutter_riverpod` / `riverpod` | **3.4.3** |
| Navigation | `go_router` | **18.1.2** |
| GraphQL client | `graphql_flutter` / `graphql` | **5.3.0** / **5.2.4** |
| GraphQL AST | `gql`, `gql_exec`, `gql_http_link` | 1.0.1 / 1.1.1-alpha / 1.2.0 |
| HTTP | `http` | **1.6.0** |
| Local key-value store | `shared_preferences` (+ `_web`) | **2.5.6** |
| GraphQL response cache | `hive_ce` (via `graphql_flutter`) | **2.22.0** |
| Date formatting | `intl` | **0.20.3** |
| Carousel | `flutter_carousel_widget` | **4.0.1** |
| Skeleton loading | `shimmer` (+ `material_ui`) | **4.0.0** / 1.9.0 |
| External links | `url_launcher` | **6.3.3** |
| Immutable models | `freezed` / `freezed_annotation` | **4.0.3** / 3.1.0 |
| JSON serialisation | `json_serializable` / `json_annotation` | **6.15.2** / 4.12.0 |
| Code generation | `build_runner` | **2.17.1** |
| Lints | `flutter_lints` | **6.0.0** |
| CI/CD | GitHub Actions → GitHub Pages | `subosito/flutter-action@v2`, `actions/deploy-pages@v4` |

> Versions above are what is **actually resolved today**. `pubspec.yaml` declares
> caret constraints; run `flutter pub outdated` before assuming a constraint still
> matches the lockfile.

---

## 1. Flutter & Dart

**Chosen:** Flutter stable, Dart SDK `^3.13.5`, **web-only** target.

**Why.**
- One codebase and one language for UI, state, and data logic — the whole app is
  ~90 Dart files with no platform-specific code.
- Flutter Web ships as a self-contained bundle, which suits the GitHub Pages
  deployment target with no server of our own.
- `CustomPainter` gives real canvas drawing for the logo, the aurora background, and
  the nine animated profile banners without image assets or CSS.

**Trade-offs accepted.**
- Web is the **only** scaffolded platform. `.metadata` records migrations for `root`
  and `web` only; there are no `android/`, `ios/`, `windows/`, `linux/`, or `macos/`
  directories. Adding a platform means running `flutter create .` first.
- Dart isolates do not exist on the web, so `compute()` cannot move JSON parsing off
  the main thread. The mitigation is small pages and `select()`-driven rebuilds rather
  than background parsing — see [GRAPHQL_MIGRATION.md](GRAPHQL_MIGRATION.md).
- Flutter's default web renderer is used; no `--web-renderer` / canvaskit override is
  configured anywhere in the repo.

**Version pinning:** CI uses `channel: stable` **without** a pinned version, so the
pipeline tracks the latest stable at run time. Locally the project was developed on
3.47.9. This is a deliberate simplicity/consistency trade-off recorded in
[DECISIONS.md](DECISIONS.md).

---

## 2. State management — Riverpod 3

**Chosen:** `flutter_riverpod ^3.4.3`, **hand-written providers** (no codegen).

**Why.**
- Riverpod's compile-time-safe dependency injection removes the `BuildContext`
  boilerplate that `Provider.of` / `InheritedWidget` require, and its `ProviderScope`
  gives one obvious place to override infrastructure for tests and startup.
- Riverpod 3 specifically introduced a unified `Ref` type and the `retry:` provider
  parameter, both of which this app uses directly.
- **No `riverpod_annotation` / `riverpod_generator`.** All 41 providers are plain
  top-level `final …Provider = …` globals. The reasoning: the project already runs
  `build_runner` for `freezed`/`json_serializable`, and adding a second generator
  increases cold-build time and creates another class of "forgot to regenerate" errors
  for very little gain at this codebase size.

**What it is *not*.** No `StateNotifier`, `StateProvider`, `AsyncNotifier`, or
`StreamNotifier` appears anywhere. Controllers are `Notifier<T>` with explicit
`NotifierProvider` declarations; async data comes from `StreamProvider` / `FutureProvider`.

**Detail:** [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md).

---

## 3. Navigation — GoRouter

**Chosen:** `go_router ^18.0.2`.

**Why.**
- Declarative URL-first routing is what makes deep links like
  `/media/anime/123456?rail=trending` shareable and reload-safe on the web.
- A single `ShellRoute` wrapping `AppShell` means the sidebar/bottom nav and the
  aurora background persist across navigations instead of remounting on every route.
- `errorBuilder` gives a real 404 page rather than a blank screen.
- Query parameters (`?rail=`, `?tab=`, `?q=`) are read back into provider state on
  load, so a shared link reproduces the exact view.

**Trade-off.** There are **no route guards**. Every route is public and sign-in is
voluntary. This is intentional (guest mode is first-class) but means auth-gated
screens must each handle the signed-out state themselves.

**Route table:** [ARCHITECTURE.md](ARCHITECTURE.md#navigation-and-routing).

---

## 4. API integration — AniList GraphQL

**Chosen:** `graphql_flutter` for the link/cache machinery, plus a **hand-written
`http.BaseClient`** for rate limiting and retries.

**Why this split.**
- `graphql_flutter` gives normalised caching (`GraphQLCache`), `watchQuery` streams,
  fetch policies, and a `Link` chain — all of which are hard to rebuild correctly.
- It does **not** give AniList-aware rate limiting. AniList's limit is ~90 requests
  per minute (degrading to 30 when abused), and CORS hides the `Retry-After` header in
  browsers. That logic lives in `AniListHttpClient`, which owns a per-tab sliding
  window, a global 429 pause, jittered exponential backoff, and partial-data
  pass-through.
- A second, simpler client (`AniListClient`) still exists for the auth path and as a
  fallback transport. It shares the same error taxonomy but has no rate gate.

**Why not REST?** AniList's public API is GraphQL-only.

**Detail:** [API_DOCUMENTATION.md](API_DOCUMENTATION.md) and
[GRAPHQL_MIGRATION.md](GRAPHQL_MIGRATION.md).

---

## 5. Local storage & caching

Two stores, deliberately split by *what kind of data* it is:

| Store | Holds | Why here |
| --- | --- | --- |
| `shared_preferences` → browser `localStorage` | OAuth token, profile snapshot, tracking list, history, settings, calendar zone/reminders, banner preset | Small, synchronous-enough, human-inspectable JSON. Survives reloads. |
| Hive (`hive_ce` via `graphql_flutter`) → browser **IndexedDB** | Normalised GraphQL response cache + freshness timestamps | Key-value with a binary-ish store suited to the cache's churn; isolated from user data so it can be wiped freely. |

**Why Hive over plain `localStorage` for the cache:** the cache holds every normalised
entity from every response. `localStorage` is a synchronous string store with a ~5 MB
origin quota and no bulk delete; Hive gives namespaced boxes and a `store.reset()`
that clears the whole cache when the signed-in user changes.

**Why not Drift/sqflite/Isar:** the app has no relational queries. Everything is
"fetch a page of entities" or "read my list". A full ORM would add codegen, a schema
migration story, and (on web) a WASM/IndexedDB bridge for no query benefit.

**Fallbacks matter.** Private-mode browsers and storage-partitioned contexts can block
both stores. `main()` falls back to mock preferences, and `openGqlStorage()` falls back
to an in-memory store, so a blocked-storage browser still boots instead of showing a
white screen.

**Detail:** [DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md).

---

## 6. UI libraries & packages

| Package | Used for | Why this one |
| --- | --- | --- |
| `flutter_carousel_widget` | Home hero carousel | Battle-tested carousel with paging/indicator support; hand-rolling gesture physics is where custom carousels usually break. |
| `shimmer` | Skeleton loading placeholders (browse cards, calendar cards) | Only shimmer implementation needed; the effect is a simple gradient sweep. Paired with `material_ui` as required by shimmer 4.x. |
| `url_launcher` | Opening AniList pages and external links | Standard. Wrapped by `safeExternalUri`, which refuses any scheme other than `http`/`https`. |
| `intl` | Dates, times, relative times, number formatting | Locale-aware formatting without re-implementing calendars. |
| `cupertino_icons` | iOS-style icon set | Bundled default; used sparingly alongside Material icons. |

**Notably *not* used:** no `cached_network_image` (image caching is left to the
browser), no `dio` (the `http` package plus the custom client is enough), no
`get_it`/`injectable` (Riverpod is the container), no `equatable` (freezed generates
equality), no `flutter_gen` (assets are declared manually).

---

## 7. Code generation

**Chosen:** `freezed` + `json_serializable`, driven by `build_runner`.

**Where it is actually used** — this is narrower than the dependency list suggests:

- `lib/data/graphql/models/anime_media.dart` — freezed entities for the GraphQL layer.
- `lib/data/graphql/models/media_list_entry.dart` — freezed entry + `@JsonEnum`.
- `lib/state/anime_providers.dart` — one `@freezed` args class (`AnimePageArgs`).

**Everything else is hand-written.** The `lib/data/models/` domain models
(`Media`, `MediaEntry`, `HistoryEntry`, `ViewerProfile`, …) use manual
`toJson`/`fromJson`. This is a deliberate split: the GraphQL models are mechanical
mappings from a fixed schema where codegen removes real typing risk, while the domain
models have legacy wire formats, snake_case keys, sentinel values for `copyWith`, and
defensive parsing that codegen would fight.

**Configuration** (`build.yaml`):

```yaml
json_serializable:
  options:
    explicit_to_json: true   # nested freezed objects serialise recursively
    include_if_null: false   # omit nulls — smaller payloads, cleaner diffs
```

**Important:** `*.g.dart` and `*.freezed.dart` are **git-ignored**. A fresh clone does
not compile until `dart run build_runner build --delete-conflicting-outputs` has run.
CI and the VS Code pre-launch task both do this automatically.

---

## 8. Development tools

| Tool | Purpose |
| --- | --- |
| `flutter_lints ^6.0.0` | The lint set. Loaded from `package:flutter_lints/flutter.yaml` with **no custom rules enabled** — the `rules:` block in `analysis_options.yaml` contains only commented-out examples. |
| `flutter analyze` | The static-analysis gate. It is the **only** quality check that runs in CI. |
| `build_runner` | Generates freezed/json_serializable output. |
| **VS Code** (tracked in `.vscode/`) | One launch config (`Flutter (Debug)`) with a pre-launch task running `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze`. Settings are tuned for a low-memory container: watcher excludes for `build/`, `.dart_tool/`, `.git/`, `pubspec.lock`; `dart.runPubGetOnPubspecChanges: never`; UI guides and DevTools off. |
| `analysis_options.yaml` | Excludes `build/**` and `web/**` from analysis; includes `flutter_lints`. |

**Not configured:** no custom lint rules, no `dart_code_metrics`, no formatter
enforcement in CI (`dart format --set-exit-if-changed` does not run), no linter in the
pre-commit path.

---

## 9. CI/CD

**Chosen:** GitHub Actions building to GitHub Pages.

- `subosito/flutter-action@v2` (`channel: stable`, `cache: true`) — **not version
  pinned**.
- Build order: `pub get` → `build_runner` → `flutter analyze` → `flutter build web
  --release --base-href=/<repo>/`.
- `.nojekyll` is written so Jekyll does not strip the `_`-prefixed bundle files.
- `index.html` is copied to `404.html` after the build so deep links boot the SPA
  instead of 404ing.
- **`flutter test` is commented out** — there are no tracked tests to run.

**Detail:** [DEPLOYMENT.md](DEPLOYMENT.md).

---

## 10. Deliberate non-choices

| Considered | Why not |
| --- | --- |
| REST API layer | AniList is GraphQL-only. |
| Drift / sqflite / Isar | No relational queries; two key-value stores cover the need. |
| Riverpod codegen (`@riverpod`) | Extra generator + regeneration step; 41 hand-written providers is manageable. |
| `StateNotifier` | Superseded by `Notifier` in Riverpod 3. |
| `dio` | `http` + a custom `BaseClient` already provides the intercept-like behaviour needed. |
| `cached_network_image` | Browser HTTP cache handles it; avoids a second cache layer competing with the GraphQL cache. |
| `equatable` | freezed generates `==`/`hashCode`. |
| Route guards / auth walls | Guest mode is a first-class product decision. |
| Pinned Flutter version in CI | Favouring "always latest stable" over reproducibility; recorded as a decision with its downside. |
| `get_it` / `injectable` | Riverpod is the service locator. |

---

## Reading further

- Architecture and layering → [ARCHITECTURE.md](ARCHITECTURE.md)
- Provider inventory and async patterns → [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)
- Endpoints, queries, rate limits → [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- What each store holds → [DATABASE_AND_STORAGE.md](DATABASE_AND_STORAGE.md)
- Visual rules → [UI_DESIGN_GUIDELINES.md](UI_DESIGN_GUIDELINES.md)
- Why these trade-offs were made → [DECISIONS.md](DECISIONS.md)
