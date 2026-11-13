import 'dart:async';

import '../protocol/constants.dart';
import '../protocol/device.dart';

/// How a peer was discovered. Shown as a small badge in the UI.
enum PeerSource {
  udp,
  mdns,
  qr,
  manual,

  /// Loaded from the trust store: a device this app already paired with, even
  /// when it is not currently announcing itself.
  paired,
}

class Peer {
  const Peer({
    required this.device,
    required this.lastSeen,
    required this.source,
    this.pinned = false,
  });

  final DeviceInfo device;
  final DateTime lastSeen;
  final PeerSource source;

  /// Paired devices are pinned: they never disappear from the registry just
  /// because they stopped beaconing. The UI dims them and probes them instead.
  final bool pinned;

  /// True when the device answered (a beacon or a probe) recently.
  bool get isLive =>
      DateTime.now().difference(lastSeen) <= FlowDropProtocol.peerTimeout;

  bool get isExpired => !pinned && !isLive;

  Peer touched({PeerSource? source}) => Peer(
    device: device,
    lastSeen: DateTime.now(),
    source: source ?? this.source,
    pinned: pinned,
  );
}

/// Keeps track of devices seen recently and exposes a sorted, de-duplicated
/// list to the UI.
///
/// Identity is the device id, not the IP: a peer that roams between Wi-Fi and
/// hotspot keeps one radar bubble. Pinned (paired) devices are never pruned,
/// which is what makes reconnecting after a restart trivial.
class PeerRegistry {
  PeerRegistry({Duration? tick}) : _tick = tick ?? const Duration(seconds: 2) {
    _timer = Timer.periodic(_tick, (_) => _prune());
  }

  final Duration _tick;
  late final Timer _timer;
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();

  Stream<List<Peer>> get peers => _controller.stream;
  List<Peer> get snapshot => _sorted();

  void upsert(
    DeviceInfo device, {
    required PeerSource source,
    bool pinned = false,
    DateTime? lastSeen,
  }) {
    final existing = _peers[device.id];
    final merged = _merge(existing?.device, device);
    _peers[device.id] = Peer(
      device: merged,
      lastSeen: lastSeen ?? DateTime.now(),
      source: source,
      // A pinned peer stays pinned even if a later beacon arrives without the
      // flag (discovery has no access to the trust store).
      pinned: pinned || (existing?.pinned ?? false),
    );
    _emit();
  }

  /// Adds a paired device without claiming it is online. [lastSeen] is the
  /// persisted timestamp, so an offline device starts dimmed in the UI.
  void seedPaired(DeviceInfo device, {DateTime? lastSeen}) {
    final existing = _peers[device.id];
    if (existing == null) {
      _peers[device.id] = Peer(
        device: device,
        lastSeen: lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0),
        source: PeerSource.paired,
        pinned: true,
      );
      _emit();
      return;
    }
    _peers[device.id] = Peer(
      device: _merge(existing.device, device),
      lastSeen: existing.lastSeen,
      source: existing.source,
      pinned: true,
    );
    _emit();
  }

  void remove(String deviceId) {
    if (_peers.remove(deviceId) != null) _emit();
  }

  void clear() {
    _peers.clear();
    _emit();
  }

  void _prune() {
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.isExpired);
    if (_peers.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  List<Peer> _sorted() {
    final list = _peers.values.toList();
    list.sort((a, b) {
      // Live devices first, then paired-but-offline, then the rest.
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      final byName = a.device.name.toLowerCase().compareTo(
        b.device.name.toLowerCase(),
      );
      return byName != 0 ? byName : a.device.id.compareTo(b.device.id);
    });
    return List.unmodifiable(list);
  }

  DeviceInfo _merge(DeviceInfo? old, DeviceInfo fresh) {
    if (old == null) return fresh;
    // Freshest addresses first, then remembered ones (Wi-Fi roam), capped so
    // a long-lived install cannot accumulate stale addresses forever.
    final addresses = <String>{
      ...fresh.addresses,
      ...old.addresses,
    }.take(8).toList(growable: false);
    return fresh.copyWith(addresses: addresses);
  }

  Future<void> dispose() async {
    _timer.cancel();
    await _controller.close();
  }
}
