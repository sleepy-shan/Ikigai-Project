# Contributing to Ikigai

Thanks for helping. This document captures how the project is actually developed
today, plus the standards we want to hold to going forward.

## Contents

- [Getting started](#getting-started)
- [Branch naming](#branch-naming)
- [Commit message conventions](#commit-message-conventions)
- [Coding standards](#coding-standards)
- [Pull request process](#pull-request-process)
- [Code review rules](#code-review-rules)
- [Documentation](#documentation)
- [Reporting bugs](#reporting-bugs)
- [Current gaps in this guide](#current-gaps-in-this-guide)

---

## Getting started

1. Fork and clone.
2. Install dependencies **and generate code** — the codegen step is mandatory:

   ```bash
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```

   `*.g.dart` and `*.freezed.dart` are git-ignored, so a fresh clone **does not
   compile** without it.

3. Create your branch from `main`.
4. Make the change.
5. Before pushing:

   ```bash
   flutter analyze        # must be clean
   ```

6. Run the app and confirm the change behaves as described.

Full environment setup, commands, and troubleshooting:
[docs/SETUP_AND_DEVELOPMENT.md](docs/SETUP_AND_DEVELOPMENT.md).

---

## Branch naming

The repository uses a prefix + kebab-case slug, sometimes with a version marker when
the same area is iterated on. Real examples from `git branch -a`:

| Prefix | Use | Real examples |
| --- | --- | --- |
| `feature/…` | New capability or UI change | `feature/v3-search-design`, `feature/v2-home-design`, `feature/navigation-components-sidebar`, `feature/project-name` |
| `bugfix/…` | Defect fix | `bugfix/v4-anilist-auth`, `bugfix/v1-dart-package`, `bugfix/button-event` |
| `chore/…` | Tooling, config, housekeeping | `chore/v1-fix-deployment`, `chore/ignore-test-folder` |
| `refactor/…` | Restructure with no behaviour change | `refactor/project-name`, `refactor/redesign-layout` |
| `revert/…` | Undoing a merged change | `revert/v1-fix-deployment` |

**Convention going forward:**

```
<type>/<slug>              e.g. feature/profile-export
<type>/v<n>-<slug>         e.g. bugfix/v2-anilist-fetch     (when iterating on the same area)
```

- Lowercase, hyphen-separated, no spaces.
- `v1`, `v2`, … only when reworking the same area repeatedly — it keeps related
  branches sortable.
- One logical change per branch. History shows small, focused branches work well here.

---

## Commit message conventions

### What the history actually looks like

Current practice is **free-form and lowercase**, with occasional conventional-commit
prefixes. Real subjects from `git log`:

```
redesign the cards under the home screen
add animation in side bar
chore: stop tracking test folder
feat redesign the home
fix the problem in fetching anilist data under profile
successfuly fix anime and manga screen          ← typo, as committed
fixminr changes                                 ← typo, as committed
```

> **Be honest about this:** the repository does **not** currently enforce any commit
> format, and several subjects contain typos. There is no commit linter, no
> `commitlint`, and no pre-commit hook.

### The standard we want going forward

```
<type>: <imperative summary, lowercase, ≤ 72 chars>
```

| Type | Use | Example |
| --- | --- | --- |
| `feat` | New user-visible capability | `feat: add manga releases to the calendar` |
| `fix` | Defect fix | `fix: discard superseded browse responses` |
| `chore` | Tooling, config, dependencies | `chore: stop tracking test folder` |
| `docs` | Documentation only | `docs: document the rate-limit gate` |
| `refactor` | No behaviour change | `refactor: extract tab loader from search controller` |
| `style` | Formatting, no logic change | `style: apply dart format` |
| `test` | Adding or changing tests | `test: cover tracking status rules` |
| `perf` | Performance only | `perf: select narrow rebuild on list rows` |

- Imperative mood: "add", not "added" or "adds".
- Lowercase summary; no trailing period.
- Body explains **why** when the diff does not make it obvious.
- Reference the issue/PR number when there is one.

Past commits are **not** rewritten — they stay as they are.

---

## Coding standards

### Linting

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
(**`flutter_lints ^6.0.0`**) with **no custom rules enabled** — the `rules:` block
contains only commented-out examples. The analyzer excludes `build/**` and `web/**`.

```bash
flutter analyze     # must exit clean; this is the only CI gate
```

`dart format --set-exit-if-changed` does **not** run in CI. Format before pushing.

### Layering (non-negotiable)

```
ui  ──▶  state  ──▶  data  ──▶  core
```

| Rule | Why |
| --- | --- |
| `core/` imports no other app layer | Primitives must not create cycles |
| `data/` never imports `state/` or `ui/` | Data stays testable without a UI or provider container |
| `state/` never imports `ui/` | Controllers stay unit-testable |
| `ui/` never constructs a repository or HTTP client | All I/O enters through providers so startup overrides work |
| Only `main.dart` calls `ProviderScope(overrides: …)` | One place binds infrastructure |

Full rationale: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Errors

- Cross layers as **`AppException` + `ErrorKind`**, never as ad-hoc strings.
- `AppException.message` is developer-facing and **must not reach the UI**.
- User-facing copy comes from `AppException.userMessage` (or a controller's formatted
  fallback).
- Controllers catch `AppException` specifically, then a generic `catch` for the rest.

### State

- Use **`Notifier<T>` + `NotifierProvider`** — no `StateNotifier`, `StateProvider`, or
  `AsyncNotifier`.
- Providers are **hand-written top-level globals**; there is no Riverpod codegen. Do
  not introduce `@riverpod`.
- Any provider consuming GraphQL through `swrQuery`/`GqlCatalog` must pass
  **`retry: noProviderRetry`** — Riverpod 3 otherwise auto-retries against a rate
  limit the transport already retries.
- Guard every fetch with a **monotonic request id** so superseded responses are
  discarded.
- Use **`.select(…)`** for narrow rebuilds instead of watching a whole controller.
- Debounce network-triggering input: search **400 ms**, list-sync **500 ms**.

### Networking

- All traffic goes through the GraphQL client (`gqlCatalogProvider` /
  `MediaRepository.transport`) — do not add raw `http` calls.
- Respect the rate budget: prefer cache reads inside the TTL; **never** make
  `cacheAndNetwork` the default for a hot path.
- **Never put user-specific fields** (`mediaListEntry`, `isFavourite`) in the shared
  `MediaCard` fragment — responses normalise onto account-agnostic `Media:<id>`
  records and would leak across accounts.
- Token-bearing requests must always go to the network, never the cache.

### Models

- **Domain models** (`lib/data/models/`): hand-written `toJson`/`fromJson`. Keep the
  defensive parsing — AniList payloads are not always complete.
- **GraphQL models** (`lib/data/graphql/models/`): `freezed` + `json_serializable`.
- After touching either, **re-run `build_runner`**; generated files are not committed.
- JSON converters must **fall back to `unknown`, never throw** — a new AniList enum
  value must degrade, not crash.

### Storage

- New persisted state gets a namespaced key: `ikigai.<area>.<name>` (with a `.v1`
  suffix where the shape may change).
- Legacy `sandwich.*` keys are read once for migration and never written.
- Update controller state first, then `await prefs.setX(…)`; a failed write throws
  `AppException(ErrorKind.storage, …)`.

### UI

- Colours, spacing, radii, and durations come from **`Tokens`** — no magic numbers or
  hex literals. Use `scheme.*` rather than hard-coded colours so accents stay
  accessible.
- Define loading, empty, **and** error states for anything that fetches.
- Icon-only controls get a `tooltip`.
- Handle 360 px, 1000 px, and 1440 px widths.
- Skeletons over spinners where the layout shape is already known.

See [docs/UI_DESIGN_GUIDELINES.md](docs/UI_DESIGN_GUIDELINES.md).

### Dead code

If you find unused code, either remove it or open an issue. Current known instances
are tracked in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) — please do not add more
without recording them.

---

## Pull request process

1. **Branch from `main`** using the naming convention above.
2. **Keep PRs focused.** The project's history is 33 merged PRs of small, single-purpose
   changes — that works.
3. **Before pushing:**

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   flutter analyze
   ```

4. **Open the PR against `main`** with:
   - **What** changed, in a sentence or two.
   - **Why** (link the issue, or explain the problem).
   - **How to test** — concrete steps a reviewer can follow.
   - **Screenshots or a short recording** for any visual change (light **and** dark
     mode if you touched them).
   - **Anything known not to work**, honestly.

5. **Self-review the diff** before requesting review.
6. **Respond to review**, then squash-merge or merge-commit — match whatever the
   existing PR history does for that change size.

### Merge criteria

- [ ] `flutter analyze` is clean.
- [ ] Generated files are **not** committed (`*.g.dart`, `*.freezed.dart`).
- [ ] No secrets, tokens, or client secrets committed.
- [ ] Layering rules respected.
- [ ] Guest mode still works (no accidental auth requirement).
- [ ] Loading / empty / error states covered for new fetches.
- [ ] Docs updated where behaviour changed.

---

## Code review rules

Reviewers check these in order:

### Blocking

| # | Check |
| --- | --- |
| 1 | **Layering respected** — no `data → ui`, no `state → ui`, no raw HTTP in `ui/`. |
| 2 | **No credentials committed** — tokens, client secrets, private keys. Public client ids are fine. |
| 3 | **No generated files committed** — `*.g.dart` / `*.freezed.dart` must stay ignored. |
| 4 | **Errors use `AppException`** and developer messages do not reach the UI. |
| 5 | **Rate-limit safety intact** — `noProviderRetry` present on GraphQL providers, no request-on-every-rebuild pattern, cache TTLs not gutted. |
| 6 | **Guest mode unbroken** — nothing newly requires sign-in. |
| 7 | **No user-specific fields in the shared `MediaCard` fragment.** |
| 8 | **`flutter analyze` clean.** |

### Should fix

- Loading, empty, and error states defined for new fetches.
- `.select()` used where a whole-controller watch would over-rebuild.
- Magic numbers replaced with `Tokens`.
- Deep links (`?rail=`, `?tab=`, `?q=`) still reproduce the view.
- Text fits at 360 px and 1440 px.

### Nice to have

- A test added (see the caveat below).
- Docs updated.
- A follow-up issue filed for anything knowingly left out.

### Tone

Review the code, not the person. Prefer *"this could race if X"* over *"this is
wrong"*. Authors: prefer *"good catch"* over defensiveness.

> **There is no CODEOWNERS file and no PR template** — this section is the whole
> review policy.

---

## Documentation

Update the matching document when you change behaviour:

| You changed… | Update… |
| --- | --- |
| What the app can do | [docs/FEATURES.md](docs/FEATURES.md) |
| Architecture, layers, routing | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Dependencies or tooling | [docs/TECH_STACK.md](docs/TECH_STACK.md) |
| Endpoints, queries, rate limits | [docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md) |
| Providers, async patterns | [docs/STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md) |
| Storage keys, cache, TTLs | [docs/DATABASE_AND_STORAGE.md](docs/DATABASE_AND_STORAGE.md) |
| Visual rules, tokens | [docs/UI_DESIGN_GUIDELINES.md](docs/UI_DESIGN_GUIDELINES.md) |
| Setup, commands, env vars | [docs/SETUP_AND_DEVELOPMENT.md](docs/SETUP_AND_DEVELOPMENT.md) |
| Build, release, CI | [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) |
| Testing | [docs/TESTING.md](docs/TESTING.md) |
| A meaningful technical trade-off | [docs/DECISIONS.md](docs/DECISIONS.md) (add an ADR) |
| A newly discovered bug or limitation | [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) |
| User-visible release | [CHANGELOG.md](CHANGELOG.md) |

**Never document a planned feature as if it ships.** Use the status vocabulary in
[docs/FEATURES.md](docs/FEATURES.md): *Completed*, *Partial*, *In progress*,
*Planned*.

---

## Reporting bugs

Open an issue (or use the template in [docs/TESTING.md](docs/TESTING.md#bug-reproduction-guidelines)) with:

1. **Steps to reproduce** — numbered, starting from a clean load.
2. **Expected vs actual** behaviour.
3. **Environment** — browser + version, OS, signed-in or guest, local or the deployed
   Pages site.
4. **Console output** — any red errors from DevTools.
5. **Screenshots/recordings** for anything visual.
6. **Frequency** — always, sometimes, once.

Security issues: **do not** open a public issue. Contact the maintainer directly.

---

## Current gaps in this guide

Stated plainly so nobody is surprised:

| Gap | Detail |
| --- | --- |
| **No tracked tests** | `/test/` is git-ignored and no `*_test.dart` files exist. "Add tests" is aspirational, not enforceable. See [docs/TESTING.md](docs/TESTING.md). |
| **`flutter test` is disabled in CI** | The step is commented out in `.github/workflows/deploy-web.yml`. |
| **No pre-commit hooks** | No `husky`/`lefthook`, no `commitlint`, no `dart format` enforcement. |
| **No CODEOWNERS / PR template / issue templates** | Review policy is this document only. |
| **No custom lint rules** | Only the stock `flutter_lints` set. |
| **Flutter version not pinned in CI** | Builds track latest stable; local/CI drift is possible. |
| **No coverage reporting** | `coverage/` is git-ignored; no codecov/coveralls. |

Contributions that close these gaps are especially welcome.

---

## License

By contributing, you agree that your contributions are licensed under the MIT
License — see [LICENSE](LICENSE).
