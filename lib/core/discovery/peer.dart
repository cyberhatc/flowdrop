import 'dart:async';

import '../protocol/constants.dart';
import '../protocol/device.dart';

/// How a peer was discovered. Shown as a small badge in the UI.
enum PeerSource { udp, mdns, qr, manual }

class Peer {
  const Peer({
    required this.device,
    required this.lastSeen,
    required this.source,
  });

  final DeviceInfo device;
  final DateTime lastSeen;
  final PeerSource source;

  bool get isExpired =>
      DateTime.now().difference(lastSeen) > FlowDropProtocol.peerTimeout;

  Peer touched({PeerSource? source}) => Peer(
        device: device,
        lastSeen: DateTime.now(),
        source: source ?? this.source,
      );
}

/// Keeps track of devices seen recently and exposes a sorted, de-duplicated
/// list to the UI.
///
/// Identity is the device id, not the IP: a peer that roams between Wi-Fi and
/// hotspot keeps one radar bubble.
class PeerRegistry {
  PeerRegistry({Duration? tick})
      : _tick = tick ?? const Duration(seconds: 2) {
    _timer = Timer.periodic(_tick, (_) => _prune());
  }

  final Duration _tick;
  late final Timer _timer;
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();

  Stream<List<Peer>> get peers => _controller.stream;
  List<Peer> get snapshot => _sorted();

  void upsert(DeviceInfo device, {required PeerSource source}) {
    final existing = _peers[device.id];
    final merged = _merge(existing?.device, device);
    _peers[device.id] = Peer(
      device: merged,
      lastSeen: DateTime.now(),
      source: source,
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
      final byName = a.device.name.toLowerCase().compareTo(
            b.device.name.toLowerCase(),
          );
      return byName != 0 ? byName : a.device.id.compareTo(b.device.id);
    });
    return List.unmodifiable(list);
  }

  DeviceInfo _merge(DeviceInfo? old, DeviceInfo fresh) {
    if (old == null) return fresh;
    final addresses = <String>{...old.addresses, ...fresh.addresses}.toList();
    return fresh.copyWith(addresses: addresses);
  }

  Future<void> dispose() async {
    _timer.cancel();
    await _controller.close();
  }
}
