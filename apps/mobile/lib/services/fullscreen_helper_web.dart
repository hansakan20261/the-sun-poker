// Web-only implementation using the browser Fullscreen API.
// Only compiled in when running as Flutter Web (via conditional import in
// fullscreen_helper.dart) — never touches native iOS/Android builds.
import 'dart:html' as html;

bool isFullscreenSupported() => html.document.fullscreenEnabled ?? false;

bool isFullscreenActive() => html.document.fullscreenElement != null;

/// Requests fullscreen on the document body — this is what actually hides
/// the browser's address bar / URL bar (mainly effective on Android Chrome
/// and desktop browsers; iOS Safari does not support the Fullscreen API
/// for regular web pages, so on iOS the address bar can only be hidden by
/// installing the PWA via "Add to Home Screen").
Future<void> requestFullscreen() async {
  try {
    html.document.documentElement?.requestFullscreen();
  } catch (_) {
    // Silently ignore — fullscreen must be triggered by a direct user
    // gesture; if called outside one, the browser rejects the request.
  }
}

Future<void> exitFullscreen() async {
  try {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }
  } catch (_) {}
}
