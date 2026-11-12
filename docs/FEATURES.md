# Features

This document describes **what Ikigai actually does today**. Each feature lists its
purpose, the expected behaviour, the user workflow, the screens and components
involved, and an explicit status.

## Status legend

| Status | Meaning |
| --- | --- |
| **Completed** | Implemented, reachable in the running app, and exercised in normal use. |
| **Partial** | Implemented but with a known limitation, or a sub-part of the feature is missing. |
| **In progress** | Actively being worked on; do not rely on it. |
| **Planned** | Designed or sketched but not implemented. Never presented as working. |

Anything recorded as **Planned** or **Partial** is also tracked with its impact in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md). Design rationale lives in
[DECISIONS.md](DECISIONS.md).

---

## 1. Home

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Give an immediate, glanceable starting point for discovery. |
| **Route** | `/` |
| **Screen** | `lib/ui/screens/home_screen.dart` |

**Expected behaviour.** On first paint the page shows a hero block, a full-width
carousel of featured titles, and a series of horizontal rails — trending anime,
trending manga, popular this season, airing now, all-time popular, upcoming, top
rated, top completed, and new chapters. Each rail renders poster cards and can be
scrolled horizontally. Images that fail to load fall back to a tinted placeholder
rather than a broken-image glyph.

**Workflow.** Open the app → skim rails → tap a card → land on the media detail
page → press back and return to the same scroll position.

**Components.** `Rails`/`SectionHeader` (horizontal rail + hover action pill),
`PosterCard`, `AppLogo`, `AppFooter`, `flutter_carousel_widget` for the hero.

**Notes.**
- Rails are served by `mediaRailProvider`, which reuses the shared
  `animePageStream` SWR helper (10-minute TTL for browse, 2 minutes when a search
  term is present).
- There is one cosmetic `TODO` in this file (carousel rotate strength); it does not
  affect behaviour.

---

## 2. Discover (Browse)

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Explore the whole catalogue with sort presets and structured filters. |
| **Routes** | `/anime`, `/manga` |
| **Screen** | `lib/ui/screens/browse_screen.dart` |

**Expected behaviour.** A responsive poster grid of `BrowseCard`s with a filter
sidebar, a sort menu, and a pagination bar. Loading shows skeleton cards rather
than a spinner. Presets — Airing, Trending, Popular, Top rated, Upcoming, Top
completed — apply a canned sort/status combination in one tap.

**Workflow.** Choose Anime or Manga from the nav → apply a preset or open filters →
adjust status/genre/format/season/year/source/country/min-score/adult → results
update → page through → open a title → return and keep the same page.

**Filter application model.**
- **Desktop (≥ 1000 px):** the filter form sits in a sidebar and applies live.
- **Mobile (< 1000 px):** filters open as a draft sheet; nothing is requested until
  the user taps **Show results**.

**Components.** `BrowseFilterForm`, `BrowseCard`, `MediaGrid`, `PaginationBar`,
`StateView` helpers (`posterColumns` / `browsePosterColumns`), skeleton placeholders.

**State.** `browseControllerProvider(MediaType)` — deliberately **not** `autoDispose`,
so navigating into a title and back preserves the applied filters and current page.
A monotonic request id discards out-of-order responses.

---

## 3. Search

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Fast lookup by title plus entity search across studios, staff, and characters. |
| **Route** | `/search` (also reachable with `?q=…`) |
| **Screen** | `lib/ui/screens/search_screen.dart` |

**Expected behaviour.** Five tabs — **Anime, Manga, Studios, Staff, Characters** —
each with its own query text, result set, page, and pagination. Typing debounces at
**400 ms** per tab (clearing the field fires immediately). Results support grid/list
layouts, per-tab sorting, and removable active-filter chips. Infinite scroll tops up
automatically when the signature of the current result set changes.

**Workflow.** Press `/` or `Ctrl/Cmd+K` anywhere (or click the top-bar lens) → type →
switch tabs without losing the other tabs' results → open filters → apply → see a live
result count on the Apply button → scroll for more pages.

**Components.** `LensSearchField`, `SearchFiltersEditor` (panel on desktop, bottom
sheet on phone), `SearchFilterFields` primitives, `MediaGrid`, `PaginationBar`.

