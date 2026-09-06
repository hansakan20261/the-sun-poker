/// Cross-platform fullscreen control, used to hide the browser address bar
/// on the web build. Resolves to a no-op on native iOS/Android via
/// conditional import, so this file is safe to use from shared widgets
/// without affecting the native app.
export 'fullscreen_helper_stub.dart'
    if (dart.library.html) 'fullscreen_helper_web.dart';
