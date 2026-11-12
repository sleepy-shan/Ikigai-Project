# Ikigai

[![Deploy web to GitHub Pages](https://github.com/sleepy-shan/Ikigai-Project/actions/workflows/deploy-web.yml/badge.svg)](https://github.com/sleepy-shan/Ikigai-Project/actions/workflows/deploy-web.yml)

**Ikigai** is a web application for discovering, browsing, and tracking anime and manga.
It is built with Flutter and reads its metadata from the public
[AniList GraphQL API](https://docs.anilist.co/), with an optional AniList sign-in that
lets you mirror your list changes back to your AniList account.

> **Status:** the app runs and deploys as a Flutter Web single-page application.
> It is currently a **web-only** project — no Android, iOS, or desktop targets are
> scaffolded yet. See [Known Issues](docs/KNOWN_ISSUES.md) for current limitations.

---

## Table of contents

- [Screenshots](#screenshots)
- [Key features](#key-features)
- [Tech stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Setup](#setup)
- [Quick start](#quick-start)
- [Project structure](#project-structure)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Screenshots

> **To be added.** Capture these after running the app locally (see
> [Quick start](#quick-start)) and drop them into `docs/screenshots/`.
> Suggested shots: Home, Browse, Search with filters open, Media detail,
> Calendar, My Lists, Profile.

| Home | Browse |
| --- | --- |
| *pending* | *pending* |

| Search | Media detail |
| --- | --- |
| *pending* | *pending* |

---

## Key features

Everything below is **implemented and reachable in the running app** unless it is
explicitly marked otherwise. See [docs/FEATURES.md](docs/FEATURES.md) for the
full breakdown, including status per feature.

| Area | What you can do |
| --- | --- |
| **Home** | Hero banner, carousel, and horizontal rails for trending, seasonal, and top-rated titles. |
| **Discover** | Browse anime and manga as a paginated poster grid with sort presets (Popular, Trending, Top rated, Favourites, Newest, Updated, A–Z, Best match). |
| **Filters** | Filter by status, genre, format, season, year, source, country, minimum score, and adult content. Desktop applies filters live; mobile uses a draft sheet with a "Show results" action. |
| **Search** | Debounced search across five tabs — Anime, Manga, Studios, Staff, Characters — with per-tab pagination, sorting, and removable filter chips. |
| **Media detail** | Banner, score, status, synopsis, genres, relations, recommendations, characters, staff, and studio links. |
| **Tracking** | Add/remove titles, set status, edit progress and score. Works signed-out (stored locally) and signed-in (mirrored to AniList). |
| **My Lists** | Watchlist/reading list split by status, with filtering, sorting, counts, and an "Import from AniList" action. |
| **Calendar** | Weekly anime airing schedule and manga release calendar with timezone selection, reminders, sorting, and day navigation. |
| **History** | Recently opened titles, newest first, capped at 50 entries. |
| **Profile** | AniList statistics — totals, mean score, status breakdown, top genres, activity, and notifications. Customisable animated profile banner. |
| **Settings** | Theme mode (system/light/dark), accent colour, and sidebar collapse state — all persisted. |
| **Auth** | Optional AniList OAuth sign-in. The app is fully usable as a guest. |

**Not implemented** (planned or deliberately out of scope) is tracked in
[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) rather than presented here as working.

---

## Tech stack

| Layer | Choice |
| --- | --- |
| Framework | Flutter (stable channel), Dart SDK `^3.13.5` |
| Target platform | Web only (`flutter build web`) |
| State management | Riverpod 3 (`flutter_riverpod ^3.4.3`) — hand-written providers, no codegen |
| Navigation | `go_router ^18.0.2` with a single `ShellRoute` |
| API | AniList GraphQL (`graphql_flutter ^5.2.0`) + a hand-written `http` client layer |
| Local storage | `shared_preferences` (user data/settings) + Hive-backed GraphQL cache (IndexedDB on web) |
| Code generation | `freezed` + `json_serializable` via `build_runner` |
| Lints | `flutter_lints ^6.0.0` |
| CI/CD | GitHub Actions → GitHub Pages |

Rationale for each choice lives in [docs/TECH_STACK.md](docs/TECH_STACK.md).

---

## Prerequisites

- **Flutter SDK, stable channel** — must satisfy Dart SDK `^3.13.5`.
  Check with `flutter --version`. Install via <https://docs.flutter.dev/get-started/install>.
- **A browser** — Chrome/Chromium is the primary target; the app uses the path URL
  strategy, so it also works from a sub-path deployment.
- **Git**.
- **AniList account** — only needed if you want to test sign-in. The app runs fine
  without one.
- **AniList API client** — only needed for sign-in. Create one at
  <https://anilist.co/settings/developer> (see [Setup](#setup)).

> **No Android Studio / Xcode / platform toolchains are required** — this repository
> contains no `android/`, `ios/`, `windows/`, `linux/`, or `macos/` directories.

---

## Installation

```bash
git clone https://github.com/sleepy-shan/Ikigai-Project.git
cd Ikigai-Project
```

Then fetch dependencies and generate code — **the code generation step is mandatory**:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

`*.g.dart` and `*.freezed.dart` are intentionally git-ignored, so a fresh clone will
**not compile** until `build_runner` has run. The same step runs automatically in CI
and in the VS Code `flutter: optimized-prep` task.

---

## Setup

### 1. Confirm your toolchain

```bash
flutter --version   # Dart SDK must report ^3.13.5 or newer
flutter doctor      # web device support must be available
```

### 2. (Optional) Configure AniList sign-in

Sign-in uses the AniList **OAuth 2.0 implicit grant**. Without a client ID the app
still runs, but the "Continue with AniList" button is disabled.

1. Create an application at <https://anilist.co/settings/developer>.
2. Set the **Redirect URL** to wherever the app is served, e.g.
   `http://localhost:PORT/` for local development and your Pages URL in production.
3. Pass the client ID at build/run time:

```bash
flutter run -d chrome --dart-define=ANILIST_CLIENT_ID=<your-client-id>
```

If `ANILIST_CLIENT_ID` is not supplied, the project falls back to a public client ID
(`53659`) that is baked into `lib/core/config/app_config.dart`. Use your own client
ID for anything beyond local experimentation.

The access token is stored in browser `localStorage` only — it is never sent
anywhere except to `https://graphql.anilist.co`, and the URL fragment is scrubbed
from the address bar immediately after the redirect is captured.

### 3. (Optional) VS Code

`.vscode/` is tracked and contains a **Flutter (Debug)** launch configuration whose
pre-launch task runs `flutter clean && flutter pub get && dart run build_runner build
--delete-conflicting-outputs && flutter analyze`. The settings are tuned for a
low-memory machine (reduced file watching, no auto `pub get`).

---

## Quick start

```bash
# 1. Dependencies + generated code
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 2. Run in Chrome with hot reload
flutter run -d chrome

# 3. Or build a release bundle
flutter build web --release --base-href="/Ikigai-Project/"
```

Then open the printed `localhost` URL. Useful commands:

| Command | Purpose |
| --- | --- |
| `flutter run -d chrome` | Debug run with hot reload/restart |
| `flutter analyze` | Static analysis (the CI gate) |
| `flutter test` | Run tests — **currently no tests are tracked** (see [docs/TESTING.md](docs/TESTING.md)) |
| `dart run build_runner build --delete-conflicting-outputs` | Regenerate `*.g.dart` / `*.freezed.dart` |
| `flutter build web --release` | Production web bundle into `build/web/` |

---

## Project structure

```
lib/
├── main.dart              # Startup: prefs, GraphQL storage, OAuth fragment capture, runApp
├── app.dart               # IkigaiApp — MaterialApp.router, theme, accent
├── core/                  # Configuration, design tokens, theming, cross-cutting utils
│   ├── config/            #   AppConfig: endpoint, OAuth client, environment defines
│   ├── theme/             #   Tokens, ThemeData, motion, scroll physics, breakpoints
│   └── utils/             #   AppException, formatters, debouncer, external links, URL cleaner
├── data/                  # Everything that talks to storage or the network
│   ├── anilist/           #   Hand-written AniList HTTP client, raw query documents, mapper
│   ├── graphql/           #   graphql_flutter wiring: links, rate gate, cache bootstrap, models
│   ├── models/            #   Plain Dart domain models (hand-written JSON)
│   └── repositories/      #   Auth, Media, Tracking, History repositories
├── state/                 # Riverpod providers and Notifier controllers (41 providers)
└── ui/
    ├── components/        # 23 reusable widgets
    ├── layout/            # AppShell: sidebar/bottom-nav, top bar, keyboard shortcuts
    ├── router/            # GoRouter route table
    └── screens/           # 13 screen files (see FEATURES.md)
```

Full layering, dependency rules, and data flow are documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Documentation

| Question | Document |
| --- | --- |
| What is this project? | **README.md** (you are here) |
| What changed recently? | [CHANGELOG.md](CHANGELOG.md) |
| How do I contribute? | [CONTRIBUTING.md](CONTRIBUTING.md) |
| How is the code organised? | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| What can the app do? | [docs/FEATURES.md](docs/FEATURES.md) |
| What technologies are used and why? | [docs/TECH_STACK.md](docs/TECH_STACK.md) |
| Where is data stored? | [docs/DATABASE_AND_STORAGE.md](docs/DATABASE_AND_STORAGE.md) |
| How does the API work? | [docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md) |
| How does state management work? | [docs/STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md) |
| How should the UI look? | [docs/UI_DESIGN_GUIDELINES.md](docs/UI_DESIGN_GUIDELINES.md) |
| How do I run the project? | [docs/SETUP_AND_DEVELOPMENT.md](docs/SETUP_AND_DEVELOPMENT.md) |
| How do I test the app? | [docs/TESTING.md](docs/TESTING.md) |
| How do I publish the app? | [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) |
| How was GraphQL implemented? | [docs/GRAPHQL_MIGRATION.md](docs/GRAPHQL_MIGRATION.md) |
| Why was X decided over Y? | [docs/DECISIONS.md](docs/DECISIONS.md) |
| What is broken right now? | [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) |

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Short version:

1. Branch from `main` using `feature/<name>`, `bugfix/<name>`, or `chore/<name>`.
2. Run `flutter analyze` — it must be clean before you push.
3. Regenerate code after touching any `@freezed` or `@JsonSerializable` model.
4. Open a PR with a clear description of what changed and how to test it.

---

## License

Licensed under the MIT License. See [LICENSE](LICENSE).

Copyright (c) Shan (sleepy-shan).

---

**Metadata provided by [AniList](https://anilist.co/).** Ikigai is not affiliated with
or endorsed by AniList.
