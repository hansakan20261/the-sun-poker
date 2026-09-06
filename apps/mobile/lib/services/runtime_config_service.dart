import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'api_service.dart';

class RuntimeConfigService {
  static const int supportedSchemaVersion = 1;
  static const String _cacheKey = 'runtime_public_config_v1';
  static const String _etagKey = 'runtime_public_config_etag_v1';

  static Map<String, dynamic>? _value;
  static Map<String, dynamic>? _payload;
  static String? _etag;

  static Future<Map<String, dynamic>> load({bool force = false}) async {
    if (!force && _value != null) return _value!;
    final prefs = await SharedPreferences.getInstance();
    final cachedBody = prefs.getString(_cacheKey);
    _etag = prefs.getString(_etagKey);

    try {
      final response = await ApiService.getRaw(
        '/settings/public-config?schemaVersion=$supportedSchemaVersion&appVersion=${AppConfig.appVersion}',
        headers: {'If-None-Match': ?_etag},
      );
      if (response.statusCode == 304 && cachedBody != null) {
        _applyPayload(jsonDecode(cachedBody) as Map<String, dynamic>);
        return _value!;
      }
      if (response.statusCode == 426) {
        throw StateError('Client config schema is not supported; update required');
      }
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode, 'Unable to load runtime config');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      _applyPayload(payload);
      _etag = response.headers['etag'] ?? payload['etag']?.toString();
      await prefs.setString(_cacheKey, response.body);
      if (_etag != null) await prefs.setString(_etagKey, _etag!);
      return _value!;
    } catch (error) {
      if (error is StateError) rethrow;
      if (cachedBody != null) {
        _applyPayload(jsonDecode(cachedBody) as Map<String, dynamic>);
        return _value!;
      }
      rethrow;
    }
  }

  static void _applyPayload(Map<String, dynamic> payload) {
    final schema = int.tryParse(payload['schema_version']?.toString() ?? '');
    if (schema != supportedSchemaVersion) {
      throw StateError('Unsupported runtime config schema: $schema');
    }
    _payload = payload;
    final values = payload['values'] is Map<String, dynamic>
        ? payload['values'] as Map<String, dynamic>
        : <String, dynamic>{};
    _value = <String, dynamic>{};
    for (final section in [
      'app_control',
      'game_runtime',
      'notification_policy',
      'app_background',
      'room_defaults',
    ]) {
      final sectionValue = values[section];
      if (sectionValue is Map) {
        _value!.addAll(Map<String, dynamic>.from(sectionValue));
      }
    }
    AppConfig.httpTimeoutSeconds = integer('http_timeout_sec');
    AppConfig.healthCheckTimeoutSeconds = integer('health_check_timeout_sec');
    ApiService.configureRuntime(retryAttempts: integer('api_retry_attempts'));
  }

  static Map<String, dynamic>? get payload => _payload;
  static String? get etag => _etag;
  static dynamic optionalValue(String key) => _value?[key];

  static dynamic value(String key) {
    final value = _value?[key];
    if (value == null) throw StateError('Missing runtime config: $key');
    return value;
  }

  static String string(String key) => value(key).toString();

  static int integer(String key) => number(key).toInt();

  static double number(String key) {
    final raw = _value?[key];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    if (value == null) throw StateError('Missing runtime config: $key');
    return value;
  }

  static Future<void> clear() async {
    _value = null;
    _payload = null;
    _etag = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_etagKey);
  }
}
