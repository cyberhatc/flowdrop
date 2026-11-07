import 'dart:convert';
import 'dart:io';

import '../../core/security/trust_store.dart';

/// Trust store backed by a small JSON file in the app support directory.
///
/// A JSON file (instead of secure storage) is intentional: fingerprints and
/// display names are public, and the file is much easier to debug.
class JsonTrustStore implements TrustStore {
  JsonTrustStore(this.file);

  final File file;
  Map<String, TrustedDevice>? _cache;

  Future<Map<String, TrustedDevice>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final devices = <String, TrustedDevice>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List<dynamic>) {
          for (final entry in decoded) {
            if (entry is Map<String, dynamic>) {
              final device = TrustedDevice.fromJson(entry);
              devices[device.fingerprint] = device;
            }
          }
        }
      }
    } on Object {
      // A broken file must not lock the user out of the app.
    }
    _cache = devices;
    return devices;
  }

  Future<void> _flush() async {
    final devices = _cache ?? {};
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(devices.values.map((device) => device.toJson()).toList()),
      flush: true,
    );
  }

  @override
  Future<List<TrustedDevice>> all() async =>
      (await _load()).values.toList(growable: false);

  @override
  Future<bool> isTrusted(String fingerprint) async =>
      (await _load()).containsKey(fingerprint);

  @override
  Future<void> trust(TrustedDevice device) async {
    final devices = await _load();
    devices[device.fingerprint] = device;
    await _flush();
  }

  @override
  Future<void> forget(String fingerprint) async {
    final devices = await _load();
    devices.remove(fingerprint);
    await _flush();
  }
}
