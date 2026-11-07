import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/security/identity.dart';

/// Keeps the private identity material in the OS secure store.
///
/// Windows: DPAPI, macOS/iOS: Keychain, Android: Keystore-backed storage,
/// Linux: libsecret. Nothing here is ever written to shared preferences.
class SecureIdentityStore {
  SecureIdentityStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'flowdrop.identity.v1';

  final FlutterSecureStorage _storage;

  Future<DeviceIdentity?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DeviceIdentity.fromStorageJson(decoded);
    } on Object {
      // A corrupted record is treated as "no identity"; the caller generates a
      // fresh one. The old certificate is abandoned rather than trusted.
      return null;
    }
  }

  Future<void> save(DeviceIdentity identity) async {
    await _storage.write(key: _key, value: jsonEncode(identity.toStorageJson()));
  }

  Future<void> delete() async {
    await _storage.delete(key: _key);
  }
}