**State.** `searchControllerProvider` — one instance drives the header field, tabs,
filter chips, results, and the load-more footer. Per-tab debounce timers, monotonic
request ids, and dedupe-on-append (AniList rankings shift between pages) all live
here. `_params` remembers the query/sort/filters a result page was fetched with, so
paging never mixes criteria.

**Filter coverage.** Anime exposes 8 criteria, Manga 5 (manga drops season, source,
and minimum score; a manga season-year becomes a start-date range).

---

## 4. Calendar & schedule

| | |
| --- | --- |
| **Status** | Completed (reminders are Partial) |
| **Purpose** | Show what airs and what publishes, week by week, in your timezone. |
| **Route** | `/calendar` (also `?tab=anime` / `?tab=manga`) |
| **Screen** | `lib/ui/screens/calendar_screen.dart` |

**Expected behaviour.** Two tabs:

- **Anime** — weekly airing schedule driven by AniList's airing-schedule query,
  showing episode number, countdown/air time, and streaming platform chip.
- **Manga** — releases whose start date falls inside the selected week, sorted by
  date then popularity.

Week navigation (previous / this / next), a day strip, and a live-season pill are
present. The timezone picker offers device time, UTC, JST, SGT, and IST and
**persists** across sessions. Sorting can be by air time, popularity, or countdown.

**Workflow.** Open Calendar → pick a timezone → step weeks → tap a day to focus it →
sort → open a title.

**Components.** `_DayStrip`, `_DayTile`, `_ReleaseCard`, `_PlatformChip`,
`_WeekBadge`, `_SortSegment`, `_ZonePicker`, shimmer skeletons, inline empty and
error slivers.

**State.** `calendarControllerProvider` — **two independent status machines** (anime
and manga) so one failing load does not blank the other, each guarded by its own
monotonic id. Previous items stay visible while reloading so the list never flashes
empty. Week navigation is throttled while a load is in flight.

**Reminders — Partial.** Each release card has a bell that toggles a persisted set of
media ids (`ikigai.calendar.reminders`). **The marker is stored but no notification
is ever delivered** — there is no scheduling or delivery mechanism. Treat it as a
"save for later" flag, not an alarm.

---

## 5. Media detail

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | The single destination for everything about one title, including tracking. |
| **Route** | `/media/:type/:id` |
| **Screen** | `lib/ui/screens/media_detail_screen.dart` |

**Expected behaviour.** Banner, title, score, format, status, season, genres,
synopsis, relations, recommendations, characters, staff, and studio links. Opening a
title records it in history. The tracking card lets the user increment progress, set
status, and set score.

**Workflow.** Open a title → read details → tap **+1** on progress → see the value
optimistically → the change syncs to AniList in the background if signed in → related
titles are one tap away.

**Components.** `ProgressEditor`, `StatusBadge`, `SectionHeader`, rails for
relations/recommendations, person links to `/staff/:id`, `/character/:id`,
`/studio/:id`.

**State.** `mediaDetailProvider` (SWR, 30-minute TTL), `displayEntryProvider`
(optimistic overlay over the server entry), `historyControllerProvider.record()`,
`trackedEntryProvider`.

**Sync feedback.** While an edit is pending, the tracking card shows *"syncing to
AniList…"*. Failures surface as a snackbar from the app shell, and the local value
rolls back.

---

## 6. Tracking & My Lists

| | |
| --- | --- |
| **Status** | Completed (sync has documented limits) |
| **Purpose** | Personal watchlist/reading list that works signed-out and improves when signed-in. |
| **Route** | `/lists` |
| **Screen** | `lib/ui/screens/my_lists_screen.dart` |

**Expected behaviour.** The user's titles grouped by list status with filter, sort,
and per-section counts. Adding, removing, changing status, editing progress, and
scoring all work. A cloud button (**Import from AniList**) copies anime and manga
lists from AniList into the local list when signed in.

**Workflow.** Open a title → add to list → change status to Completed → progress fills
to the total → open My Lists → filter to Completed → sort → import from AniList to
backfill.

