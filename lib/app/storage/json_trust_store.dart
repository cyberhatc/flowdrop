import 'dart:convert';
import 'dart:io';

import '../../core/security/trust_store.dart';

/// Trust store backed by a small JSON file in the app support directory.
///
/// A JSON file (instead of secure storage) is intentional: fingerprints and
/// display names are public, and the file is much easier to debug.
///
/// Writes are serialised and go through a temporary file so a crash, a full
/// disk or two concurrent reconnects cannot leave a half-written list behind.
/// Losing this file would mean having to pair every device again, which is
/// exactly what persistent reconnection must never require.
class JsonTrustStore implements TrustStore {
  JsonTrustStore(this.file);

  final File file;
  Map<String, TrustedDevice>? _cache;
  Future<void> _writes = Future<void>.value();

  File get _temp => File('${file.path}.tmp');
  File get _backup => File('${file.path}.bak');

  Future<Map<String, TrustedDevice>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final devices = await _read(file) ?? await _read(_backup) ?? {};
    _cache = devices;
    return devices;
  }

  Future<Map<String, TrustedDevice>?> _read(File source) async {
    try {
      if (!await source.exists()) return null;
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! List<dynamic>) return null;
      final devices = <String, TrustedDevice>{};
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          final device = TrustedDevice.fromJson(entry);
          devices[device.fingerprint] = device;
        }
      }
      return devices;
    } on Object {
      // A broken file must not lock the user out of the app.
      return null;
    }
  }

  Future<void> _flush() {
    final next = _writes.then((_) => _writeNow());
    // Keep the chain alive even if one write fails.
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeNow() async {
    final devices = _cache ?? {};
    await file.parent.create(recursive: true);
    await _temp.writeAsString(
      jsonEncode(devices.values.map((device) => device.toJson()).toList()),
      flush: true,
    );
    try {
      if (await file.exists()) {
        await file.copy(_backup.path);
        await file.delete();
      }
      await _temp.rename(file.path);
    } on FileSystemException {
      // If the swap fails, the previous file (or its backup) is still intact.
    }
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
