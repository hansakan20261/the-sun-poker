import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Shared background widget for all main screens.
/// Supports local asset fallback + remote URL from admin settings.
/// Admin can change background via PUT /settings/app-config { background_url, overlay_opacity }
class AppBackground extends StatefulWidget {
  final Widget child;

  /// Override overlay opacity (0.0 = transparent, 1.0 = fully black).
  /// If null, uses admin-configured value or default 0.55.
  final double? overlayOpacity;

  const AppBackground({super.key, required this.child, this.overlayOpacity});

  // ── Static cache shared across all instances ──
  static String? _cachedBgUrl;
  static double _cachedOverlayOpacity = 0.55;
  static bool _fetched = false;
  static bool _fetching = false;

  /// Preload background config from admin API.
  /// Called once on app start and can be called again to force refresh.
  static Future<void> preload({bool force = false}) async {
    if (_fetched && !force) return;
    if (_fetching) return;
    _fetching = true;
    try {
      final config = await ApiService.get('/settings/app-config');
      _cachedBgUrl = config['background_url'] as String?;
      final opacity = config['overlay_opacity'];
      if (opacity != null) {
        _cachedOverlayOpacity = (opacity as num).toDouble().clamp(0.0, 1.0);
      }
      _fetched = true;
    } catch (_) {
      _fetched = true; // Don't retry on every build
    } finally {
      _fetching = false;
    }
  }

  /// Force refresh background from admin (call after admin changes setting).
  static void invalidateCache() {
    _fetched = false;
    _cachedBgUrl = null;
  }

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  @override
  void initState() {
    super.initState();
    AppBackground.preload().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final remoteUrl = AppBackground._cachedBgUrl;
    final opacity =
        widget.overlayOpacity ?? AppBackground._cachedOverlayOpacity;

    return Stack(
      children: [
        // Background image — remote URL from admin, fallback to local asset
        Positioned.fill(
          child: remoteUrl != null && remoteUrl.isNotEmpty
              ? Image.network(
                  remoteUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _localBg(),
                )
              : _localBg(),
        ),
        // Dark overlay for readability
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(opacity)),
        ),
        // Content
        widget.child,
      ],
    );
  }

  Widget _localBg() {
    return Image.asset(
      'assets/bg_main.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0505), Color(0xFF0E0303), Color(0xFF0A0202)],
          ),
        ),
      ),
    );
  }
}
