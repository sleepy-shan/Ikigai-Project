# Deployment

How Ikigai is built, released, and published.

## Contents

- [Supported platforms](#supported-platforms)
- [Production configuration](#production-configuration)
- [Environment variables](#environment-variables)
- [Build commands](#build-commands)
- [Web deployment](#web-deployment)
- [CI/CD pipeline](#cicd-pipeline)
- [Android build (not currently possible)](#android-build-not-currently-possible)
- [iOS build (not currently possible)](#ios-build-not-currently-possible)
- [Versioning](#versioning)
- [Deployment troubleshooting](#deployment-troubleshooting)
- [Release checklist](#release-checklist)

---

## Supported platforms

| Platform | Status | Notes |
| --- | --- | --- |
| **Web (Chrome/Chromium and friends)** | ✅ **Supported and deployed** | GitHub Pages via GitHub Actions |
| Android | ❌ **Not scaffolded** — no `android/` directory | See below |
| iOS | ❌ **Not scaffolded** — no `ios/` directory | See below |
| Windows / Linux / macOS | ❌ **Not scaffolded** | No desktop directories |

`.metadata` records migrations for **`root` and `web` only**. This is a web-first
project by design: there is no backend, storage is browser-local, and the whole
deployment story is a static host.

> **Honest statement:** the Android and iOS sections below describe what **would** be
> required. **They cannot be built from this repository as-is.** Nothing in the build
> configuration is broken — the platform targets simply do not exist yet.

---

## Production configuration

### What makes the release build correct

| Piece | Value / behaviour | Why |
| --- | --- | --- |
| Build mode | `--release` | Tree-shakes, minifies, strips asserts |
| Base href | `--base-href="/<repo>/"` | Project Pages are served from `/<repo>/`, not `/`. Assets and routing are prefix-relative. |
| `.nojekyll` | `touch build/web/.nojekyll` | Jekyll ignores `_`-prefixed files, which would strip the Flutter bundle → **white screen** |
| SPA fallback | `cp build/web/index.html build/web/404.html` | GitHub Pages serves `404.html` for unknown paths, so deep links like `/<repo>/anime` boot the app instead of 404ing. Copied **after** build so the base href matches exactly. |
| Bootstrap | `flutter_bootstrap.js` (generated) | Loaded by `web/index.html` with `async onerror` → boot-failure reporting |
| Renderer | Flutter's default | No `--web-renderer` / canvaskit / skwasm override exists anywhere in the repo |
| URL strategy | **Path** (`usePathUrlStrategy()`) | Clean `/media/anime/123` URLs instead of `/#/…` |

### Boot-time diagnostics built into `web/index.html`

- CSS sets `html, body { background: #0B1212 }` **before the body parses**, so there is
  never a white flash (there is no splash screen).
- An invisible `#boot` layer reports:
  - `window.onerror` and `unhandledrejection`
  - `flutter_bootstrap.js` returning 404 — with an explicit hint to rebuild with
    `--base-href="/Ikigai-Project/"`
  - a **30-second** startup timeout
- The layer removes itself on the `flutter-first-frame` event.

### Web metadata

| File | Value |
| --- | --- |
| `<title>` | `Ikigai — Discover & Track Anime & Manga` |
| `theme-color` | `#0E7C6B` |
| `manifest.json` name | `Ikigai — Discover & Track Anime & Manga`, short `Ikigai` |
| Manifest background / theme | `#0B1212` / `#0E7C6B` |
| Manifest orientation | `portrait-primary` |
| Icons | `Icon-192`, `Icon-512`, maskable variants |
| Favicons | `favicon.svg` (+ `.png` fallback), cache-busted `?v=2` |

`manifest.json` makes the app **installable**, but **no service worker exists** — there
is no offline shell.

---

## Environment variables

Exactly one build-time define:

| Define | Default | Effect if missing |
| --- | --- | --- |
| `ANILIST_CLIENT_ID` | `'53659'` (hardcoded fallback in `lib/core/config/app_config.dart`) | Sign-in is disabled with an explanatory message; everything else works |

```bash
flutter build web --release \
  --dart-define=ANILIST_CLIENT_ID=<your-client-id> \
  --base-href="/Ikigai-Project/"
```

> **The GitHub Pages workflow currently passes no `--dart-define`.** Production
> therefore runs on the hardcoded fallback client id. Supplying your own requires
> editing `.github/workflows/deploy-web.yml` (e.g. a repository variable or secret
> injected as `--dart-define`).

### Also required on the AniList side

The client's **Redirect URL** at <https://anilist.co/settings/developer> must include
the deployed origin, e.g. `https://sleepy-shan.github.io/Ikigai-Project/`, or AniList
refuses the redirect after login.

**No other environment variables, secrets, or API keys exist.** The workflow declares
no `secrets.*` and no `env:` blocks.

---

## Build commands

```bash
# Prerequisites (generated files are gitignored)
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Quality gate
flutter analyze

# Production web bundle
flutter build web --release --base-href="/Ikigai-Project/"

# Optional: explicit client id
flutter build web --release \
  --dart-define=ANILIST_CLIENT_ID=<id> \
  --base-href="/Ikigai-Project/"

# Output
#   build/web/          ← upload this directory as-is
```

Local preview of the release build:

```bash
cd build/web && python3 -m http.server 8080
# deep links need a fallback to index.html; `flutter run` avoids this entirely
```

---

## Web deployment

### Automated (the normal path)

Push to `main` → the workflow builds and publishes to GitHub Pages. No manual step.

### Manual (fallback)

```bash
flutter build web --release --base-href="/Ikigai-Project/"
touch build/web/.nojekyll
cp build/web/index.html build/web/404.html
# upload the contents of build/web/ to your static host
```

Any static host works as long as it serves `index.html` for unknown paths (SPA
fallback) — GitHub Pages does this via the `404.html` copy.

### One-time GitHub Pages setup

Settings → Pages → Source: **GitHub Actions** (the workflow uses
`actions/deploy-pages`, which requires this).

---

## CI/CD pipeline

Single workflow: **`.github/workflows/deploy-web.yml`** — *"Deploy web to GitHub
Pages"*.

### Triggers and policy

| Setting | Value |
| --- | --- |
| Triggers | `push` to **`main`**, plus `workflow_dispatch` (manual) |
| Permissions | `contents: read`, `pages: write`, `id-token: write` |
| Concurrency | group `pages`, **`cancel-in-progress: true`** — a new push aborts an in-flight deploy |
| Runner | `ubuntu-latest` for both jobs |

### Job: `build`

| # | Step | Notes |
| --- | --- | --- |
| 1 | `actions/checkout@v4` | |
| 2 | `subosito/flutter-action@v2` | `channel: stable`, `cache: true` — **version not pinned** |
| 3 | `flutter pub get` | |
| 4 | `dart run build_runner build --delete-conflicting-outputs` | *"freezed / json_serializable output is not committed"* |
| 5 | `flutter analyze` | **The only quality gate.** |
| 6 | ~~`flutter test`~~ | **Commented out** — *"Guards the auth/session regressions (browser refresh, rate-limited validation, stale profile snapshot) before anything is deployed."* See [TESTING.md](TESTING.md). |
| 7 | `flutter build web --release --base-href="/${{ github.event.repository.name }}/"` | Deriving the repo name keeps **forks** working without editing the file. *"Keep both slashes."* |
| 8 | `touch build/web/.nojekyll` | Prevents Jekyll stripping the bundle |
| 9 | `cp build/web/index.html build/web/404.html` | SPA deep-link fallback; copied **after** build so the base href matches |
| 10 | `actions/upload-pages-artifact@v3` | `path: build/web` |

### Job: `deploy`

`needs: build` → environment **`github-pages`** (with `url: ${{ steps.deployment.outputs.page_url }}`) →
`actions/deploy-pages@v4`.

### Properties worth knowing

- **Flutter is not pinned** — CI builds with whatever stable is current at run time.
  A breaking Flutter release can take the pipeline down without any repo change.
- **No secrets, no `env`, no `--dart-define`** — production uses the fallback AniList
  client id.
- **No test execution** — only static analysis.
- **No lint/format enforcement** beyond `flutter analyze`.
- **No artefact retention, no release tagging, no changelog automation.**

---

## Android build (not currently possible)

> **Status: blocked — the `android/` platform directory does not exist.**

To make Android builds possible:

1. Scaffold the platform (this adds `android/`, Gradle files, and the manifest):

   ```bash
   flutter create --platforms=android .
   ```

2. Review the generated `android/app/src/main/AndroidManifest.xml`:
   - App label, icon, and `INTERNET` permission (already present for Flutter apps)
   - **No deep-link intent filter is needed** for the implicit OAuth flow, because the
     redirect returns to the registered web URL, not a custom scheme — unless you
     deliberately add one.

3. Configure signing:

   ```bash
   keytool -genkey -v -keystore ~/ikigai-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias ikigai
   ```

   Then `android/key.properties` + a `signingConfigs` block in
   `android/app/build.gradle`. **Never commit `key.properties` or the keystore.**

4. Build:

   ```bash
   flutter build apk --release          # → build/app/outputs/flutter-apk/app-release.apk
   flutter build appbundle --release    # → build/app/outputs/bundle/release/app-release.aab
   ```

5. Play Store requires: a signed AAB, target API level compliance, a privacy policy
   URL (the app stores data locally and talks to AniList), and store listing assets.

**Additional work implied by leaving the web:**
- `shared_preferences` → native preferences (fine, no code change).
- Hive → file-based box (needs `path_provider`, already a transitive dependency).
- **OAuth redirect** — the implicit-grant flow assumes a browser returns to the app
  origin with a URL fragment. On Android this needs a custom scheme or App Links plus
  token capture in `MainActivity`. This is real work, not a build flag.
- `url_launcher` already has an Android implementation.

---

## iOS build (not currently possible)

> **Status: blocked — the `ios/` platform directory does not exist, and building
> requires macOS + Xcode.**

1. On macOS with Xcode installed:

   ```bash
   flutter create --platforms=ios .
   ```

2. Open `ios/Runner.xcworkspace` in Xcode, set the bundle identifier and signing
   team.

3. Build:

   ```bash
   flutter build ipa --release      # → build/ios/ipa/*.ipa
   flutter build ios --release      # simulator/device build
   ```

4. Distribute via App Store Connect (Xcode organizer or `xcrun altool` /
   `notarytool`), requiring an Apple Developer account.

The same **OAuth redirect problem** described for Android applies: capturing a URL
fragment requires a custom URL scheme or universal links, which is a code change in
addition to scaffolding.

---

## Versioning

| Field | Current value | Meaning |
| --- | --- | --- |
| `pubspec.yaml` `version` | **`1.0.0+1`** | Build name `1.0.0`, build number `1` |
| Git tags | **None** (`git tag -l` is empty) | No formal releases have been cut |

### How Flutter uses it

- **Web:** the version is informational; the bundle does not embed it for update
  checks.
- **Android:** `1.0.0` → `versionName`, `1` → `versionCode`.
- **iOS:** `1.0.0` → `CFBundleShortVersionString`, `1` → `CFBundleVersion`.

Override at build time:

```bash
flutter build web --release --build-name=1.2.0 --build-number=42
```

### Recommended versioning practice

1. Bump `version:` in `pubspec.yaml` in the release PR.
2. Tag it: `git tag -a v1.2.0 -m "…"` and push tags.
3. Record the changes in [CHANGELOG.md](../CHANGELOG.md).

The project has **33 merged PRs and no tags** — the first tagged release is still
ahead.

---

## Deployment troubleshooting

The repository has a long history with GitHub Pages (PRs #4, #6, #8, #9, #10 and five
workflow edits). Every problem below was actually hit.

| Symptom | Cause | Fix |
| --- | --- | --- |
| **White screen on Pages after deploy** | Jekyll stripped `_`-prefixed bundle files | `touch build/web/.nojekyll` (now in CI) |
| **White screen** | Codegen not run in the build | CI runs `build_runner`; locally run it too |
| **White screen / assets 404** | Base href does not match the repo path | `--base-href="/<repo>/"`. **Case-sensitive.** CI derives it from `github.event.repository.name` so forks work |
| **`flutter_bootstrap.js` 404** | Built without the correct base href | The `#boot` layer prints this exact hint; rebuild |
| **Deep link (`/anime`) 404s** | Pages has no SPA fallback | `cp build/web/index.html build/web/404.html` **after** the build (so the base href matches) |
| **Deep links work only after a reload fails** | `index.html` copied *before* build, so hrefs mismatch | Always copy after `flutter build` |
| **Fork's Pages build is broken** | Hardcoded repo name in base href | Use `${{ github.event.repository.name }}` |
| **Deploy finished but old app still loads** | Browser/CDN cache of `index.html` | Hard-refresh; `flutter_bootstrap.js` is loaded async so it is usually `index.html` that is stale |
| **Workflow ran but site not published** | Pages source not set to GitHub Actions | Settings → Pages → Source: **GitHub Actions** |
| **`upload-pages-artifact` finds nothing** | Build output path wrong or build failed earlier | Check the `build` step logs; output must be `build/web` |
| **AniList login fails only in production** | Redirect URL not registered for the deployed origin | Add `https://<user>.github.io/<repo>/` to the AniList client's Redirect URL |
| **`429` after heavy use** | Per-tab 80 req/min gate or AniList throttling | Wait; close extra tabs |
| **Build output committed to the repo** | Build artefacts tracked by git | Removed in PR #8 (`remove/deleted-build`); `/build/` is git-ignored |
| **Two deploys racing** | Concurrent pushes to `main` | Handled: concurrency group with `cancel-in-progress: true` |

### Diagnosing a broken deploy

1. Read the **Actions → build** job log — `flutter analyze` and `build_runner` fail
   loudly.
2. Open the site, hard-refresh, and check the browser console: the `#boot` layer
   prints the specific failure (404, timeout, or an uncaught error).
3. Confirm the served HTML's `<base href>` matches the repo path.
4. Verify `.nojekyll` and `404.html` exist in the deployed output.
5. Reproduce locally with the same base href:
   `flutter build web --release --base-href="/<repo>/"`.

---

## Release checklist

### Pre-release

- [ ] `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs`
- [ ] `flutter analyze` exits clean
- [ ] `flutter test` — *currently reports no tests; run it anyway so regressions in
      intent are visible* ([TESTING.md](TESTING.md))
- [ ] Manual smoke test: home, browse, search + filters, detail, calendar (both tabs
      and a timezone change), My Lists, history
- [ ] Guest-mode pass — everything must work signed out
- [ ] Sign-in pass (if `ANILIST_CLIENT_ID` is configured): sign in, edit progress,
      sign out
- [ ] Light **and** dark theme checked
- [ ] Widths checked: ~360 px, ~1000 px, ~1440 px
- [ ] Deep links verified: `/media/anime/<id>`, `/search?q=…`, `/calendar?tab=manga`
- [ ] No secrets, tokens, or generated files in the diff
- [ ] Browser console clean of red errors

### Release

- [ ] Bump `version:` in `pubspec.yaml`
- [ ] Update [CHANGELOG.md](../CHANGELOG.md)
- [ ] Merge to `main`
- [ ] Watch the **Deploy web to GitHub Pages** workflow
- [ ] Confirm the `github-pages` environment reports the new `page_url`

### Post-release

- [ ] Hard-refresh and verify the deployed site
- [ ] Verify a cold deep link in a private window
- [ ] Verify AniList sign-in on production (redirect URL)
- [ ] Tag: `git tag -a v<version> -m "…" && git push --tags`
- [ ] Close the milestone / linked issues

### If it fails

- [ ] Re-run the workflow (transient runner issues are common)
- [ ] Roll back by re-running the workflow on the previous commit, or redeploy a
      local build from the last good ref
- [ ] Record the cause in [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

---

## Related documents

- Setup and local commands → [SETUP_AND_DEVELOPMENT.md](SETUP_AND_DEVELOPMENT.md)
- Testing (CI gap) → [TESTING.md](TESTING.md)
- Version history → [CHANGELOG.md](../CHANGELOG.md)
- Technical trade-offs → [DECISIONS.md](DECISIONS.md)
