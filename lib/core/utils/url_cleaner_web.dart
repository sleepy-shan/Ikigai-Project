import 'dart:ui_web' as ui_web;

/// Drops the `#fragment` and `?query` from the address bar **in place**
/// (history `replaceState`, no reload, no new history entry).
///
/// After the AniList redirect the URL still reads `…/#access_token=…`; left
/// alone, the token would sit in the address bar, the browser history and
/// anything the user copies or screenshots. Must run after the URL strategy
/// has been configured (`usePathUrlStrategy()` in `main`).
void clearUrlFragment() {
  try {
    final strategy = ui_web.urlStrategy;
    if (strategy == null) return;
    // `getPath()` is app-relative (base href already stripped); keep only the
    // path, then let the strategy put the base href back.
    final path = Uri.parse(strategy.getPath()).path;
    strategy.replaceState(
      strategy.getState(),
      '',
      strategy.prepareExternalUrl(path.isEmpty ? '/' : path),
    );
  } on Object {
    // Cosmetic hardening only: never let it break startup.
  }
}
