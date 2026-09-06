/// No-op implementation for native platforms (iOS/Android/desktop).
/// The Fullscreen API only exists in browsers — on native platforms there
/// is no address bar to hide, so these calls do nothing.
bool isFullscreenSupported() => false;

bool isFullscreenActive() => false;

Future<void> requestFullscreen() async {}

Future<void> exitFullscreen() async {}
