/// Central configuration for the app.
/// Change these URLs to your production server when deploying.
class AppConfig {
  // ── Toggle: true = production server, false = local dev ──
  // Set to true to connect to real server (129.212.236.4)
  // Set to false for local development (localhost)
  static const bool useProduction = true;

  // ── Environment override (for CI/CD or testing) ──
  static const String _envHost = String.fromEnvironment(
    'SERVER_HOST',
    defaultValue: '',
  );

  static const String _prodHost = 'http://129.212.236.4';
  static const String _localHost = 'http://localhost';

  /// Effective host: env override > production toggle > localhost
  static String get _host {
    if (_envHost.isNotEmpty) return _envHost;
    return useProduction ? _prodHost : _localHost;
  }

  static const String _envAuthBaseUrl = String.fromEnvironment('AUTH_BASE_URL');
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _envGameSocketUrl = String.fromEnvironment('GAME_SOCKET_URL');

  // ── Service URLs ──
  static String get authBaseUrl =>
      _envAuthBaseUrl.isNotEmpty ? _envAuthBaseUrl : '$_host:3001';
  static String get apiBaseUrl =>
      _envApiBaseUrl.isNotEmpty ? _envApiBaseUrl : '$_host:3002';
  static String get gameSocketUrl =>
      _envGameSocketUrl.isNotEmpty ? _envGameSocketUrl : '$_host:3003';

  // ── App Info ──
  static const String appName = 'THE SUN POKER';
  static const String appVersion = '1.0.0';

  // ── Timeouts ──
  static const int _defaultHttpTimeoutSeconds = int.fromEnvironment(
    'APP_HTTP_TIMEOUT_SECONDS',
    defaultValue: 30,
  );
  static const int _defaultHealthCheckTimeoutSeconds = int.fromEnvironment(
    'APP_HEALTH_CHECK_TIMEOUT_SECONDS',
    defaultValue: 5,
  );
  static int httpTimeoutSeconds = _defaultHttpTimeoutSeconds;
  static int healthCheckTimeoutSeconds = _defaultHealthCheckTimeoutSeconds;
  static Duration get httpTimeout => Duration(seconds: httpTimeoutSeconds);
  static Duration get healthCheckTimeout =>
      Duration(seconds: healthCheckTimeoutSeconds);

  // ── Debug ──
  static const bool enableLogging = true;
}
