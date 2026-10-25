import 'dart:js_interop';

/// Browser `history.replaceState`, bound directly.
@JS('history.replaceState')
external void _replaceState(JSAny? data, JSString title, JSString url);

/// Removes the OAuth `#fragment` (and any `?query`) from the address bar,
/// in place: no reload and no new history entry.
///
/// The URL is rebuilt from [Uri.base], which is already the full absolute
/// address, so the deployment's base path (for example `/Ikigai-Project/`)
/// is kept exactly once. The previous version went through the URL
/// strategy's `getPath` + `prepareExternalUrl`, which added the base path a
/// second time and produced `/Ikigai-Project/Ikigai-Project/` ("Page not
/// found" after sign-in).
void clearUrlFragment() {
  try {
    final current = Uri.base;
    if (current.fragment.isEmpty && !current.hasQuery) return;
    final clean = current.replace(fragment: '', query: '');
    _replaceState(null, ''.toJS, clean.toString().toJS);
  } on Object {
    // Cosmetic only: never let it break startup.
  }
}
