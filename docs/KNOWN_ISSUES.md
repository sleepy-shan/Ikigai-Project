# Known issues

A factual register of current bugs, limitations, workarounds, and scope gaps. Every
entry is traceable to something in the code — nothing here is speculative.

**Severity:** Critical · High · Medium · Low
**Status:** Open · By design · Needs decision · Fixed

## Summary

| ID | Sev | Area | Issue | Status |
| --- | --- | --- | --- | --- |
| [KI-001](#ki-001--no-tracked-tests) | Critical | Quality | No tracked tests; `flutter test` disabled in CI | Open |
| [KI-002](#ki-002--generated-files-are-gitignored) | Medium | Tooling | Fresh clone does not compile until `build_runner` runs | By design |
| [KI-003](#ki-003--calendar-reminders-never-deliver) | Medium | Feature | Calendar reminders store a marker but deliver no notification | Open |
| [KI-004](#ki-004--accent-colour-has-no-ui) | Low | Feature | Accent colour is applied but has no settings UI | Needs decision |
| [KI-005](#ki-005--dead-code-filters_sheetdart) | Low | Code health | `filters_sheet.dart` is dead code | Open |
| [KI-006](#ki-006--stateview-is-never-instantiated) | Low | Code health | `StateView` is defined but never used | Open |
| [KI-007](#ki-007--unused-providers) | Low | Code health | Two SWR providers are declared but never watched | Open |
| [KI-008](#ki-008--swrresult-status-fields-are-never-read) | Medium | UX | Refresh/cache/failure state is computed but never shown | Open |
| [KI-009](#ki-009--sync-error-has-no-dismiss) | Medium | UX | `EntrySyncError` can never be cleared | Open |
| [KI-010](#ki-010--stale-hive-boxes-are-never-deleted) | Low | Storage | Old versioned cache boxes accumulate | Open |
| [KI-011](#ki-011--unverified-graphqlclient-parameter) | Low | Risk | `queryRequestTimeout` written without compiling against the package | Open |
| [KI-012](#ki-012--no-refresh-token) | Low | Auth | Session ends only when AniList rejects the token | By design |
| [KI-013](#ki-013--rate-limiting-is-per-browser-tab) | Medium | Network | Two tabs share AniList's real limit | By design |
| [KI-014](#ki-014--hive-is-not-multi-tab-safe) | Medium | Storage | Concurrent tabs can race cache writes | By design |
| [KI-015](#ki-015--no-offline-write-queue) | Medium | Offline | No outbox; a tap in the last 500 ms is lost | Open |
| [KI-016](#ki-016--anilist-import-and-sync-limits) | Low | Sync | Add-only import; edits skipped when the server entry is unreadable | By design |
| [KI-017](#ki-017--web-is-the-only-platform) | Medium | Scope | No Android/iOS/desktop targets exist | By design |
| [KI-018](#ki-018--ci-does-not-pin-flutter) | Low | CI | Builds track latest stable; non-reproducible | Needs decision |
| [KI-019](#ki-019--no-custom-lints-or-format-check) | Low | CI | Only stock `flutter_lints`; no `dart format` gate | Open |
| [KI-020](#ki-020--unused-logo-asset) | Low | Code health | `assets/images/app_logo.svg` declared but never imported | Open |
| [KI-021](#ki-021--single-todo) | Low | Code health | The only `TODO` in the codebase | Open |
| [KI-022](#ki-022--no-service-worker) | Low | PWA | App is installable but has no offline shell | Open |
| [KI-023](#ki-023--production-uses-the-fallback-oauth-client) | Medium | Deploy | Pages workflow passes no `ANILIST_CLIENT_ID` | Needs decision |
| [KI-024](#ki-024--accessibility-is-not-verified) | Medium | A11y | No a11y tests, audit, or reduced-motion coverage | Open |

---

## KI-001 — No tracked tests

**Severity:** Critical · **Status:** Open

**Symptoms.** `flutter test` reports no tests. `git status` does not show a `test/`
directory being missing, because `/test/` is git-ignored.

**Root cause.** The suite was removed from version control in
`0a4be39` *"chore: stop tracking test folder"* (2026-10-29, PR #27) and
`/test/` added to `.gitignore` (line 34). The `flutter test` step in
`.github/workflows/deploy-web.yml` was commented out at the same time.

**Impact.** Auth/session regressions, rate-limit behaviour, pagination, and the
tracking status rules can all break silently — the exact classes the workflow comment
says the step was meant to guard.

**Workaround.** Review manually; rely on `flutter analyze`.

**Planned fix.**
1. `git checkout 0a4be39^ -- test/` (recovers 20 files / 2,590 lines)
2. Remove `/test/` from `.gitignore`
3. Repair what no longer compiles after 19 days of development
4. Uncomment `- run: flutter test`
5. Only then add coverage thresholds

---

## KI-002 — Generated files are gitignored

**Severity:** Medium · **Status:** By design

**Symptoms.** A fresh clone fails to compile with errors about missing `*.g.dart` /
`*.freezed.dart`.

**Root cause.** `.gitignore` lines 52–53 ignore `*.g.dart` and `*.freezed.dart`; the
sources use `part` directives for `anime_media`, `media_list_entry`, and
`anime_providers`.

**Workaround.** `dart run build_runner build --delete-conflicting-outputs`.

**Mitigating factors.** CI runs it automatically, and the VS Code
`flutter: optimized-prep` pre-launch task runs it before every debug launch.

**Planned fix.** None — commit generated output only if this ever becomes a recurring
cost.

---

## KI-003 — Calendar reminders never deliver

**Severity:** Medium · **Status:** Open

**Symptoms.** The bell icon on a calendar release card toggles between *"Remind me"*
and *"Remove reminder"*, implying an alarm. **No notification is ever delivered.**

**Root cause.** `CalendarRemindersController` persists a `Set<int>` of media ids to
`ikigai.calendar.reminders`. There is no scheduler, no local-notification plugin, and
no push registration anywhere in the project.

**Impact.** Misleading UI — users will reasonably expect a notification.

**Workaround.** Treat it as a "save for later" flag.

**Planned fix.** Either implement delivery (see [DECISIONS.md — open questions](DECISIONS.md#decisions-not-yet-made))
or relabel the control so it does not promise an alarm.

---

## KI-004 — Accent colour has no UI

**Severity:** Low · **Status:** Needs decision

**Symptoms.** The settings dialog states *"Theme mode only (accent color removed)"*.
Accent persists from earlier versions but cannot be changed.

**Root cause.** The picker was removed from `settings_dialog.dart`, but
`AccentController`, the `ikigai.accent` key, `AppAccent.fromName` legacy migration, and
`app.dart`'s `ref.watch(accentControllerProvider)` all remain. `setAccent` is never
called from any widget.

**Impact.** Working capability with no entry point; a small amount of live-but-unreachable
state.

**Planned fix.** Re-add the picker (six seeds are already defined in `AppAccent`), or
delete the provider and migration code entirely.

---

## KI-005 — Dead code: `filters_sheet.dart`

**Severity:** Low · **Status:** Open

**Symptoms.** `lib/ui/screens/filters_sheet.dart` defines `FilterSheet`, which is
referenced **nowhere else** in `lib/`.

**Root cause.** Superseded by `SearchFiltersEditor` (`FiltersLayout.panel` / `.sheet`)
and `BrowseFilterForm`.

**Impact.** ~1 misleading file; readers may implement new filters in the wrong place.

**Planned fix.** Delete the file.

---

## KI-006 — `StateView` is never instantiated

**Severity:** Low · **Status:** Open

**Symptoms.** `StateView<T>` in `lib/ui/components/state_views.dart` has no call
sites. Its only mention elsewhere is a doc comment in `sliver_headers.dart`.

**Root cause.** Screens embed the `LoadStatus` enum in their own state classes and
render with `SliverLoading` / `SliverError` / `SliverEmpty` (or an inline `switch`),
because most screens are sliver-based rather than box-based.

**Impact.** Dead API surface; `LoadState<T>` exists largely for it.

**Planned fix.** Either use `StateView` on genuinely box-based screens or remove it
and simplify `LoadState`.

---

## KI-007 — Unused providers

**Severity:** Low · **Status:** Open

**Symptoms.** `animePageProvider` and `animeByIdProvider` (`lib/state/anime_providers.dart`)
are declared but watched by no widget.

**Root cause.** The home rails reach the same underlying `animePageStream` function
through `mediaRailProvider`, which maps the `SwrResult` away.

**Impact.** Not harmful — they are available API surface with no side effects — but
they add to the provider inventory and may confuse readers.

**Planned fix.** Use them from the screens that need a raw `AnimePage`/`AnimeMedia`
stream, or remove them.

---

## KI-008 — `SwrResult` status fields are never read

**Severity:** Medium · **Status:** Open

**Symptoms.** `SwrResult.isRefreshing`, `fromCache`, and `refreshError` are populated
correctly but **`grep` finds no usage in `lib/ui/`**.

**Root cause.** `mediaRailProvider` maps `SwrResult<AnimePage>` → `MediaPage`;
`mediaDetailProvider` maps → `Media`. The wrapper is discarded at the provider
boundary.

**Impact.** Three designed affordances never appear:
- no subtle "refreshing" indicator (explicitly intended *not* to be a full-screen
  spinner),
- no visual distinction for the 0 ms cache paint,
- **no "we kept showing you old data, but the refresh failed — retry" path.** A failed
  background revalidation is currently indistinguishable from success.

**Workaround.** Users must manually refresh to discover stale data.

**Planned fix.** Stop discarding `SwrResult` at the provider boundary, or surface
`refreshError` through a separate lightweight provider.

---

## KI-009 — Sync error has no dismiss

**Severity:** Medium · **Status:** Open

**Symptoms.** `EntrySyncError` exposes only `void report(AppException e)`. There is no
`clear()`/`dismiss()`, and `state` is never reset to `null`.

**Root cause.** `tracked_entries_notifier.dart` calls `.report(...)` at two sites
(both `_flush` and `removeEntry` failure paths). `app_shell.dart` uses
`ref.listen(entrySyncErrorProvider, …)`, which fires **only on change**.

**Impact.** A reported error persists indefinitely. Because the listener only fires on
change, re-triggering the *same* error does not re-notify — and the state is stale
relative to reality (a later successful sync does not clear it).

**Workaround.** None from the UI.

**Planned fix.** Add `void clear()` and call it on the next successful flush, or model
it as a monotonically-increasing event counter instead of a held value.

---

## KI-010 — Stale Hive boxes are never deleted

**Severity:** Low · **Status:** Open

**Symptoms.** Bumping `kGqlBox`/`kMetaBox` (the documented remedy for a fragment or
model shape change) leaves the old boxes in IndexedDB forever.

**Root cause.** `openGqlStorage()`'s doc comment says stale boxes should be deleted
there, but the implementation only calls `open` on the two current names.

**Impact.** Accumulating dead storage across version bumps. No correctness impact —
old names are never opened again.

**Planned fix.** Delete any box whose name matches the prefix but not the current
version suffix.

---

## KI-011 — Unverified `GraphQLClient` parameter

**Severity:** Low · **Status:** Open

**Symptoms.** Potential construction-time failure after a `graphql` upgrade.

**Root cause.** `buildGraphQLClient` passes `queryRequestTimeout: Duration(seconds: 25)`
with an in-code comment: *"Verify this parameter name against your installed graphql
version."* It was written in an environment with no Flutter SDK or pub.dev access.

**Impact.** Currently works with `graphql 5.2.4` / `graphql_flutter 5.3.0`. A
dependency bump could rename or remove it.

**Planned fix.** Delete the comment and confirm the parameter against the lockfile
version; add a smoke test that constructs the client (see [KI-001](#ki-001--no-tracked-tests)).

---

## KI-012 — No refresh token

**Severity:** Low · **Status:** By design

**Symptoms.** A long-idle session can fail on the next authenticated call.

**Root cause.** The OAuth implicit grant issues no refresh token. `tokenExpiresAt`
(`ikigai.anilist.tokenExpiresAt`) is stored but **never consulted** for sign-out.

**Actual behaviour.** `restore()` validates against AniList's `Viewer` query; HTTP 400
is remapped to `unauthorized` and signs out. Transient failures keep the cached
profile and retry on a 2 s → 5 s → 15 s → 30 s → 60 s ladder.

**Planned fix.** None without abandoning the no-backend constraint
([ADR-006](DECISIONS.md#adr-006--implicit-grant-oauth-with-fragment-only-capture)).

---

## KI-013 — Rate limiting is per browser tab

**Severity:** Medium · **Status:** By design

**Symptoms.** With two tabs open, the app can exceed AniList's real ~90 req/min and
receive 429s.

**Root cause.** `AniListHttpClient`'s sliding window (`Queue<DateTime>`) and
`_blockedUntil` live in per-tab Dart memory.

**Workaround.** Close extra tabs; wait out the 429 (the UI says how long — 60 s
maximum auto-wait).

**Planned fix.** Not solvable client-side without shared storage (which would still
race). Mitigated by the deliberate 80 req/min budget leaving headroom.

---

## KI-014 — Hive is not multi-tab safe

**Severity:** Medium · **Status:** By design

**Symptoms.** Two tabs writing the GraphQL cache concurrently can interleave writes;
an opened box is also held fully in memory.

**Impact.** Cache corruption risk (recoverable — the cache is disposable) and memory
cost with many responses cached.

**Consequences enforced elsewhere.** Tokens and the only copy of user data are
deliberately **never** stored in Hive, and `openGqlStorage()` falls back to an
in-memory store if the box cannot be opened.

---

## KI-015 — No offline write queue

**Severity:** Medium · **Status:** Open

**Symptoms.**
- A tap in the **last 500 ms** before the tab closes is silently lost — the debounce
  timer is cancelled in `ref.onDispose` with no final flush.
- There is no outbox, no retry-on-reconnect, no background sync worker.
- No service worker, so a cold offline load fails entirely
  ([KI-022](#ki-022--no-service-worker)).

**Root cause.** Writes go straight to `SharedPreferences`; there is no queue layer.

**Workaround.** Local edits are otherwise persisted immediately, so only the final
debounce window is at risk.

**Planned fix.** Drain pending timers on `visibilitychange`/`pagehide`.

---

## KI-016 — AniList import and sync limits

**Severity:** Low · **Status:** By design

Deliberate restrictions ([ADR-010](DECISIONS.md#adr-010--local-first-tracking-with-add-only-import)):

- **Import never overwrites or deletes** local entries, and never removes titles that
  exist only locally — a locally deleted title returns on the next import.
- **A local edit made while a title's AniList entry cannot be read is not synced.**
  Nothing is sent on a guess.
- **Local deletions are never pushed** to AniList (the `MediaList` entry id may not be
  available).
- **Sync lives outside `TrackingRepository`** — in `OptimisticEntries` — so the
  repository interface does not express the full behaviour.

---

## KI-017 — Web is the only platform

**Severity:** Medium · **Status:** By design

**Symptoms.** `flutter build apk` / `ipa` fail — no `android/` or `ios/` directories
exist. `.metadata` records migrations for `root` and `web` only.

**Impact.** Scope limitation, not a defect. See
[DEPLOYMENT.md](DEPLOYMENT.md#android-build-not-currently-possible) for what scaffolding
would involve — including a non-trivial OAuth redirect story for native.

---

## KI-018 — CI does not pin Flutter

**Severity:** Low · **Status:** Needs decision

**Symptoms.** The same commit can build with a different Flutter version over time.

**Root cause.** `subosito/flutter-action@v2` with `channel: stable`, no
`flutter-version`. Locally the project is on 3.47.9 / Dart 3.13.7.

**Impact.** Non-reproducible builds; a breaking Flutter release can take CI down with
no repository change.

**Planned fix.** Pin `flutter-version` if this ever bites — one line, one quarterly
bump. See [ADR-011](DECISIONS.md#adr-011--ci-tracks-flutter-stable-unpinned).

---

## KI-019 — No custom lints or format check

**Severity:** Low · **Status:** Open

**Symptoms.** `analysis_options.yaml` is the stock Flutter template: it includes
`package:flutter_lints/flutter.yaml` and its `rules:` block contains only commented
examples. `dart format --set-exit-if-changed` does not run in CI.

**Impact.** Style drift is possible; only stock `flutter_lints` findings are caught.

**Planned fix.** Enable a small set of project-specific rules and a format gate.

---

## KI-020 — Unused logo asset

**Severity:** Low · **Status:** Open

**Symptoms.** `assets/images/app_logo.svg` is declared in `pubspec.yaml` under
`flutter: assets:` but is **never imported anywhere in `lib/`**.

**Root cause.** The in-app logo is `AppLogo`, a `CustomPainter`
(`_StillWaterPainter`) that draws the mark as vectors at runtime. (Note:
`lib/ui/components/app_logo.dart` *is* imported — that is the widget, not the asset.)

**Impact.** ~3 KB of dead bundle weight and mild confusion.

**Planned fix.** Remove the asset entry and file, or use the SVG somewhere.

---

## KI-021 — Single TODO

**Severity:** Low · **Status:** Open

The only `TODO`/`FIXME`/`XXX`/`HACK` marker in `lib/`:

```
lib/ui/screens/home_screen.dart:387
  // TODO: apply rotate strength 1.10 once the parameter name is
  // confirmed from CarouselEffect.rotate's signature.

  effect: const CarouselEffect.rotate(),
```

**Impact.** Cosmetic — the home carousel uses the default rotate strength instead of
1.10. Blocked on confirming the parameter name in `flutter_carousel_widget` 4.0.1.

---

## KI-022 — No service worker

**Severity:** Low · **Status:** Open

**Symptoms.** `manifest.json` makes the app installable, but there is no service
worker, so a cold load with no network fails.

**Impact.** PWA installability without offline capability — potentially misleading.

**Planned fix.** Add a service worker (carefully: Flutter web bundles are large) or
document the app as online-only.

---

## KI-023 — Production uses the fallback OAuth client

**Severity:** Medium · **Status:** Needs decision

**Symptoms.** The deployed Pages site signs in with the hardcoded public client id
`53659` from `app_config.dart`.

**Root cause.** `.github/workflows/deploy-web.yml` declares **no** `env:`, no
`secrets.*`, and no `--dart-define`.

**Impact.** Anyone can use that client id; the registered redirect URL is shared with
whatever else uses it. Not a secret leak (implicit grant has no secret), but
production login is coupled to a public identifier the project may not control.

**Planned fix.** Add `--dart-define=ANILIST_CLIENT_ID=${{ vars.ANILIST_CLIENT_ID }}`
to the build step and set the repository variable.

---

## KI-024 — Accessibility is not verified

**Severity:** Medium · **Status:** Open

**What exists:** explicit chip label colours for dark-mode contrast, light-mode
`StatusBadge` lightness adjustment, `Semantics` on `AnimatedToggle`, tooltips on
icon-only buttons, cursor feedback, `ColorScheme.fromSeed` contrast for all accents,
and reduced-motion support for the profile banner.

**What does not exist:**
- **No automated accessibility tests** (there are no tests at all —
  [KI-001](#ki-001--no-tracked-tests)).
- **No colour-contrast audit** — the 4.5:1 figure in `app_theme.dart` is a code comment
  about one chip style, not a measured audit.
- **`disableAnimations` is not honoured** by page fades, hover lifts, `FadeSlideIn`,
  shimmer, or the sidebar animation.
- **No focus-trap or Escape-to-dismiss verification** for dialogs and sheets.
- **No localisation** — all copy is hard-coded English.

---

## How to report a new issue

1. **Search this file** and [GRAPHQL_MIGRATION.md — Known limitations](GRAPHQL_MIGRATION.md#known-limitations)
   first.
2. Open an issue with, at minimum:
   - steps to reproduce (numbered, from a clean load),
   - expected vs actual,
   - environment: browser + OS, signed-in or guest, local or deployed site,
   - console output,
   - screenshots for anything visual.
3. If it is a **limitation by design** rather than a bug, say so — it will be moved to
   the appropriate status (`By design`) rather than closed.
4. Once understood, add it here with an ID, severity, root cause, workaround, and
   status.

**Security issues: do not open a public issue.** Contact the maintainer directly.

---

## Related documents

- Contribution standards → [CONTRIBUTING.md](../CONTRIBUTING.md)
- Decision records behind many of these → [DECISIONS.md](DECISIONS.md)
- Migration limits → [GRAPHQL_MIGRATION.md](GRAPHQL_MIGRATION.md)
- Testing gap → [TESTING.md](TESTING.md)
- CI gap → [TESTING.md](TESTING.md#ci-gap) and [DEPLOYMENT.md](DEPLOYMENT.md#cicd-pipeline)
