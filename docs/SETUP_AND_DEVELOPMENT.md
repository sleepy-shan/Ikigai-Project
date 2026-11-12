# Setup and development

Prepare a machine, get the app running, and know which commands to reach for.

## Contents

- [Prerequisites](#prerequisites)
- [Flutter SDK installation](#flutter-sdk-installation)
- [IDE setup](#ide-setup)
- [Project installation](#project-installation)
- [Environment variables and configuration](#environment-variables-and-configuration)
- [Running the application](#running-the-application)
- [Development commands](#development-commands)
- [Hot reload and debugging](#hot-reload-and-debugging)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Detail |
| --- | --- |
| **Flutter SDK** | Stable channel. Must satisfy Dart SDK **`^3.13.5`**. The project is developed on **Flutter 3.47.9 / Dart 3.13.7**. |
| **Browser** | Chrome/Chromium is the primary target. |
| **Git** | For cloning and branching. |
| **AniList account** | Optional — only to test sign-in. The app runs fully as a guest. |
| **AniList API client** | Optional — only for sign-in. Create at <https://anilist.co/settings/developer>. |

**Not required:** Android Studio, Xcode, Gradle, CocoaPods, or any platform toolchain.
This repository contains **no `android/`, `ios/`, `windows/`, `linux/`, or `macos/`
directories** — it is a web-only project (`.metadata` records migrations for `root`
and `web` only).

Verify with:

```bash
flutter --version    # Dart SDK must report ^3.13.5 or newer
flutter doctor       # web device support must be available
```

---

## Flutter SDK installation

1. Install via the official guide: <https://docs.flutter.dev/get-started/install>
2. Stay on the **stable** channel:

```bash
flutter channel stable
flutter upgrade
```

3. Confirm:

```bash
flutter doctor -v
```

Only the **Chrome** and **Web** entries need to be green. Anything about Android
toolchains, Xcode, or Visual Studio can be ignored for this project.

> **No version is pinned.** CI tracks `channel: stable` at run time, and
> `pubspec.yaml` only constrains the Dart SDK. If a Flutter release breaks the build,
> downgrade locally with `flutter version <x.y.z>` — this is a known trade-off
> recorded in [DECISIONS.md](DECISIONS.md).

---

## IDE setup

### VS Code (recommended — configuration is tracked)

`.vscode/` is committed with three files.

**`launch.json`** — one configuration:

| Name | Request | Mode | Pre-launch task |
| --- | --- | --- | --- |
| `Flutter (Debug)` | launch | debug | `flutter: optimized-prep` |

**`tasks.json`** — the pre-launch task runs the full cycle:

```bash
flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze
```

So pressing **F5** regenerates code and runs the analyzer before the app starts —
which is why a broken `build_runner` step surfaces as a failed launch rather than a
mystery compile error.

**`settings.json`** — tuned for a **low-memory container** (reduces analysis and file
watching so Flutter web runs do not freeze the UI):

```jsonc
"files.watcherExclude": { "**/build/**": true, "**/.dart_tool/**": true,
                          "**/.git/**": true, "**/pubspec.lock": true },
"search.exclude": { "**/build": true, "**/.dart_tool": true },
"files.exclude": { "**/.dart_tool": true },
"dart.analysisExcludedFolders": ["build"],
"dart.runPubGetOnPubspecChanges": "never",   // run pub get manually
"dart.previewFlutterUiGuides": false,
"dart.showDevTools": "never"
```

> Because auto `pub get` is disabled, **you must run `flutter pub get` yourself** after
> editing `pubspec.yaml`.

Extensions: **Dart** and **Flutter** (ms-dart.scala / dart-code.flutter).

### IntelliJ / Android Studio

Works fine with the Dart + Flutter plugins. No project-specific configuration exists
in the repo for these IDEs.

---

## Project installation

```bash
git clone https://github.com/sleepy-shan/Ikigai-Project.git
cd Ikigai-Project
```

Then **two** steps — the second one is mandatory:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Why `build_runner` is mandatory

`*.g.dart` and `*.freezed.dart` are **git-ignored** (`.gitignore` lines 51–53). They
are produced from `@freezed` / `@JsonSerializable` sources in:

- `lib/data/graphql/models/anime_media.dart`
- `lib/data/graphql/models/media_list_entry.dart`
- `lib/state/anime_providers.dart` (the `AnimePageArgs` args class)

**A fresh clone does not compile until this step has run.** This is the single most
common setup failure.

Codegen configuration lives in `build.yaml`:

```yaml
json_serializable:
  options:
    explicit_to_json: true   # nested freezed objects serialise recursively
    include_if_null: false   # omit nulls
```

Re-run codegen whenever you touch a `@freezed` class, a `@JsonSerializable` class, a
`part '*.g.dart'` / `part '*.freezed.dart'` directive, or `build.yaml`.

---

## Environment variables and configuration

There is exactly **one** compile-time configuration value.

| Define | Type | Default | Purpose |
| --- | --- | --- | --- |
| `ANILIST_CLIENT_ID` | `--dart-define` | `'53659'` (hardcoded public fallback) | AniList OAuth client id |

Source of truth: `lib/core/config/app_config.dart`

```dart
static const String aniListClientId =
    String.fromEnvironment('ANILIST_CLIENT_ID', defaultValue: '53659');
static bool get hasAnilistClient => anilistClientId.isNotEmpty;
```

**There are no other environment variables, feature flags, or API keys.**

### Getting a client id

1. Go to <https://anilist.co/settings/developer> → **Create New Client**.
2. Set the **Redirect URL** to where the app will be served:
   - Local: `http://localhost:<port>/` (any port works for the implicit grant when the
     browser returns to the same origin — match what you actually run)
   - Production: your GitHub Pages URL, e.g.
     `https://sleepy-shan.github.io/Ikigai-Project/`
3. Pass it at run/build time:

```bash
flutter run -d chrome --dart-define=ANILIST_CLIENT_ID=<your-client-id>
```

**Without it** the app runs normally, but the sign-in dialog explains that login is
unconfigured instead of failing silently.

> **Never commit a client secret.** The implicit grant uses no secret; only the public
> client id is ever needed.

### Other configuration that is *not* environment-driven

| Thing | Where it lives |
| --- | --- |
| GraphQL endpoint | `AppConfig.aniListEndpoint` |
| Rate limit / retry / timeouts | `AniListHttpClient` constructor defaults |
| Cache TTLs | `swr.dart`, `gql_catalog.dart`, `anime_providers.dart`, `media_providers.dart` |
| Storage keys | Constants in the owning repository/controller |
| Theme / accent / sidebar | Persisted in `localStorage`, changeable in-app |

---

## Running the application

```bash
# Basic — debug build with hot reload
flutter run -d chrome

# With your own AniList client
flutter run -d chrome --dart-define=ANILIST_CLIENT_ID=<your-client-id>

# List available devices
flutter devices
```

Then open the printed `localhost` URL. The app uses the **path URL strategy**, so deep
links like `/media/anime/123456` work from the app root without a `#`.

```bash
# Release bundle
flutter build web --release --base-href="/Ikigai-Project/"
```

Output goes to `build/web/`. See [DEPLOYMENT.md](DEPLOYMENT.md).

---

## Development commands

| Command | Purpose |
| --- | --- |
| `flutter pub get` | Fetch dependencies (**run manually** — auto-get is off in VS Code) |
| `dart run build_runner build --delete-conflicting-outputs` | Generate `*.g.dart` / `*.freezed.dart` |
| `flutter analyze` | Static analysis — **the CI gate**; must be clean |
| `flutter run -d chrome` | Debug run with hot reload/restart |
| `flutter run -d chrome --profile` / `--release` | Non-debug builds |
| `flutter test` | Run tests — **currently no tests are tracked** ([TESTING.md](TESTING.md)) |
| `flutter build web --release` | Production web bundle |
| `flutter clean` | Remove build artefacts (do this if output looks stale) |
| `flutter pub outdated` | Check for dependency updates |
| `flutter doctor` | Toolchain diagnostics |
| `git log --oneline -20` | Recent history |

### Recommended local loop

```bash
dart run build_runner build --delete-conflicting-outputs   # after model changes
flutter analyze                                             # before every push
flutter run -d chrome
```

---

## Hot reload and debugging

### Hot reload / restart

- **Hot reload (`r`)** — injects changed code, preserves state. Works for widget and
  most logic changes.
- **Hot restart (`R`)** — full re-run, state reset. Required after changes to
  `main()`, top-level initialisers, or anything that runs at startup.
- **Not reload-safe:** changes to `@freezed` models or `part` files — rerun
  `build_runner` first, or you will compile against stale generated code.

### Debugging in the browser

| Technique | How |
| --- | --- |
| Chrome DevTools | Right-click → Inspect; the Dart VM service is exposed for the running app |
| `debugPrint` / DevTools logging | `print` is linted (`avoid_print`); use `debugPrint` or `dart:developer log` — the codebase logs partial-data warnings this way |
| Widget inspector | DevTools → Flutter widget tree and paint |
| Breakpoints | Set in VS Code; the pre-launch task runs first, so a failed `analyze` blocks the launch |
| Global error hooks | `FlutterError.onError` and `PlatformDispatcher.instance.onError` are installed in `main()`; background errors are logged **without** crashing the app |
| Boot failure diagnostics | `web/index.html` has an invisible `#boot` layer that reports `window.onerror`, unhandled rejections, a missing `flutter_bootstrap.js`, and a 30-second startup timeout |

### Reproducing a bug locally

1. Clean and regenerate: `flutter clean && flutter pub get && dart run build_runner
   build --delete-conflicting-outputs`
2. Run with your client id if the bug involves sign-in.
3. Check the browser console — most non-fatal errors are logged there, not thrown.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| **Compile errors about missing `*.g.dart` / `*.freezed.dart`** | Generated files are git-ignored and absent | `dart run build_runner build --delete-conflicting-outputs` |
| **White screen on boot** | One of: codegen not run · `--base-href` mismatch · browser storage blocked · assets 404 | Run codegen; for Pages use `--base-href="/Ikigai-Project/"`; check the console — the `#boot` layer prints the specific failure |
| **`Could not find a generated file…`** | `build_runner` output stale after editing a model | Re-run `build_runner` with `--delete-conflicting-outputs` |
| **"Continue with AniList" is disabled** | `ANILIST_CLIENT_ID` not provided and no fallback resolves | Pass `--dart-define=ANILIST_CLIENT_ID=…` |
| **404 when opening `/media/anime/…` directly in dev** | Server not falling back to `index.html` | `flutter run` handles this; for any other static server, serve `index.html` for unknown paths |
| **404 / wrong asset paths on GitHub Pages** | Base href does not match the repo path (case-sensitive) | `flutter build web --release --base-href="/Ikigai-Project/"` — CI derives this from the repository name automatically |
| **White screen *only* on Pages after deploy** | Jekyll stripped `_`-prefixed bundle files | Ensure `.nojekyll` exists in the built output (CI runs `touch build/web/.nojekyll`) |
| **`flutter_bootstrap.js` 404** | Built without the correct base href | The `#boot` layer prints this exact hint; rebuild with the right `--base-href` |
| **429 / "AniList is rate-limiting"** | Per-tab sliding window (80 req/min) or AniList throttling you | Wait — the UI tells you how long. Close extra tabs; two tabs share the real limit |
| **`flutter test` runs nothing** | `/test/` is git-ignored and no test files are tracked | Expected today — see [TESTING.md](TESTING.md) |
| **Analyzer floods / editor freezes on low RAM** | Heavy file watching | Use the tracked `.vscode/settings.json` (watcher excludes, no auto pub get) |
| **Edits to `pubspec.yaml` do not take effect** | `dart.runPubGetOnPubspecChanges` is `never` | Run `flutter pub get` manually |
| **`StateError: sharedPreferencesProvider` (or `gqlStorageProvider`) was not overridden** | A provider was read outside `ProviderScope` overrides — e.g. running a widget test without overrides | Provide the override, as `main()` does |
| **Stale UI after a big change** | Hot reload cannot apply it | `R` for hot restart, or `flutter clean` + relaunch |
| **Storage blocked (private mode)** | localStorage/IndexedDB unavailable | The app still boots: it falls back to mock preferences and an in-memory GraphQL cache. Data is lost when the tab closes |

### Still stuck

1. `flutter clean && flutter pub get && dart run build_runner build
   --delete-conflicting-outputs && flutter analyze`
2. Check `flutter doctor -v` and the browser console.
3. Search [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — the problem may already be recorded.

---

## Related documents

- Release and CI → [DEPLOYMENT.md](DEPLOYMENT.md)
- Code standards and PR flow → [CONTRIBUTING.md](../CONTRIBUTING.md)
- Testing → [TESTING.md](TESTING.md)
- Architecture → [ARCHITECTURE.md](ARCHITECTURE.md)
- Dependencies → [TECH_STACK.md](TECH_STACK.md)
