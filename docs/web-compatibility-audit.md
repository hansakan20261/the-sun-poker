# Web Compatibility Audit — The Sun Poker PWA

## Date: July 2026

---

## 1. Package Web Support Analysis

| Package | Version | Web Support | Issue | Action |
|---------|---------|-------------|-------|--------|
| `flutter` (sdk) | 3.11.4 | ✅ Full | — | None |
| `cupertino_icons` | ^1.0.8 | ✅ Full | — | None |
| `http` | ^1.6.0 | ✅ Full | — | None |
| `socket_io_client` | ^3.1.4 | ✅ Full | Uses websocket_channel on web | None |
| `shared_preferences` | ^2.5.5 | ✅ Full | Uses localStorage on web | None |
| `audioplayers` | ^6.6.0 | ✅ Full | Uses HTML5 Audio on web | May need user gesture for autoplay |
| `google_fonts` | ^6.2.1 | ✅ Full | — | None |
| `rive` | ^0.13.14 | ✅ Full | Uses CanvasKit on web | None |
| `lottie` | ^3.1.2 | ✅ Full | — | None |
| `image_picker` | ^1.2.2 | ✅ Full | Uses file input on web | Works differently (no camera) |
| `path_provider` | (transitive) | ⚠️ Limited | No filesystem on web | Wrap with kIsWeb check |

---

## 2. dart:io Usage (NOT available on web)

| File | Usage | Fix |
|------|-------|-----|
| `lib/services/api_service.dart` | `import 'dart:io'` → `SocketException` | Replace with conditional import or try/catch generic |
| `lib/screens/profile_screen.dart` | `import 'dart:io'` → `File` for avatar | Use `kIsWeb` + `Uint8List` on web |
| `lib/services/profile_provider.dart` | `import 'dart:io'` + `path_provider` → local file storage | Use `SharedPreferences` + base64 on web |

---

## 3. Web-Incompatible Patterns Found

| Pattern | Files | Fix |
|---------|-------|-----|
| `File()` class | profile_screen, profile_provider | Use `XFile` or `Uint8List` on web |
| `getApplicationDocumentsDirectory()` | profile_provider | Use `SharedPreferences` on web |
| `SocketException` catch | api_service | Catch generic Exception on web |
| Audio autoplay | audio_manager | Require user gesture before first play |

---

## 4. Packages Already Web-Ready (No Changes Needed)

- ✅ `http` — uses XMLHttpRequest on web
- ✅ `socket_io_client` — uses WebSocket on web  
- ✅ `shared_preferences` — uses localStorage on web
- ✅ `google_fonts` — loads from CDN on web
- ✅ `rive` — uses CanvasKit on web
- ✅ `lottie` — uses Canvas on web
- ✅ `image_picker` — uses HTML file input on web

---

## 5. Web-Specific Considerations

### Safari/PWA Issues:
- **Audio autoplay blocked** — need user interaction before playing BGM
- **WebSocket in background** — Safari suspends connections when tab/PWA is backgrounded
- **No filesystem** — must use localStorage/IndexedDB for persistence
- **Viewport meta** — need proper meta tags for iPhone X+ safe area

### Performance:
- CanvasKit renderer (default) — better graphics but larger download (~2MB)
- HTML renderer — smaller but less consistent rendering
- Recommend: CanvasKit for this poker game (needs smooth animations)

---

## 6. Files Requiring Changes

### Critical (will crash without fix):
1. `lib/services/api_service.dart` — `dart:io` import
2. `lib/services/profile_provider.dart` — `dart:io` + `path_provider`
3. `lib/screens/profile_screen.dart` — `dart:io` + `File`

### Enhancement (better UX on web):
4. `lib/services/audio_manager.dart` — handle autoplay policy
5. `lib/services/game_socket.dart` — add reconnect on visibility change
6. `web/index.html` — add viewport meta, PWA meta tags
7. `web/manifest.json` — update name, colors, icons

---

## 7. Implementation Plan

### Phase 1: Make it compile (Critical)
- Replace `dart:io` with conditional imports
- Wrap `File`/`path_provider` usage with `kIsWeb` checks

### Phase 2: Make it work (Functional)  
- Fix audio autoplay for Safari
- Add WebSocket reconnect on page visibility change
- Test login/register/game flow in browser

### Phase 3: Make it shine (Polish)
- Update manifest.json for proper PWA
- Add responsive breakpoints for iPad
- Add install prompt banner

---

## 8. Risk Assessment

| Risk | Level | Mitigation |
|------|-------|-----------|
| Breaking Android/iOS builds | Low | Use conditional imports, never remove mobile code |
| Audio not playing on Safari | Medium | Add "tap to start" overlay before BGM |
| WebSocket drops in background | Medium | Add visibility API reconnect |
| Large initial download | Low | CanvasKit lazy loads, use deferred loading |
| Game performance on web | Low | Poker is not graphics-intensive |

---

## Summary

**Overall: 90% web-ready** — Only 3 files need critical fixes (`dart:io` removal), all packages support web natively. The main work is:
1. Conditional `dart:io` replacement (~30 min)
2. Audio autoplay handling (~15 min)  
3. WebSocket reconnect (~15 min)
4. PWA manifest/meta polish (~10 min)

Total estimated effort: **~2 hours**
