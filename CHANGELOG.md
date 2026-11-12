# Changelog

All notable changes to Ikigai, derived from the actual git history.

## How this project versions

| Fact | Value |
| --- | --- |
| `pubspec.yaml` version | **`1.0.0+1`** (name `1.0.0`, build number `1`) |
| Git tags | **None** — no formal releases have been cut |
| Repository | <https://github.com/sleepy-shan/Ikigai-Project> |
| History | 71 commits · 33 merged PRs · 2026-10-10 → 2026-11-03 |

Because no tags exist, entries below are grouped by **date milestone** rather than by
invented semantic-version releases. The first tagged version is still ahead — see the
[Release checklist](docs/DEPLOYMENT.md#release-checklist).

Types used: **Added** · **Changed** · **Fixed** · **Removed** · **Documentation** ·
**Breaking** (developer-facing).

---

## [Unreleased]

### Documentation

- **Added** the full documentation set: `README.md`, `CHANGELOG.md`,
  `CONTRIBUTING.md`, `LICENSE`, and 13 documents under `docs/` covering architecture,
  features, tech stack, storage, API, state management, UI guidelines, setup,
  testing, deployment, decisions, and known issues.
- **Added** `docs/GRAPHQL_MIGRATION.md` rewritten from a pre-implementation *blueprint*
  into an accurate implementation record that separates shipped work from remaining
  work.
- **Added** `docs/DECISIONS.md` (ADR-001 … ADR-012) recording technical trade-offs
  with alternatives and consequences.
- **Added** `docs/KNOWN_ISSUES.md` registering open bugs, limitations, and scope gaps.
- **Added** `LICENSE` — MIT, copyright Shan (sleepy-shan). *No licence file had ever
  existed in this repository.*

---

## 2026-11-03 — Search v3 and home card redesign

### Added

- Redesigned search screen layout (#32, `feature/v3-search-design`).
- Redesigned the cards under the home screen (#33, `feature/v2-home-design`).

---

## 2026-10-31 → 2026-10-30 — Navigation polish and search design passes

### Added

- Sidebar animation in the navigation shell (#31, `feature/navigation-components-sidebar`).
- Search screen redesign, second pass (#29 `feature/v1-search-design`,
  #30 `feature/v2-search-design`).

### Fixed

- Minor issues from the first search pass (#30).

---

## 2026-10-29 — Calendar redesign, anime/manga screens, test removal

### Added

- Redesigned calendar screen (#28, `feature/v1-calendar-design`).
- Redesigned anime/manga (browse) screen (#25, `feature/v1-anime-manga-design`).

### Fixed

- Anime and manga screen issues (#25).
- Deployment problem (#26).
- Dart package bug (#24, `bugfix/v1-dart-package`).

### Removed

- **BREAKING (developer)** — the `test/` directory was removed from version control
  and added to `.gitignore` (#27, `chore/ignore-test-folder`, `0a4be39`).
  **20 test files / 2,590 lines deleted**, and `flutter test` was commented out of CI.
  The suite had been present since the initial MVP. Recoverable with
  `git checkout 0a4be39^ -- test/`. See [docs/TESTING.md](docs/TESTING.md).

---

## 2026-10-27 → 2026-10-28 — Navigation and home redesign

### Added

- Redesigned home screen (#23, `feature/v1-home-design`).
- New navigation components and design (#22, `feature/navigation-components`).

---

## 2026-10-26 — AniList fetch and session fixes

### Fixed

- Auth session not being registered (#21, `bugfix/v5-anilist-auth`).
- Profile data not fetching from AniList (#20, `bugfix/v3-anilist-fetch`).
- AniList data fetching bugs (#19 `bugfix/v2-anilist-fetch`,
  #18 `bugfix/v1-anilist-fetch`).

---

## 2026-10-19 — AniList data retrieval

### Fixed

- AniList data retrieval problems (#17, `bugfix/anilist-retrieve-data`).

### Removed

- **BREAKING (docs)** — `README.md` was deleted from the repository (`7ad00c0`,
  `bugfix-anilist-retrieving-data`). It contained the original feature matrix, run
  instructions, and AniList login guide. Restored in **[Unreleased]**.

---

## 2026-10-17 — Profile and AniList login

### Added

- Profile feature enhancements (#13, `feature/profile-ui-enhancement`).

### Fixed

- Profile section bug (#15, `bugfix/profile`).
- Profile list UI (#16, `bugfix/profile-list`).
- Profile UI refinements (#14).
- AniList login bugs (#11 `bugfix/anilist-login`, #12 refix).

---

## 2026-10-13 — Deployment, project rename, authentication

A concentrated day of deployment work: six of the day's ten PRs were about GitHub
Pages, white screens, or build output.

### Changed

- **BREAKING (developer)** — project renamed **Dartotsu → Ikigai**
  (#7, `refactor/project-name`). Persisted `SharedPreferences` keys gained an
  `ikigai.*` prefix; legacy `sandwich.*` keys are still read once for migration and
  never written.
- Reverted the previous Pages deployment approach (#6,
  `refactor/revert-changes-pages-deploy`).

### Fixed

- Deployment problems (#10, `bugfix/deployment-problem`).
- The white-screen bug (#9, `bugfix/white-screen`).
- Authentication bug (#5, `bugfix/authentication`).
- Base href updated in `index.html` for Pages (#4, `fix/pages-deploy`).

### Removed

- Committed build output removed from the repository (#8, `remove/deleted-build`).

---

## 2026-10-11 → 2026-10-12 — Initial UI and layout

### Added

- Redesigned layout (#3, `refactor/redesign-layout`).
- New name colour and logo treatment (#2, `refactor/redesign-ui`).

### Fixed

- Button functionality (#1, `bugfix/button-funtionality`).

---

## 2026-10-10 — Initial MVP

### Added

- **Flutter Web MVP** — *"`Initial Dartotsu Web app: Flutter web MVP with AniList,
  tracking, tests"`*:
  - AniList integration (browse, search, detail).
  - Local tracking (watchlist/reading list).
  - **A 20-file test suite (2,590 lines)** — later removed on 2026-10-29.
- Deep linking via the **path URL strategy**, filter query fixes, and responsive
  toolbars (`Fix deep linking (path URL strategy), filter queries, responsive
  toolbars`).

---

## Contributor summary

| Contributor | Commits |
| --- | --- |
| Shan / sleepy-shan (`sa.galang02@gmail.com`, `sa.galangs02@gmail.com`) | 69 |
| Dartotsu Dev (`dev@example.com`) | 2 |

Branch conventions observed across the 33 merged PRs: `feature/*`, `bugfix/*`,
`chore/*`, `refactor/*`, `revert/*` — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Known gaps carried forward

Recorded in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md), not repeated here:

- No tracked tests; `flutter test` disabled in CI.
- Flutter version unpinned in CI; no custom lints; no format check.
- Calendar reminders store a marker but deliver no notification.
- Accent colour is applied but has no settings UI.
- Web is the only scaffolded platform.

---

**Metadata provided by [AniList](https://anilist.co/).**
