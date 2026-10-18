// Removes OAuth leftovers from the browser address bar.
//
// Conditional export: the web implementation talks to the browser's history
// through Flutter's URL strategy; every other platform gets a no-op.
export 'url_cleaner_stub.dart'
    if (dart.library.js_interop) 'url_cleaner_web.dart';
