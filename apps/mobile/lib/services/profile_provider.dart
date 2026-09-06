import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Centralized profile state — single source of truth for all screens.
/// Call [load] once at app start, then [update] when user edits profile.
/// Listen via [addListener] or use [ValueListenableBuilder] with [notifier].
class ProfileProvider extends ChangeNotifier {
  static final ProfileProvider instance = ProfileProvider._();
  ProfileProvider._();

  Map<String, dynamic>? _profile;
  int _balance = 0;
  String? _savedAvatarPath; // persisted local avatar path

  Map<String, dynamic>? get profile => _profile;
  int get balance => _balance;

  String get displayName =>
      _profile?['display_name'] ?? _profile?['username'] ?? '';
  String get username => _profile?['username'] ?? '';
  String? get avatarUrl => _profile?['avatar_url'] as String?;
  String get bio => _profile?['bio'] as String? ?? '';

  /// Returns the best available image provider for avatar
  ImageProvider? get avatarImage {
    // 1. Server avatar URL (http)
    if (avatarUrl != null &&
        avatarUrl!.isNotEmpty &&
        avatarUrl!.startsWith('http')) {
      return NetworkImage(avatarUrl!);
    }
    // 2. Local saved avatar (persisted file — from data URL or direct pick)
    if (_savedAvatarPath != null && File(_savedAvatarPath!).existsSync()) {
      return FileImage(File(_savedAvatarPath!));
    }
    return null;
  }

  /// Load profile from server + restore saved avatar path
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedAvatarPath = prefs.getString('avatar_local_path');

      // Load from server
      final results = await Future.wait([
        ApiService.getProfile(),
        ApiService.getBalance(),
      ]);
      _profile = results[0]['profile'];
      _balance = toInt(results[1]['balance']);

      // If server has avatar_url as data URL → decode and save to local file
      final serverAvatar = _profile?['avatar_url'] as String?;
      if (serverAvatar != null && serverAvatar.startsWith('data:image')) {
        try {
          final base64Str = serverAvatar.split(',')[1];
          final bytes = base64Decode(base64Str);
          final appDir = await getApplicationDocumentsDirectory();
          final file = File('${appDir.path}/avatar.jpg');
          await file.writeAsBytes(bytes);
          _savedAvatarPath = file.path;
          await prefs.setString('avatar_local_path', file.path);
          debugPrint('✅ Decoded server data URL avatar → local file');
        } catch (e) {
          debugPrint('Failed to decode data URL avatar: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('ProfileProvider.load error: $e');
    }
  }

  /// Refresh just the balance
  Future<void> refreshBalance() async {
    try {
      final b = await ApiService.getBalance();
      _balance = toInt(b['balance']);
      if (_profile != null) _profile!['balance'] = _balance;
      notifyListeners();
    } catch (_) {}
  }

  /// Update profile locally + persist + try server
  Future<void> update({
    String? displayName,
    String? bio,
    File? avatarFile,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Update local state immediately
    if (displayName != null && displayName.isNotEmpty) {
      _profile?['display_name'] = displayName;
      await prefs.setString('display_name', displayName);
    }
    if (bio != null) {
      _profile?['bio'] = bio;
    }

    // Save avatar to persistent app directory
    if (avatarFile != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final savedFile = await avatarFile.copy('${appDir.path}/avatar.jpg');
        _savedAvatarPath = savedFile.path;
        await prefs.setString('avatar_local_path', savedFile.path);
      } catch (e) {
        debugPrint('Failed to save avatar locally: $e');
        _savedAvatarPath = avatarFile.path;
      }
    }
    notifyListeners(); // notify all screens immediately

    // Try server update
    String? uploadedAvatarUrl;
    if (avatarFile != null) {
      try {
        uploadedAvatarUrl = await ApiService.uploadAvatar(avatarFile);
        _profile?['avatar_url'] = uploadedAvatarUrl;
      } catch (e) {
        debugPrint('Avatar upload failed: $e — converting to data URL');
        // Fallback: convert to base64 data URL and store directly
        try {
          final bytes = await avatarFile.readAsBytes();
          uploadedAvatarUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _profile?['avatar_url'] = uploadedAvatarUrl;
        } catch (e2) {
          debugPrint('Base64 conversion failed: $e2');
        }
      }
    }

    try {
      await ApiService.updateProfile(
        displayName: displayName,
        bio: bio,
        avatarUrl: uploadedAvatarUrl,
      );
      debugPrint(
        '✅ Profile updated on server (avatar: ${uploadedAvatarUrl != null ? "sent" : "null"})',
      );
    } catch (e) {
      debugPrint('Server profile update failed: $e — local state kept');
    }

    notifyListeners();
  }
}