**Local business rules** (single source of truth, `LocalTrackingRepository`):
- Progress reaching a known total ⇒ status becomes `Completed`.
- Progress dropping below the total of a completed entry ⇒ back to `Watching`.
- Progress > 0 on a `Planning` entry ⇒ `Watching`.
- Score is clamped to 0–10; progress is clamped to 0–total.
- `startedAt` / `completedAt` timestamps are maintained.

**AniList mirroring — limits.**
- Signed-out users keep everything in browser storage; nothing is sent anywhere.
- Signed-in edits are mirrored with **absolute** values (never `+1`), debounced at
  **500 ms**, so ten quick taps cost one request.
- The server entry is awaited **before** the first edit, so a local progress of 1 can
  never overwrite a real server progress of 11.
- Import **only adds missing titles** — it never overwrites or deletes local entries.
- If a title's AniList entry cannot be read, the edit is **not** sent rather than
  guessed.

**Components.** `ProgressEditor`, `StatusBadge`, `MediaGrid`, filter/sort controls,
import button.

**State.** `myListsControllerProvider` (subscribed to the repository stream),
`optimisticEntriesProvider` (the overlay), `displayEntryProvider`,
`entrySyncErrorProvider`.

---

## 7. History

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Resume where you left off. |
| **Route** | `/history` |
| **Screen** | `lib/ui/screens/history_screen.dart` |

**Expected behaviour.** A chronological list of recently opened titles, newest first,
one row per title (re-opening moves it to the top), capped at **50** entries. Rows can
be removed individually or cleared entirely. Stored purely locally.

**Workflow.** Open any title → it appears in History → come back later → resume.

**State.** `historyControllerProvider` seeded from `LocalHistoryRepository.readAll()`.
The detail screen calls `record()` on open; the history screen calls `remove()` /
`clear()`.

---

## 8. User profile & authentication

### 8a. AniList sign-in

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Optionally link an AniList account so list changes sync and profile data loads. |

**Workflow.** Click the account button → **Continue with AniList** → the browser
navigates to AniList's OAuth authorize URL in the **same tab** (required so the
fragment redirect lands back on the app) → AniList redirects back with
`#access_token=…` → the app captures it, stores it, immediately scrubs the fragment
from the address bar, and validates it against AniList's `Viewer` query.

**Safety properties.**
- A redirect is only accepted if a sign-in was started within the **last 30 minutes**,
  and the "login started" marker is consumed either way (one sign-in ⇒ one redirect).
- Only the URL **fragment** is read; a `?access_token=` query parameter is
  deliberately ignored, which prevents an attacker forcing a victim into their account.
- Tokens live in browser `localStorage` only and are never logged.
- If the client ID is missing, the sign-in button explains the problem instead of
  failing silently.

**Guest mode is first-class.** No route is guarded; everything except AniList mirroring
and profile data works signed out.

### 8b. Profile

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Summarise the linked AniList account. |
| **Route** | `/profile`, `/profile/list/:section` |

**Expected behaviour.** Custom banner, avatar, and name, then panels for statistics
(totals, units, time watched, mean score), status breakdown linking into per-section
lists, top genres, recent activity, and notifications. Profile data is snapshotted to
local storage so the page paints instantly on reload and revalidates in the
background.

**Components.** `ProfileBannerView` + `ProfileBannerPicker`, `ProfileStatsPanel`,
`ProfileOverviewPanel`, `ProfileGenresPanel`, `ProfileActivityPanel`,
`ProfileNotificationsPanel`.

### 8c. Notifications

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Surface AniList notifications for the signed-in user. |
| **Route** | `/notifications` |

Fetches `AIRING`, `RELATED_MEDIA_ADDITION`, and `MEDIA_DATA_CHANGE` notifications.
Requires a token; signed-out users see the empty/signed-out state. Manual refresh via
`ref.invalidate`.

---

## 9. Profile banner customisation

| | |
| --- | --- |
| **Status** | Completed |
| **Purpose** | Let the user personalise the profile header without needing an AniList banner. |
| **Component** | `lib/ui/components/profile_banner.dart`, `profile_banner_picker.dart` |

Nine presets — `auto` (the AniList banner, falling back to a calm aurora),
`aurora`, `sakura`, `sunset`, `ocean`, `neon`, `starfield`, `gradient`, `grid`. The
eight designed presets are `CustomPainter` animations looping over 24 s. Animations
stop when the OS reports reduced motion. The choice persists under
`ikigai.profile.banner` and is a **website-only preference**, unrelated to AniList.

