import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// แปลงค่าจาก API ให้เป็น int เสมอ (DB ส่ง BIGINT มาเป็น String)
int toInt(dynamic v, [int fallback = 0]) =>
    v is int ? v : int.tryParse(v.toString()) ?? fallback;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}

class ApiService {
  static String? _token;
  static String? _userId;
  static int _apiRetryAttempts = 0;

  static void configureRuntime({required int retryAttempts}) {
    if (retryAttempts < 0) {
      throw StateError('api_retry_attempts must be non-negative');
    }
    _apiRetryAttempts = retryAttempts;
  }

  static Future<http.Response> _execute(
    Future<http.Response> Function() request, {
    bool retry = false,
  }) async {
    final maxAttempts = retry ? _apiRetryAttempts + 1 : 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request();
      } on SocketException {
        if (attempt == maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt == maxAttempts) rethrow;
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      }
    }
    throw StateError('unreachable');
  }

  static void setToken(String token) {
    _token = token;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = utf8.decode(base64Url.decode(normalized));
        final map = jsonDecode(decoded);
        _userId = map['id']?.toString();
      }
    } catch (_) {}
    // Save to local storage
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('auth_token', token);
    });
  }

  static void clearToken() {
    _token = null;
    _userId = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('auth_token');
    });
  }

  /// Load saved token from local storage — call on app startup
  static Future<bool> loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('auth_token');
    if (saved == null || saved.isEmpty) return false;
    setToken(saved);
    // Verify token is still valid
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.authBaseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $saved'},
      );
      if (res.statusCode == 200) return true;
      clearToken();
      return false;
    } catch (_) {
      clearToken();
      return false;
    }
  }

  static String? get token => _token;
  static String? get currentUserId => _userId;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Check if the server is reachable
  static Future<bool> checkServerHealth() async {
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.authBaseUrl}/health'))
          .timeout(AppConfig.healthCheckTimeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get current server info for debugging
  static Map<String, String> get serverInfo => {
    'authUrl': AppConfig.authBaseUrl,
    'apiUrl': AppConfig.apiBaseUrl,
    'gameSocketUrl': AppConfig.gameSocketUrl,
    'useProduction': AppConfig.useProduction.toString(),
  };

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? baseUrl,
    bool idempotent = false,
  }) async {
    try {
      final res = await _execute(
        () => http
            .post(
              Uri.parse('${baseUrl ?? AppConfig.apiBaseUrl}$path'),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(AppConfig.httpTimeout),
        retry: idempotent,
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, data['error'] ?? 'Request failed');
      }
      return data;
    } on SocketException catch (e) {
      throw NetworkException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.message}');
    } on http.ClientException catch (e) {
      throw NetworkException('เครือข่ายมีปัญหา: ${e.message}');
    } on TimeoutException {
      throw NetworkException('คำขอหมดเวลา');
    }
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    String? baseUrl,
  }) async {
    try {
      final res = await _execute(
        () => http
            .get(
              Uri.parse('${baseUrl ?? AppConfig.apiBaseUrl}$path'),
              headers: _headers,
            )
            .timeout(AppConfig.httpTimeout),
        retry: true,
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, data['error'] ?? 'Request failed');
      }
      return data;
    } on SocketException catch (e) {
      throw NetworkException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.message}');
    } on http.ClientException catch (e) {
      throw NetworkException('เครือข่ายมีปัญหา: ${e.message}');
    } on TimeoutException {
      throw NetworkException('คำขอหมดเวลา');
    }
  }

  static Future<http.Response> getRaw(
    String path, {
    Map<String, String>? headers,
    String? baseUrl,
  }) async {
    return _execute(
      () => http
          .get(
            Uri.parse('${baseUrl ?? AppConfig.apiBaseUrl}$path'),
            headers: {..._headers, ...?headers},
          )
          .timeout(AppConfig.httpTimeout),
      retry: true,
    );
  }

  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? baseUrl,
  }) async {
    try {
      final res = await _execute(
        () => http
            .put(
              Uri.parse('${baseUrl ?? AppConfig.apiBaseUrl}$path'),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(AppConfig.httpTimeout),
        retry: true,
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, data['error'] ?? 'Request failed');
      }
      return data;
    } on SocketException catch (e) {
      throw NetworkException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.message}');
    } on http.ClientException catch (e) {
      throw NetworkException('เครือข่ายมีปัญหา: ${e.message}');
    } on TimeoutException {
      throw NetworkException('คำขอหมดเวลา');
    }
  }

  // Auth
  static Future<Map<String, dynamic>> login(String username, String password) =>
      post('/auth/login', {
        'username': username,
        'password': password,
      }, baseUrl: AppConfig.authBaseUrl);

  static Future<Map<String, dynamic>> register(
    String username,
    String password,
    String? email,
  ) => post('/auth/register', {
    'username': username,
    'password': password,
    'email': email,
  }, baseUrl: AppConfig.authBaseUrl);

  static Future<void> logout() async {
    try {
      await post('/auth/logout', {}, baseUrl: AppConfig.authBaseUrl);
    } finally {
      clearToken();
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final data = await get('/profile/me');
    // balance อาจมาเป็น String — แปลงเป็น int
    if (data['profile'] != null) {
      data['profile']['balance'] =
          int.tryParse(data['profile']['balance'].toString()) ?? 0;
      data['profile']['total_games'] =
          int.tryParse(data['profile']['total_games'].toString()) ?? 0;
      data['profile']['total_wins'] =
          int.tryParse(data['profile']['total_wins'].toString()) ?? 0;
      data['profile']['hands_played'] =
          int.tryParse(data['profile']['hands_played'].toString()) ?? 0;
    }
    return data;
  }

  static Future<Map<String, dynamic>> getBalance() async {
    final data = await get('/wallet/balance');
    // balance อาจมาเป็น String จาก DB — แปลงเป็น int เสมอ
    data['balance'] = int.tryParse(data['balance'].toString()) ?? 0;
    return data;
  }

  static Future<Map<String, dynamic>> getTransactions({
    int limit = 100,
    String? type,
  }) {
    String params = 'limit=$limit';
    if (type != null) params += '&type=$type';
    return get('/wallet/transactions?$params');
  }

  static Future<Map<String, dynamic>> getGameTypes() =>
      get('/tables/game-types');
  static Future<Map<String, dynamic>> getTables({String? gameTypeId}) =>
      get('/tables${gameTypeId != null ? "?game_type_id=$gameTypeId" : ""}');
  static Future<Map<String, dynamic>> getClubs() => get('/clubs');
  static Future<Map<String, dynamic>> getMyClubs() => get('/clubs/my');
  static Future<Map<String, dynamic>> createClub(
    String name, {
    String? description,
  }) => post('/clubs', {'name': name, 'description': description ?? ''});
  static Future<Map<String, dynamic>> joinClub(String clubId) =>
      post('/clubs/$clubId/join', {});
  static Future<Map<String, dynamic>> leaveClub(String clubId) =>
      post('/clubs/$clubId/leave', {});
  static Future<Map<String, dynamic>> getClubMembers(String clubId) =>
      get('/clubs/$clubId/members');
  static Future<Map<String, dynamic>> getClubTables(String clubId) =>
      get('/clubs/$clubId/tables');
  static Future<Map<String, dynamic>> createClubTable(
    String clubId,
    Map<String, dynamic> data,
  ) => post('/clubs/$clubId/tables', data);
  static Future<Map<String, dynamic>> getShopItems({String? category}) =>
      get('/shop/items${category != null ? "?category=$category" : ""}');
  static Future<Map<String, dynamic>> getInventory() => get('/shop/inventory');
  static Future<Map<String, dynamic>> getHandHistory({
    int limit = 20,
    String? tableId,
  }) => get(
    '/tables/hand-history?limit=$limit${tableId != null ? "&table_id=$tableId" : ""}',
  );
  static Future<Map<String, dynamic>> getHandDetail(String handId) =>
      get('/tables/hand-history/$handId');

  // Daily Bonus
  static Future<Map<String, dynamic>> getDailyBonusStatus() =>
      get('/daily-bonus/status');
  static Future<Map<String, dynamic>> claimDailyBonus() =>
      post('/daily-bonus/claim', {});

  // Practice
  static Future<Map<String, dynamic>> createPracticeTable(
    String gameTypeSlug, {
    int? smallBlind,
    int? bigBlind,
    int? minBuyIn,
    int? maxBuyIn,
  }) => post('/practice/create', {
    'game_type_slug': gameTypeSlug,
    'small_blind': ?smallBlind,
    'big_blind': ?bigBlind,
    'min_buy_in': ?minBuyIn,
    'max_buy_in': ?maxBuyIn,
  });
  static Future<Map<String, dynamic>> getPracticeStatus() =>
      get('/practice/status');

  // Profile management
  static Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? bio,
    String? locale,
    String? avatarUrl,
  }) {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (bio != null) body['bio'] = bio;
    if (locale != null) body['locale'] = locale;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    return put('/profile/me', body);
  }

  static Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
  ) => put('/profile/change-password', {
    'current_password': currentPassword,
    'new_password': newPassword,
  });
  static Future<Map<String, dynamic>> deleteAccount(String password) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/profile/delete-account'),
      headers: _headers,
      body: jsonEncode({'password': password}),
    );
    return jsonDecode(res.body);
  }

  /// Upload avatar image file and return the URL
  static Future<String> uploadAvatar(File imageFile) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/profile/avatar');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(
      await http.MultipartFile.fromPath('avatar', imageFile.path),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    final data = jsonDecode(body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data['avatar_url'] ?? data['url'] ?? '';
    }
    throw ApiException(response.statusCode, data['error'] ?? 'Upload failed');
  }
}
