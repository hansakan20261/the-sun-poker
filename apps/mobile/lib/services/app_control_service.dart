import 'api_service.dart';
import '../config.dart';

class AppControlResult {
  final bool blocked;
  final String? message;
  const AppControlResult({required this.blocked, this.message});
}

class AppControlService {
  static Future<AppControlResult> load() async {
    try {
      final config = await ApiService.get('/settings/app-control');
      if (_maintenanceActive(config)) {
        return AppControlResult(
          blocked: true,
          message: _requiredString(config, 'maintenance_message'),
        );
      }
      final minimum = _requiredString(config, 'min_supported_version');
      if (_compareVersions(AppConfig.appVersion, minimum) < 0) {
        return AppControlResult(
          blocked: true,
          message: _requiredString(config, 'force_update_message'),
        );
      }
      return const AppControlResult(blocked: false);
    } catch (_) {
      return const AppControlResult(
        blocked: true,
        message: 'ไม่สามารถตรวจสอบสถานะระบบได้',
      );
    }
  }

  static String _requiredString(Map<String, dynamic> config, String key) {
    final value = config[key];
    if (value == null) throw StateError('Missing app control config: $key');
    return value.toString();
  }

  static bool _maintenanceActive(Map<String, dynamic> config) {
    if (config['maintenance_enabled'] is! bool) {
      throw StateError('Missing app control config: maintenance_enabled');
    }
    if (config['maintenance_enabled'] != true) return false;
    final now = DateTime.now();
    final starts = DateTime.tryParse(
      config['maintenance_starts_at']?.toString() ?? '',
    );
    final ends = DateTime.tryParse(
      config['maintenance_ends_at']?.toString() ?? '',
    );
    if (starts != null && now.isBefore(starts)) return false;
    if (ends != null && now.isAfter(ends)) return false;
    return true;
  }

  static int _compareVersions(String current, String minimum) {
    final left = current
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final right = minimum
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final comparison = (i < left.length ? left[i] : 0).compareTo(
        i < right.length ? right[i] : 0,
      );
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
