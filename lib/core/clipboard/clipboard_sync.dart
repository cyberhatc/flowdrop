import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../protocol/constants.dart';

/// One clipboard payload observed either locally or from a peer.
class ClipboardEvent {
  const ClipboardEvent({
    required this.data,
    required this.originDeviceId,
    required this.createdAt,
    this.originFingerprint,
  });

  /// The clipboard contents as text.
  final String data;

  /// Device id that produced the value. Events from remote devices carry
  /// the sender's id; locally produced events carry our own id.
  final String originDeviceId;

  /// Sender certificate fingerprint, when the event came from a peer.
  final String? originFingerprint;

  final DateTime createdAt;

  /// Stable content hash used for loop prevention.
  String get hash => clipboardHash(data);

  bool get isEmpty => data.trim().isEmpty;
  bool get isTooLarge =>
      utf8.encode(data).length > FlowDropProtocol.maxTextBytes;
}

/// SHA-256 of [data] as lowercase hex.
String clipboardHash(String data) =>
    sha256.convert(utf8.encode(data)).toString();

/// Loop-prevention guard for clipboard sync.
///
/// A remote clipboard value applied to this device's clipboard must never be
/// re-pushed by the local watcher — otherwise two devices ping-pong forever.
/// The same content hash remembered from remote events is suppressed for
/// [suppressionWindow]. A per-device toggle is not enough on its own: the
/// hash check is what makes sync safe home-and-back.
class ClipboardSyncGuard {
  ClipboardSyncGuard({
    this.suppressionWindow = const Duration(seconds: 60),
    this.maxRecentRemote = 32,
    int? maxBytes,
    this.localDeviceId = 'local',
  }) : _maxBytes = maxBytes ?? FlowDropProtocol.maxTextBytes;

  final Duration suppressionWindow;
  final int maxRecentRemote;
  final int _maxBytes;
  final String localDeviceId;

  /// Remote payloads seen recently: hash -> [createdAt].
  final Map<String, DateTime> _recentRemote = {};

  String? _lastLocalHash;

  /// Marks a payload that came from a peer so it is never re-pushed.
  void rememberRemote(ClipboardEvent event) {
    final now = event.createdAt;
    _recentRemote[event.hash] = now;
    // Evict the oldest entries beyond the cap.
    if (_recentRemote.length > maxRecentRemote) {
      final entries = _recentRemote.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in entries.take(
        _recentRemote.length - maxRecentRemote,
      )) {
        _recentRemote.remove(entry.key);
      }
    }
    _prune(now);
  }

  void _prune(DateTime now) {
    _recentRemote.removeWhere(
      (_, createdAt) => now.difference(createdAt) > suppressionWindow,
    );
  }

  /// Decides whether local clipboard content should be pushed to peers.
  ///
  /// Returns `true` when [data] is new, non-empty, under the size cap, not a
  /// recent remote value, and different from the last locally pushed value.
  bool shouldPush(String data, {DateTime? now}) {
    if (data.trim().isEmpty) return false;
    if (utf8.encode(data).length > _maxBytes) return false;
    final hash = clipboardHash(data);
    final at = now ?? DateTime.now();
    _prune(at);
    if (_recentRemote.containsKey(hash)) return false;
    if (_lastLocalHash == hash) return false;
    return true;
  }

  void markPushed(String data) {
    _lastLocalHash = clipboardHash(data);
  }

  bool isRemoteRecent(String data, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _prune(at);
    return _recentRemote.containsKey(clipboardHash(data));
  }

  /// Clears guards (e.g. when the toggle is switched off and back on).
  void reset() {
    _recentRemote.clear();
    _lastLocalHash = null;
  }
}