---

## 10. Settings & appearance

| | |
| --- | --- |
| **Status** | Completed (accent colour selection is Partial) |
| **Route** | `/settings` redirects to `/` — settings is a dialog, not a page |
| **Screen** | `lib/ui/screens/settings_dialog.dart` |

**Implemented.**
- **Theme mode** — System / Light / Dark, persisted.
- **Sidebar collapse** — desktop sidebar toggles between 232 px and 72 px, animated
  over 600 ms; the choice persists and defaults to collapsed.
- **Accent colour** — six seeds (Lagoon, Moss, Dusk, Sand, Slate, Sakura) are applied
  at runtime, but **the settings dialog no longer exposes a picker** (it was removed;
  the dialog states "Theme mode only"). The provider and persistence still work, so
  this is a UI gap rather than a missing capability.

**Accent — Partial.** `AccentController.setAccent` is never called from the UI today.

---

## 11. Navigation & responsive shell

| | |
| --- | --- |
| **Status** | Completed |
| **Component** | `lib/ui/layout/app_shell.dart`, `lib/ui/router/app_router.dart` |

- **Bottom navigation** (phones): Home, Anime, Manga, Calendar, Watchlist.
- **Sidebar** (desktop, ≥ 1000 px): adds History, Settings, and a collapse toggle.
- **Top bar** (64 px) embeds the search lens at widths ≥ 600 px, hidden on `/search`.
- **Keyboard:** `/` and `Ctrl/Cmd+K` open search.
- **Aurora background** custom-painted behind every page; page transitions cross-fade
  over 260 ms.
- **404:** unknown paths render a dedicated error page via `GoRouter.errorBuilder`.
- Deep links are shareable — `?rail=`, `?tab=`, and `?q=` are read back into state on
  load.

---

## Feature status summary

| # | Feature | Status |
| --- | --- | --- |
| 1 | Home discovery rails & carousel | Completed |
| 2 | Browse with presets, filters, pagination | Completed |
| 3 | Multi-tab search with debouncing & filters | Completed |
| 4 | Calendar (anime airing + manga releases) | Completed |
| 4b | Calendar reminders | **Partial** — marker stored, no delivery |
| 5 | Media detail with relations & tracking | Completed |
| 6 | My Lists + local tracking rules | Completed |
| 6b | AniList list mirroring | **Partial** — documented sync limits |
| 6c | Import from AniList | **Partial** — add-only, never overwrites |
| 7 | History (local, 50 entries) | Completed |
| 8a | AniList OAuth sign-in | Completed |
| 8b | Profile statistics | Completed |
| 8c | Notifications | Completed |
| 9 | Animated profile banner presets | Completed |
| 10 | Theme mode / sidebar persistence | Completed |
| 10b | Accent colour picker | **Partial** — applied, no UI to change it |
| 11 | Responsive shell, shortcuts, deep links | Completed |
| — | Android / iOS / desktop builds | **Planned** — no platform targets scaffolded |
| — | Push/email notification delivery | **Planned** |
| — | Offline write queue with background sync | **Planned** |

---

## Explicitly not claimed

To keep this document honest about the difference between **implemented**, **partial**,
and **proposed**:

- **No tests are currently tracked** — the `test/` directory is git-ignored and was
  removed from version control. See [TESTING.md](TESTING.md).
- **`filters_sheet.dart` is dead code** — `FilterSheet` is not referenced anywhere;
  it was superseded by `SearchFiltersEditor` and `BrowseFilterForm`.
- **`StateView` is defined but never instantiated** — screens render `LoadStatus`
  directly using `SliverLoading` / `SliverError` / `SliverEmpty`.
- **`animePageProvider` and `animeByIdProvider` are declared but unused by the UI**;
  the home rails reach the same stream through `mediaRailProvider`.
- **`SwrResult.isRefreshing` / `fromCache` / `refreshError` are populated but not yet
  consumed** by any widget — the subtle refresh indicators they were designed for are
  not shown.
- **No offline-first write queue exists.** Local edits are persisted immediately, but
  a tap made in the final moments before the tab closes is not flushed.
