# UI design guidelines

The visual and interaction rules for Ikigai. Anything new should be built from the
tokens in `lib/core/theme/design_tokens.dart` → class **`Tokens`**, not from
hard-coded values.

> **Single source of truth:** every colour, spacing value, radius, breakpoint, and
> duration lives in `lib/core/theme/design_tokens.dart`. Re-theming is a single-file
> change; hard-coding a hex value elsewhere breaks that promise.

## Contents

- [Design philosophy](#design-philosophy)
- [Colour palette and design tokens](#colour-palette-and-design-tokens)
- [Typography](#typography)
- [Spacing and sizing](#spacing-and-sizing)
- [Component guidelines](#component-guidelines)
- [Light and dark themes](#light-and-dark-themes)
- [Responsive design](#responsive-design)
- [Motion](#motion)
- [Accessibility](#accessibility)
- [UI interaction patterns](#ui-interaction-patterns)

---

## Design philosophy

The theme is documented in the code as **"Komorebi Lagoon — chill minimal"**:

> Calm lagoon teal + warm paper sun + still-water mist. Low-saturation so long
> browsing sessions feel restful, not loud.

Five principles, all observable in the code:

1. **Restful, not loud.** Low-saturation palette; gradients are accents (toggle,
   back-to-top, hero), not wallpaper.
2. **Warmth over clinical.** A paper-toned light mode (`#F4EFE3`) rather than pure
   white, and deep pine ink instead of black.
3. **Affordances appear on demand.** Hover lifts, action pills fade in, headers pin.
   Dense lists stay quiet until you engage them.
4. **Never a blank frame.** Skeletons (`shimmer`), tinted image placeholders, and
   fill-remaining `SliverLoading`/`SliverError`/`SliverEmpty` states instead of
   spinners where a layout already exists.
5. **Feedback is subtle, not shouting.** Optimistic updates, a snackbar for background
   failures, a *"syncing to AniList…"* label rather than a blocking modal.

---

## Colour palette and design tokens

All values are from `Tokens` in `lib/core/theme/design_tokens.dart`.

### Brand palette

| Token | Value | Name in code | Use |
| --- | --- | --- | --- |
| `Tokens.brand` | `0xFF0E7C6B` | lagoon teal | Primary in light mode |
| `Tokens.brandDark` | `0xFF5EEAD4` | mist teal | Primary in dark mode |
| `Tokens.accent` | `0xFF3F6F66` | eucalyptus ink | Secondary |
| `Tokens.paper` | `0xFFF4EFE3` | warm paper sun | Light accents / logo |
| `Tokens.ink` | `0xFF0F1E1D` | deep pine ink | Dark accents / logo |
| `Tokens.sun` | `0xFFE9C46A` | calm sunrise gold | Emphasis |
| `Tokens.mist` | `0xFFDCE9E4` | still-water mist | Light tints |
| `Tokens.like` | `0xFFE54666` | score / heart | Favourite + score |
| `Tokens.success` | `0xFF21A179` | | Success |
| `Tokens.warning` | `0xFFF4A62A` | | Warning |
| `Tokens.danger` | `0xFFD64545` | | Errors (also `colorScheme.error`) |

A tertiary `0xFF7D9B8A` is applied only for the Lagoon accent.

### Status colours

Used by `StatusBadge`, list sections, and the profile statistics strip.

| Status | Token | Value |
| --- | --- | --- |
| Watching | `statusWatching` | `0xFF2D9CDB` |
| Planning | `statusPlanning` | `0xFF9B51E0` |
| Completed | `statusCompleted` | `0xFF21A179` |
| Paused | `statusPaused` | `0xFFF2C94C` |
| Dropped | `statusDropped` | `0xFFEB5757` |
| Rewatching | `statusRewatching` | `0xFF3DB4F2` |
| Favourite | `statusFavourite` | `= like` → `0xFFE54666` |

### Surfaces

| Role | Light | Dark |
| --- | --- | --- |
| Scaffold / canvas background | `0xFFEEF3F0` | `0xFF0B1212` |
| Card | `Colors.white` | `0xFF151F1F` |
| `colorScheme.surface` | `0xFFF4F7F5` | `0xFF131B1B` |
| Divider / border | `0xFFDCE5E0` | `0xFF26302F` |
| Input / chip fill | `white` | `0x1B2625` @ 85 % |
| SnackBar | `0xFF14201F` | `0xFF26302F` |
| Bottom nav bar | white @ 92 % | `0xFF0E1515` @ 92 % |
| Top app bar | background @ **82 %** (translucent) | same |

### Gradients and glows

| Token | Definition |
| --- | --- |
| `brandGradient` | `0xFF5EEAD4 → 0xFF0E7C6B → 0xFF0B4F46`, top-left → bottom-right |
| `heroGradient` | `0xFF123332 → 0xFF0B1212`, top → bottom |
| `auroraEmber` | radial `0x330E7C6B → transparent` |
| `auroraInk` | radial `0x283F6F66 → transparent` |
| `cardShadow(brightness)` | dark: black @ 45 %, light: `0xFF0F1E1D` @ 8 %; blur 20, offset (0, 8) |
| `glowShadow(color)` | colour @ 35 %, blur 18, offset (0, 6) — used for hover/selected glow |

### Accent choices

`enum AppAccent` — each drives `ColorScheme.fromSeed`, so Material 3 tonal contrast
(white-on-primary) is guaranteed by the framework.

| Accent | Seed |
| --- | --- |
| Lagoon *(default)* | `0xFF0E7C6B` |
| Moss | `0xFF5B7F5A` |
| Dusk | `0xFF3E4E8A` |
| Sand | `0xFFA98B4F` |
| Slate | `0xFF475569` |
| Sakura | `0xFFB57E8A` |

> **Partial:** the accent is applied at runtime and persisted (`ikigai.accent`), but
> **the settings dialog no longer exposes a picker** — it reads *"Theme mode only
> (accent color removed)"*. Pre-rebrand names are migrated by
> `AppAccent.fromName` (`vermilion → lagoon`, `ink → slate`, …).

**Rule:** screens must use `scheme.primary / onSurface / onSurfaceVariant` rather than
hard-coding the old vermilion, so every accent stays accessible.

---

## Typography

- **No bundled web fonts.** `TypeScale.fontFamily = null` → the platform stack
  (system-ui / Roboto). Keeps the bundle small; `pubspec.yaml`'s `fonts:` block is
  commented out.
- Base is `Typography.material2021()` (black light / white dark), overridden by
  `TypeScale`.

| Role | Size | Weight | Height | Extra (from `AppTheme`) |
| --- | --- | --- | --- | --- |
| `displaySmall` | 28 | w700 → **w800** | 1.2 | letterSpacing −0.5 |
| `headlineMedium` | 22 | w700 → **w800** | 1.25 | letterSpacing −0.3 |
| `headlineSmall` | 18 | w600 → **w700** | 1.3 | letterSpacing −0.2 |
| `titleLarge` | 16 | w600 | 1.35 | app bar title is w800, −0.2 |
| `titleMedium` | 14 | w600 | 1.4 | |
| `bodyLarge` | 15 | w400 | 1.5 | SnackBar content (white) |
| `bodyMedium` | 13 | w400 | 1.45 | hints, tooltips |
| `labelLarge` | 13 | w600 | 1.3 | buttons w700 + letterSpacing 0.1 |
| `labelSmall` | 11 | w500 | 1.3 | eyebrows / nav labels |

**Eyebrow labels** (section headers) are `labelSmall`, uppercase, with letter-spacing
around 1.2–1.4 applied at the widget level.

**Rules**
- Titles use the heavy weights (w700/w800) with **negative** letter-spacing — the
  tight, confident look is part of the identity.
- Body copy never goes below 13 px.
- Chips and small labels derive colour from the scheme so contrast is guaranteed.

---

## Spacing and sizing

### Spacing scale — 4 pt grid

`space2` 2 · `space4` 4 · `space8` 8 · `space12` 12 · `space16` 16 · `space20` 20 ·
`space24` 24 · `space32` 32 · `space48` 48

Use these instead of magic numbers. Chip padding is `space12` / `space8`; input
content padding is `space16` / `space12`.

### Radii

| Token | Value | Used by |
| --- | --- | --- |
| `radiusSm` | 6 | Tooltips |
| `radiusMd` | 10 | Inputs, buttons, icon buttons, nav indicators |
| `radiusLg` | 16 | Cards |
| `radiusXl` | 24 | Dialogs, bottom sheets |
| `radiusPill` | 999 | Chips, toggles, segmented controls, scrollbars |

### Component sizes

| Token | Value |
| --- | --- |
| `appBarHeight` | 64 |
| `posterAspect` | 0.68 (classic 2:3 poster) |
| `iconButtonSize` | 40 × 40 minimum |
| `inputHeight` | 44 (button minimum height too) |
| `railGap` | 16 |
| `railCardWidth` | 148 — **all rails use this so cards line up** |
| `railStripHeight` | 252 |
| `maxContentWidth` | 1280 (centred layouts on ultra-wide) |
| `narrowMaxWidth` | 720 (search field, settings cards) |

### Shadows

- Cards: **no elevation** (`elevation: 0`) — separation comes from
  `cardShadow(brightness)` plus a hairline border (white @ 7 % dark, `#DCE5E0` light).
- Hover/selection: `glowShadow(scheme.primary)`.

---

## Component guidelines

### Buttons

All button themes share `minimumSize: Size(0, Tokens.inputHeight)` (44 px tall) and
`radiusMd` (10 px) shapes.

| Theme | Background | Foreground | Notes |
| --- | --- | --- | --- |
| Elevated | `scheme.primary` | `scheme.onPrimary` | `labelLarge` w700, elevation 0 |
| Outlined | transparent | `scheme.onSurface` | 1 px side, white @ 14 % in dark |
| Filled | `scheme.primary` | `scheme.onPrimary` | `radiusMd` |
| Text | transparent | `scheme.primary` | `labelLarge` w700 |
| Icon | — | — | 40 × 40 minimum, `radiusMd` |

Use `Pressable` (scales to 0.96 over 120 ms, `RepaintBoundary` so only the transform
animates) for tactile feedback on cards and chips.

### Cards

`CardThemeData`: `elevation: 0`, `margin: zero`, `radiusLg`, hairline border.

- **`PosterCard`** — generic poster tile (aspect 0.68), used in grids and lists.
- **`BrowseCard`** — poster + title + format/status meta for browse grids.
- **`SectionHeader`** — title + eyebrow pill + optional action pill. The action pill
  (`_HoverActionPill`) lifts 1.04, slides −0.06, and gains
  `Tokens.glowShadow(primary)` on hover; scales to 0.95 on press.
- **`ReleaseCard`** (calendar) — poster, format badge, title + bell, episode,
  platform chip.
- **Rail cards** are fixed at `railCardWidth` 148 so every rail aligns.

### Status badges

`StatusBadge`:
- Colour from `Tokens.status*`; **220 ms `easeOutCubic` colour animation**.
- **Light mode darkens hue by −0.18 lightness** for contrast.
- **Type-aware labels:** `Watching` becomes `Reading` for manga.

### Dialogs

`DialogThemeData`: `card` background, `radiusXl` (24 px), no elevation tricks.

The sign-in dialog is the reference structure: `_DialogHero` gradient banner with the
"生" glyph → `_HeroPill` row (Free / Auto sync / Private) → `_PerkGrid` (2×2) →
*"Secure OAuth · We never see your password"* → primary action → "Maybe later"
dismiss → `_AlBadge`.

### Bottom sheets

`BottomSheetThemeData`: `card` background, top corners `radiusXl`, **drag handle
shown**. Used by the mobile search-filter sheet.

### Forms and inputs

`InputDecorationTheme`: filled, `radiusMd`, content padding `space16` / `space12`.

- Enabled border = hairline; **focused border = `scheme.primary` at 1.5 px**;
  error border = `scheme.error`.
- Hint text = `bodyMedium` in `onSurfaceVariant`.
- Filter panels edit a **draft copy** and only request on Apply.
- `SearchFilterFields` primitives: `FilterLabel`, `FilterFieldBox`, `FilterSelect`,
  `GenreChips`, `GenreMenuField`, `ScoreField` (half-point steps, displays "8.0+"),
  `YearRangeField`, `ActiveFilterPill`.
- The filter editor's Apply button shows a **live count** —
  `Apply Filters (1,234)` — debounced at 350 ms.

### Chips

`ChipThemeData`: pill radius, `radiusPill`, no checkmark, no elevation, padding
`space12` / `space8`.

> The label colour is **explicitly** set to `scheme.onSurface` because relying on
> Chip defaults left genre text near-invisible in dark mode (dark text on a dark
> chip). Keep this if you touch chip theming.

### Skeletons and placeholders

- Use `shimmer` for loading cards (`_ReleaseCardSkeleton`, browse skeletons).
- Images use tinted placeholder error builders (`_placeholderTints` in search,
  `placeholder()` on home) — never a broken-image glyph.
- While a layout exists, use fill-remaining `SliverLoading` / `SliverError` /
  `SliverEmpty`; do not replace a known layout with a centred spinner.

### Scrollbars

Thickness 8, fully rounded (`999`), transparent track, thumb
`scheme.primary` @ 28 % (55 % on hover).

---

## Light and dark themes

Both are built from the same tokens by `AppTheme._base(brightness, accent)`:

| Aspect | Light | Dark |
| --- | --- | --- |
| Scaffold | `0xFFEEF3F0` | `0xFF0B1212` |
| Card | `white` | `0xFF151F1F` |
| Border | `0xFFDCE5E0` | white @ 7 % |
| Primary | `Tokens.brand` `0xFF0E7C6B` | `Tokens.brandDark` `0xFF5EEAD4` |
| Type base | `Typography.material2021().black` | `.white` |
| App bar | background @ 82 % (translucent) | same |

- `useMaterial3: true` throughout; `splashFactory: InkSparkle.splashFactory`.
- **Theme mode** — `ThemePreference {system, light, dark}` persisted to `ikigai.theme`
  (default `system`); `themeModeProvider` derives `ThemeMode` with `select`.
- The **aurora background** is painted by `AppShell` behind all content, so content
  sits on tinted glass over the glow rather than flat colour.
- Chip contrast is corrected per-brightness; `StatusBadge` adjusts lightness per mode.

---

## Responsive design

### Breakpoints

| Token | Value | Applies to |
| --- | --- | --- |
| `breakpointCompact` | **600** | Phones. Search lens appears at ≥ 600. |
| `breakpointMedium` | **1000** | **Navigation switches bottom bar ↔ sidebar.** Filter form sidebar vs draft sheet. |
| `breakpointExpanded` | **1400** | Large desktop |

| Component | Columns / layout |
| --- | --- |
| `posterColumns` / `browsePosterColumns` | Width-based (see `state_views.dart`) |
| Search filter panel grid | 3 cols ≥ 820 px · 2 cols ≥ 520 px · 1 col below |
| Profile stats | 1 col phone → 2 cols from tablet width |
| `AppFooter` | Wide ≥ 800 px; bottom row splits ≥ 640 px |
| Theme segmented control | **Icons only below 380 px** (320 px phones) |

### Shell behaviour

| Width | Navigation |
| --- | --- |
| < 1000 px | Bottom bar — Home, Anime, Manga, Calendar, Watchlist |
| ≥ 1000 px | Sidebar — 232 px expanded / 72 px collapsed, animated 600 ms, adds History + Settings |

- Top bar height 64; search lens at ≥ 600 px, hidden on `/search`.
- **`maxContentWidth` 1280** centred for content sections; `narrowMaxWidth` 720 for
  forms.

### Layout primitives

- `Responsive` helpers in `lib/core/theme/responsive.dart`.
- Sticky section headers: `StickyHeaderDelegate` (`SliverPersistentHeader`, pinned).

---

## Motion

Central system in `lib/core/theme/app_motion.dart` — *"implicit animations only,
cheap rebuilds, consistent durations/curves."*

### Durations

| Token / constant | Value | Use |
| --- | --- | --- |
| `AppMotion.press` | **120 ms** | Press scale (via `Pressable`) |
| `AppMotion.toggle` | **220 ms** | Toggle, segmented control, colour transitions |
| `Tokens.durationFast` | 150 ms | Small state changes |
| `AppMotion.reveal` | **380 ms** | Entrance reveals |
| `Tokens.durationMedium` | 250 ms | Back-to-top button |
| `Tokens.durationSlow` | 400 ms | Slower transitions |
| `AppMotion.shimmer` | **1300 ms** | Skeleton sweep |
| `Tokens.durationReveal` | 480 ms | Larger reveals |
| `Tokens.durationHero` | 700 ms | Hero moments |
| Page fade (`_PageFade` / `_SmoothFadeBuilder`) | **260 ms** | Route changes |
| Sidebar width | **600 ms** | Collapse/expand |
| Banner loop | **24 s** | Profile banner painters |

### Curves

| Token | Curve | Use |
| --- | --- | --- |
| `AppMotion.ease` / `Tokens.curveSmooth` | `Curves.easeOutCubic` | Default |
| `AppMotion.snap` / `Tokens.curveSnap` | `Curves.easeOutBack` | Spring-back / emphasis |

### Reusable motion widgets

| Widget | Behaviour |
| --- | --- |
| `Pressable` | Scales to 0.96 on tap-down, springs back; `RepaintBoundary` isolates the transform so heavy children (images) are not rebuilt |
| `AnimatedToggle` | Sliding thumb, gradient fill when on, glow, `Semantics(toggled:, button:)` |
| `FadeSlideIn` | Staggered entrance — `delayStep` 35 ms, `maxStagger` 8, `slide` 14 px; **implicit animations, so hundreds of grid items cost ~zero tickers**; timer cancelled on dispose |
| `BackToTopButton` | Fades + scales in when visible |
| `AnimatedThemeSegmented` | Sliding gradient pill for theme mode |
| `RevealOnScroll` | Stagger 40 ms × 8 steps, 320 ms fade + slide |
| `HoverLift` | 220 ms, scale 1.025, lift 6 px |

### Page transitions

- **Web/Windows/Linux:** `_SmoothFadeBuilder` — fade in + slide 2 % + scale 0.985 →
  1.0 with `easeOutCubic`; outgoing page dips to 0.92 opacity for a cross-fade feel.
- **Android:** `FadeUpwardsPageTransitionsBuilder`.
- **iOS/macOS:** `CupertinoPageTransitionsBuilder`.
- Inside the shell, `_PageFade` cross-fades pages over 260 ms with
  `Tokens.curveSmooth`.

### Reduced motion

The profile banner's 24 s `AnimationController` stops under
`MediaQuery.disableAnimations`. Note that **most other implicit animations do not
explicitly check this flag** — see [Accessibility](#accessibility).

---

## Accessibility

### What exists

| Measure | Where |
| --- | --- |
| **Explicit chip label colours** | `chipTheme.labelStyle` forced to `scheme.onSurface` so genre text stays above 4.5:1 on the dark chip fill (the comment in `app_theme.dart` states this explicitly) |
| **Light-mode status contrast** | `StatusBadge` darkens hue lightness by −0.18 in light mode |
| **`Semantics` on the toggle** | `AnimatedToggle` passes `label`, `toggled`, `button`, `enabled` |
| **Tooltips on icon-only buttons** | Time zone, Previous/Next week, Remind me, Back to top, and others |
| **Cursor feedback** | `MouseRegion` sets `SystemMouseCursors.click` on interactive areas |
| **Reduced motion honoured** | Profile banner animations stop under `disableAnimations` |
| **Scheme-derived colours** | Accent-driven `ColorScheme.fromSeed` keeps white-on-primary contrast for every accent |
| **Semantics-aware Material widgets** | Buttons, chips, inputs, navigation all use framework widgets with built-in semantics |

### What is **not** verified

Be honest with yourself when extending the UI — none of the following is in place:

- **No automated accessibility tests** — no `accessibility_finder`, no screen-reader
  pass, no axe/`flutter_test` a11y integration. (There are no tracked tests at all;
  see [TESTING.md](TESTING.md).)
- **No focus-trap or keyboard-navigation tests.** Dialogs and the filter sheet are not
  verified for focus containment or Escape-to-dismiss.
- **`disableAnimations` is not checked by most transitions** — page fades, hover lifts,
  `FadeSlideIn`, shimmer, and the sidebar animation all run regardless of the OS
  reduced-motion setting.
- **No documented colour-contrast audit.** The 4.5:1 claim above is a code comment
  about one chip style, not a measured audit of the palette.
- **No minimum touch-target audit** beyond the 40/44 px theme minimums.
- **No localisation.** All copy is hard-coded English; `intl` is used for formatting,
  not message translation.

---

## UI interaction patterns

| Pattern | How it works here |
| --- | --- |
| **Hover reveal** | Action pills, header controls, and `HoverLift` appear/gain glow on hover only — dense grids stay quiet. |
| **Draft-then-apply** | Desktop filter panels apply live; mobile opens a sheet and only requests on **Show results**. `SearchFilters` is a pure value type so one Apply = one network request. |
| **Optimistic update** | Progress/status/score changes render immediately from the overlay; rollback is deleting the overlay. See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md). |
| **Background failure → snackbar** | Sync errors are reported to `entrySyncErrorProvider`, listened once in `AppShell`, and shown as a floating snackbar — never a modal. |
| **Skeleton over spinner** | `shimmer` placeholders while a layout's shape is already known. |
| **Sticky headers** | `StickyHeaderDelegate` pins section headers during scroll. |
| **Keyboard shortcuts** | `/` and `Ctrl/Cmd + K` open search from anywhere. |
| **Cross-fade navigation** | 260 ms page fade; content does not hard-cut. |
| **Live counts** | The filter Apply button previews the result count before committing. |
| **Inline empty states** | `_InlineEmpty` / `SliverEmpty` describe what to do next rather than showing a bare "no results". |
| **Deep-linkable views** | `?rail=`, `?tab=`, `?q=` reproduce the exact view on load. |

---

## Checklist for new UI

1. Colours, spacing, radii, durations come from `Tokens` — **no literals**.
2. Text uses `TypeScale` roles via `Theme.of(context).textTheme`.
3. Colour comes from `scheme.*`, never a hard-coded hex (accent-safe).
4. Handles three widths: 360 px phone, 1000 px tablet, 1440 px desktop.
5. Defines loading, empty, and error states — skeletons where the layout is known.
6. Icon-only controls have a `tooltip`.
7. Uses `AppMotion` durations/curves; respects `disableAnimations` where practical.
8. Updates [FEATURES.md](FEATURES.md) if the behaviour changed.

---

## Related documents

- Tokens source → `lib/core/theme/design_tokens.dart`
- Theme construction → `lib/core/theme/app_theme.dart`
- Motion widgets → `lib/core/theme/app_motion.dart`
- Feature/component inventory → [FEATURES.md](FEATURES.md)
- Tech rationale → [TECH_STACK.md](TECH_STACK.md)
