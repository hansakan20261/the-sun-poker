import 'api_service.dart';

class FeatureFlagsService {
  static Map<String, dynamic> _flags = {};

  static Future<void> load() async {
    try {
      final data = await ApiService.get('/settings/feature-flags');
      _flags = Map<String, dynamic>.from(data['flags'] ?? {});
    } catch (_) {
      _flags = {};
    }
  }

  static bool isEnabled(String key) {
    final flag = _flags[key];
    if (flag is Map) return flag['enabled'] != false;
    return true;
  }

  static Map<String, dynamic> config(String key) {
    final flag = _flags[key];
    if (flag is Map && flag['config'] is Map) {
      return Map<String, dynamic>.from(flag['config']);
    }
    return {};
  }
}
