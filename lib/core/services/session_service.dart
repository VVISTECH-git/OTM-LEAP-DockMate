import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Single source of truth for the current user session.
/// Auth token is stored in encrypted secure storage (Android Keystore).
/// Non-sensitive preferences remain in SharedPreferences.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  SharedPreferences? _prefs;
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ─── Write ────────────────────────────────────────────────────────────────

  Future<void> saveSession({
    required String instanceUrl,
    required String authHeader,
    required String userId,
  }) async {
    final p      = await _p;
    final parts  = userId.split('.');
    final domain = parts.isNotEmpty ? parts[0] : AppConstants.defaultDomain;
    final user   = parts.length > 1 ? parts.sublist(1).join('.') : userId;

    // Auth token → encrypted Android Keystore
    await _secure.write(key: AppConstants.prefAuthHeader, value: authHeader);

    // Everything else → SharedPreferences (not sensitive)
    await p.setString(AppConstants.prefInstanceUrl, instanceUrl);
    await p.setString(AppConstants.prefUserId, userId);
    await p.setString(AppConstants.prefUser, user);
    await p.setString(AppConstants.prefDomain, domain);
  }

  Future<void> setLastTeam(String team) async =>
      (await _p).setString(AppConstants.prefLastTeam, team);

  // ─── Read ─────────────────────────────────────────────────────────────────

  Future<String> get instanceUrl async =>
      (await _p).getString(AppConstants.prefInstanceUrl) ??
      AppConstants.defaultInstanceUrl;

  // Auth token read from encrypted secure storage
  Future<String> get authHeader async =>
      await _secure.read(key: AppConstants.prefAuthHeader) ?? '';

  Future<String> get domain async =>
      (await _p).getString(AppConstants.prefDomain) ??
      AppConstants.defaultDomain;

  Future<String> get user async =>
      (await _p).getString(AppConstants.prefUser) ?? '';

  Future<String> get userId async =>
      (await _p).getString(AppConstants.prefUserId) ?? '';

  Future<String> get lastTeam async =>
      (await _p).getString(AppConstants.prefLastTeam) ?? 'inbound';

  Future<bool> get isLoggedIn async =>
      (await authHeader).isNotEmpty;

  // ─── Clear ────────────────────────────────────────────────────────────────

  Future<void> clear() async {
    final p = await _p;

    // Delete auth token from secure storage
    await _secure.delete(key: AppConstants.prefAuthHeader);

    // Remove everything else from SharedPreferences
    await Future.wait([
      p.remove(AppConstants.prefInstanceUrl),
      p.remove(AppConstants.prefUserId),
      p.remove(AppConstants.prefUser),
      p.remove(AppConstants.prefDomain),
      p.remove(AppConstants.prefLastTeam),
    ]);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String buildBasicAuth(String userId, String password) {
    final encoded = base64Encode(utf8.encode('$userId:$password'));
    return 'Basic $encoded';
  }
}