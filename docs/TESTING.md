# Testing

How Ikigai's quality is — and currently is **not** — verified.

## Contents

- [Current status](#current-status)
- [Testing strategy](#testing-strategy)
- [Test folder structure](#test-folder-structure)
- [Unit testing](#unit-testing)
- [Widget testing](#widget-testing)
- [Integration testing](#integration-testing)
- [Mocking APIs and repositories](#mocking-apis-and-repositories)
- [Test data and fixtures](#test-data-and-fixtures)
- [Test execution commands](#test-execution-commands)
- [Code coverage expectations](#code-coverage-expectations)
- [CI gap](#ci-gap)
- [Bug reproduction guidelines](#bug-reproduction-guidelines)

---

## Current status

> **There are no tests in this repository today.**
>
> | Fact | Detail |
> | --- | --- |
> | Test directory | **Absent.** No `test/` folder on disk. |
> | Test files | **Zero** `*_test.dart` anywhere in the working tree. |
> | Git tracking | `.gitignore` line 34 ignores `/test/`; line 35 ignores `/coverage/`. |
> | CI | `flutter test` is **commented out** in `.github/workflows/deploy-web.yml`. |
> | Dependency | `flutter_test` is still declared in `dev_dependencies` — it is available but unused. |

### What happened

20 test files (2,590 lines) were **removed from version control** in:

```
0a4be39  2026-10-29  chore: stop tracking test folder   (PR #27)
```

They were added with the original MVP on 2026-10-10 and deleted 19 days later. The
`.gitignore` entry means they will not return on their own.

### The removed suite (recovered from `git show 0a4be39`)

| File | Lines | Area |
| --- | --- | --- |
| `account_mapper_test.dart` | 347 | `data/anilist` mapping |
| `anilist_client_test.dart` | 123 | Hand-written client: retry, classification |
| `anilist_mapper_test.dart` | 171 | Defensive JSON mapping |
| `auth_redirect_test.dart` | 66 | OAuth fragment capture / anti-CSRF rules |
| `auth_restore_test.dart` | 53 | Session restore and sign-out paths |
| `browse_paging_test.dart` | 206 | Pagination and page fallback |
| `browse_query_test.dart` | 98 | `BrowseQuery` → GraphQL variables |
| `chip_contrast_test.dart` | 44 | **Colour contrast** of status chips |
| `external_link_test.dart` | 23 | `safeExternalUri` scheme allow-list |
| `formatters_test.dart` | 70 | `Formatters` |
| `history_test.dart` | 105 | History cap, reorder, removal |
| `local_tracking_repository_test.dart` | 223 | **List business rules** (status transitions) |
| `media_entry_test.dart` | 114 | `MediaEntry` JSON round-trip, `copyWith` |
| `nav_widgets_test.dart` | 75 | Navigation widgets |
| `pagination_bar_test.dart` | 198 | Pagination rendering/logic |
| `person_works_mapper_test.dart` | 88 | Person/studio mapping |
| `profile_banner_test.dart` | 63 | Banner presets |
| `profile_refresh_test.dart` | 358 | Profile load/refresh |
| `reveal_on_scroll_test.dart` | 36 | Scroll reveal |
| `widget_test.dart` | 129 | Smoke test |

**Note what that suite covered:** repositories, mappers, auth, formatters, and a
contrast check — precisely the "unit + a few widgets" shape described below. Restoring
it is the fastest way to close this gap.

> Recover with:
> ```bash
> git show 0a4be39^:test/local_tracking_repository_test.dart > test/local_tracking_repository_test.dart
> # or the whole tree:
> git checkout 0a4be39^ -- test/
> ```
> Then **remove `/test/` from `.gitignore`** and re-enable `flutter test` in CI.

---

## Testing strategy

The architecture was layered deliberately so that the highest-value code is the
easiest to test.

| Priority | What | Why it is worth testing | Difficulty |
| --- | --- | --- | --- |
| **1** | Pure logic and repositories | No widget tree, no I/O — `LocalTrackingRepository` status rules, `SearchFilters`, `Formatters`, `AppException.userMessage`, `FreshnessTracker` key derivation, `AniListMapper` defensive parsing | Easy |
| **2** | Notifier controllers | State/ **never imports ui/**, so controllers run with a `ProviderContainer` and no widgets | Medium |
| **3** | Individual components | Stateless-ish widgets with explicit inputs | Medium |
| **4** | Screens | Need `ProviderScope` + `GoRouter` + overrides | Hard |
| **5** | End-to-end | Needs a browser and the AniList API (or a mocked transport) | Hard |

**Guiding rule:** test behaviour the code promises, not implementation details. The
tracking status transitions and the OAuth redirect safety rules are far more valuable
than snapshotting a widget tree.

---

## Test folder structure

Mirror `lib/`:

```
test/
├── core/
│   ├── utils/
│   │   ├── app_exception_test.dart
│   │   ├── debouncer_test.dart
│   │   ├── external_link_test.dart
│   │   └── formatters_test.dart
│   └── theme/
│       └── design_tokens_test.dart
├── data/
│   ├── anilist/
│   │   ├── anilist_client_test.dart
│   │   └── anilist_mapper_test.dart
│   ├── models/
│   │   └── media_entry_test.dart
│   └── repositories/
│       ├── auth_repository_test.dart
│       ├── history_repository_test.dart
│       └── tracking_repository_test.dart
├── state/
│   ├── browse_controller_test.dart
│   ├── search_filters_test.dart
│   ├── swr_test.dart
│   └── tracked_entries_notifier_test.dart
├── ui/
│   ├── components/
│   │   ├── pagination_bar_test.dart
│   │   ├── status_badge_test.dart
│   │   └── chip_contrast_test.dart
│   └── screens/
├── fixtures/
│   ├── browse_media_page.json
│   ├── media_detail.json
│   ├── viewer_profile.json
│   └── media_list_collection.json
└── helpers/
    ├── fake_transport.dart
    └── pump_app.dart
```

---

## Unit testing

### Highest-value targets

| Target | What to assert |
| --- | --- |
| `LocalTrackingRepository` | Progress reaching `total` ⇒ `Completed`; dropping below total of a completed entry ⇒ `Watching`; progress > 0 on `Planning` ⇒ `Watching`; score clamped 0–10; progress clamped 0–total; `startedAt`/`completedAt` bookkeeping; mutating an unknown id ⇒ `ErrorKind.notFound` |
| `LocalHistoryRepository` | Cap at 50; re-opening moves to top; corrupt rows dropped, others kept; `clear()` |
| `SearchFilters` | Value equality; `without(key)`; `toQuery` mapping (manga drops season/source/minScore; manga + `seasonYear` becomes a start-date range); `criteriaFor` → 8 anime / 5 manga |
| `AppException` | Every `ErrorKind.userMessage`; rate-limit wait copy for ≤ 60 s and > 60 s; `validation` passes `message` through |
| `AniListMapper` | Malformed/partial payloads degrade instead of throwing; unknown enum → `unknown` |
| `FreshnessTracker` | Key is stable regardless of variable order; `isFresh` boundary; future timestamps are stale; `forget` forces network |
| `Formatters` | `clockTime`, `timeUntil`, `score`, `timeAgo`, `compactNumber` |
| `safeExternalUri` | `http`/`https` allowed; `javascript:`, `data:`, `file:` rejected |
| `BrowseQuery` | `_unset` sentinel distinguishes "not passed" from `null`; `activeFilterCount` |

### Example — tracking status rules

```dart
// test/data/repositories/tracking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ikigai_project/data/repositories/tracking_repository.dart';
import 'package:ikigai_project/data/models/media.dart';
import 'package:ikigai_project/data/models/media_entry.dart';

void main() {
  late LocalTrackingRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = LocalTrackingRepository(prefs);
  });

  Media media({required int id, int? episodes}) => Media(
        id: id,
        type: MediaType.anime,
        title: 'Title $id',
        episodes: episodes,
      );

  group('status transitions', () {
    test('progress reaching the total marks the entry completed', () {
      final m = media(id: 1, episodes: 12);
      repo.addOrUpdate(media: m, status: ListStatus.watching, progress: 11);
      repo.setProgress(mediaId: 1, progress: 12);
      expect(repo.entryFor(1)?.status, ListStatus.completed);
    });

    test('lowering progress below the total reopens a completed entry', () {
      final m = media(id: 2, episodes: 12);
      repo.addOrUpdate(media: m, status: ListStatus.completed);
      repo.setProgress(mediaId: 2, progress: 5);
      expect(repo.entryFor(2)?.status, ListStatus.watching);
    });

    test('progress on a planning entry starts it watching', () {
      final m = media(id: 3, episodes: 24);
      repo.addOrUpdate(media: m, status: ListStatus.planning);
      repo.setProgress(mediaId: 3, progress: 1);
      expect(repo.entryFor(3)?.status, ListStatus.watching);
    });

    test('editing an untracked id throws notFound', () {
      expect(
        () => repo.setProgress(mediaId: 999, progress: 1),
        throwsA(isA<Object>()),
      );
    });
  });
}
```

### Controller tests

`ProviderContainer` with overrides, no widgets required — this works **because
`state/` does not import `ui/`**:

```dart
final container = ProviderContainer(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    gqlStorageProvider.overrideWithValue(fakeStorage),
  ],
);
addTearDown(container.dispose);

final state = container.read(browseControllerProvider(MediaType.anime));
```

---

## Widget testing

### Worth testing

| Widget | Assertions |
| --- | --- |
| `StatusBadge` | Correct colour per `ListStatus`; type-aware label ("Reading" for manga); light-mode contrast adjustment |
| `PaginationBar` | Page bounds, disabled states, ellipsis rendering |
| `SectionHeader` | Eyebrow + action pill rendering |
| `SliverLoading` / `SliverError` / `SliverEmpty` | Message + retry callback fire |
| `ProfileBannerView` | Each `BannerPreset` builds without error |
| `AnimatedToggle` | `Semantics(toggled:)` reflects value |
| `SearchFiltersEditor` | Draft-then-apply: edits do not request until Apply |

### Pitfalls

- **Screens need infrastructure.** Wrap with:

  ```dart
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), /* … */],
      child: MaterialApp.router(routerConfig: testRouter),
    ),
  );
  ```

- **Generated code must exist.** Run `build_runner` before `flutter test` or the test
  target will not compile.
- **Network.** Never let a widget test hit AniList — override the transport (below).
- **Timers.** Search (400 ms) and sync (500 ms) use real `Timer`s. Use
  `fakeAsync`/`tester.pump(duration)` or you will hit *"A Timer is still pending"*
  teardown failures.
- **Golden tests are not set up.** `matchesGoldenFile` needs `flutter test --update-goldens`
  and a committed `goldens/` directory — neither exists.

---

## Integration testing

| Fact | Detail |
| --- | --- |
| Package | `integration_test` is **not** a dependency — it would need adding to `dev_dependencies` |
| Platform | Web integration tests need Chrome (`flutter drive --target=test_driver/app.dart --browser-name chrome`, or `flutter test integration_test --platform chrome`) |
| Network | Real AniList calls are rate-limited (80 req/min per tab) — an E2E suite must mock the transport or budget requests carefully |
| Status | **Not configured. Nothing to run today.** |

---

## Mocking APIs and repositories

No mocking library (`mockito`, `mocktail`, `nock`) is a dependency. The seams already
in the architecture are the intended approach.

### 1. Provider overrides (primary seam)

The data layer sits behind repository interfaces (`AuthRepository`,
`TrackingRepository`) and singletons are providers, so tests replace them wholesale:

```dart
final container = ProviderContainer(overrides: [
  sharedPreferencesProvider.overrideWithValue(prefs),
  trackingRepositoryProvider.overrideWithValue(FakeTrackingRepository()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository(user)),
]);
```

### 2. `SharedPreferences.setMockInitialValues({})`

The Flutter-provided in-memory implementation. **`main()` already depends on this**
as its blocked-storage fallback, so it is a supported path.

```dart
SharedPreferences.setMockInitialValues({
  'ikigai.theme': 'dark',
  'ikigai.tracking.v1': '[]',
});
```

### 3. The `transport` seam (network)

`MediaRepository` accepts `transport`, which is `GqlCatalog.raw` in production. Inject
a fake to intercept every repository request without touching HTTP:

```dart
final repo = MediaRepository(fakeClient, transport: (doc, vars, {token}) async => {
  'data': jsonDecode(fixture('browse_media_page.json')),
});
```

### 4. Fake GraphQL storage

`gqlStorageProvider` is overridden in `main()`; tests override it the same way to use
an `InMemoryStore` instead of Hive/IndexedDB.

### 5. What to avoid

Do not mock `GraphQLClient` directly, and do not stub `AniListHttpClient` internals —
both couple tests to the library version. Intercept at `transport` or at the
repository.

---

## Test data and fixtures

| Rule | Detail |
| --- | --- |
| Location | `test/fixtures/*.json` — real-shaped AniList responses |
| Use | `jsonDecode(File('test/fixtures/…').readAsStringSync())` or `rootBundle.loadString` |
| Content | Include the messy cases: `data` with sibling `errors`, partial data on a non-2xx, `null` optionals, unknown enum values, empty pages with `hasNextPage: true` |
| Fixtures are **not** present today | The directory does not exist; it must be created |
| Codegen prerequisite | `dart run build_runner build --delete-conflicting-outputs` before the first run |

Suggested starting fixtures, named after the documents that produce them:
`browse_media_page.json`, `media_by_id.json`, `my_entry_for_media.json`,
`airing_schedule.json`, `viewer_profile.json`, `media_list_collection.json`,
`error_rate_limited.json`, `partial_data.json`.

---

## Test execution commands

```bash
# Prerequisite — generated files are gitignored
dart run build_runner build --delete-conflicting-outputs

# Run everything
flutter test

# Run one file
flutter test test/data/repositories/tracking_repository_test.dart

# Run by name
flutter test --name "status transitions"

# Coverage (LCOV → coverage/lcov.info)
flutter test --coverage

# Update goldens (none exist yet)
flutter test --update-goldens
```

### Today's actual behaviour

`flutter test` reports **no tests** — `test/` does not exist (and is ignored, so
creating it locally will not show up in `git status` until `/test/` is removed from
`.gitignore`). This is expected, not a broken installation.

---

## Code coverage expectations

| Item | Status |
| --- | --- |
| Coverage tooling | Available via `flutter test --coverage` |
| Output | `coverage/lcov.info` — **`/coverage/` is git-ignored** (line 35) |
| CI reporting | **None.** No codecov/coveralls integration. |
| Baseline | **0 %** — no tests exist |

### Recommended targets once tests are restored

| Area | Target | Rationale |
| --- | --- | --- |
| `data/repositories/` | ≥ 80 % | Business rules that silently corrupt user data if wrong |
| `core/utils/` | ≥ 80 % | Small, pure, cheap to cover |
| `state/` controllers | ≥ 60 % | Fetch/status/pagination transitions |
| `ui/` | Spot checks only | Prioritise components with contrast or accessibility implications |
| Overall | ≥ 50 % as a floor | Do not chase a number; chase the rules |

Coverage gates should be added to CI **after** the suite is restored — enforcing a
number against 0 % coverage would just block every PR.

---

## CI gap

Current workflow (`.github/workflows/deploy-web.yml`):

```yaml
- run: flutter pub get
- run: dart run build_runner build --delete-conflicting-outputs
- run: flutter analyze

# Guards the auth/session regressions (browser refresh, rate-limited
# validation, stale profile snapshot) before anything is deployed.
# - run: flutter test        ← COMMENTED OUT
```

**The only quality gate on a deploy is `flutter analyze`.**

The workflow comment states the original intent — guarding *auth/session regressions
(browser refresh, rate-limited validation, stale profile snapshot)*. Those are exactly
`auth_restore_test.dart`, `anilist_client_test.dart`, and `profile_refresh_test.dart`
from the deleted suite.

### To close the gap

1. Recover the suite: `git checkout 0a4be39^ -- test/`
2. Remove `/test/` from `.gitignore`
3. Fix whatever no longer compiles after 19 days of development
4. Uncomment `- run: flutter test` in the workflow
5. Only then add a coverage threshold

Tracked as [KI-001](KNOWN_ISSUES.md).

---

## Bug reproduction guidelines

Include all of the following in an issue:

```markdown
### Steps to reproduce
1.
2.
3.

### Expected behaviour


### Actual behaviour


### Environment
- Deployed site / local build:
- Browser + version:
- OS:
- Signed in / guest:
- Screen width (approx):

### Console output
```
(paste red errors from DevTools / browser console)
```

### Frequency
- [ ] Always  [ ] Sometimes (n/10)  [ ] Once

### Additional context
Screenshots, recording, related issue links.
```

**Before filing**

1. `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs`
2. Reproduce on the deployed Pages build as well as locally (a base-href or cache
   problem will only appear in one).
3. Search [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
4. Note whether it reproduces with **guest mode** — that separates an auth-path bug
   from a general one.

---

## Related documents

- Layering (why controllers are testable) → [ARCHITECTURE.md](ARCHITECTURE.md)
- Error taxonomy → [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- Setup and commands → [SETUP_AND_DEVELOPMENT.md](SETUP_AND_DEVELOPMENT.md)
- CI/CD → [DEPLOYMENT.md](DEPLOYMENT.md)
- Known issues → [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- Contribution standards → [CONTRIBUTING.md](../CONTRIBUTING.md)
