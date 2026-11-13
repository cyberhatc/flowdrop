import 'dart:async';
import 'dart:io';

import '../protocol/constants.dart';
import '../protocol/device.dart';
import 'mdns_discovery.dart';
import 'peer.dart';
import 'udp_beacon.dart';

/// Runs every discovery mechanism and funnels results into one registry.
class DiscoveryService {
  DiscoveryService({
    required this.deviceInfo,
    PeerRegistry? registry,
    this.broadcast = true,
    this.useMdns = true,
    this.isPaired,
    this.onError,
  }) : registry = registry ?? PeerRegistry();

  final DeviceInfo Function() deviceInfo;
  final PeerRegistry registry;
  final bool broadcast;
  final bool useMdns;

  /// Tells discovery whether a device id is already paired, so its peer entry
  /// is pinned and never pruned.
  final bool Function(String deviceId)? isPaired;
  final void Function(Object error)? onError;

  UdpBeaconService? _udp;
  MdnsDiscoveryService? _mdns;
  bool _running = false;

  bool get isRunning => _running;
  bool get udpRunning => _udp?.isRunning ?? false;
  bool get mdnsRunning => _mdns?.isRunning ?? false;

  Stream<List<Peer>> get peers => registry.peers;
  List<Peer> get nearby => registry.snapshot;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    if (broadcast) {
      final udp = UdpBeaconService(
        deviceInfo: deviceInfo,
        onDevice: (device, source) => registry.upsert(
          device.copyWith(addresses: _mergeAddress(device.addresses, source)),
          source: PeerSource.udp,
          pinned: isPaired?.call(device.id) ?? false,
        ),
        onError: onError,
      );
      _udp = udp;
      try {
        await udp.start();
      } on Object {
        // Discovery is best effort; the UI still supports QR/manual connect.
        _udp = null;
      }
    }
    if (useMdns) {
      final mdns = MdnsDiscoveryService(
        onDevice: (device) => registry.upsert(
          device,
          source: PeerSource.mdns,
          pinned: isPaired?.call(device.id) ?? false,
        ),
        onError: onError,
      );
      _mdns = mdns;
      await mdns.start();
    }
  }

  List<String> _mergeAddress(List<String> existing, InternetAddress source) {
    final address = source.address;
    if (existing.contains(address)) return existing;
    return [...existing, address];
  }

  void addManual(DeviceInfo device) {
    registry.upsert(
      device,
      source: PeerSource.manual,
      pinned: isPaired?.call(device.id) ?? false,
    );
  }

  void addFromQr(DeviceInfo device) {
    registry.upsert(device, source: PeerSource.qr, pinned: true);
  }

  /// Adds a paired device from the trust store, keeping its persisted
  /// `lastSeen` so the UI can show it as offline until a probe succeeds.
  void seedPaired(DeviceInfo device, {DateTime? lastSeen}) {
    registry.seedPaired(device, lastSeen: lastSeen);
  }

  /// Refreshes a paired device after a successful probe.
  void markPairedOnline(DeviceInfo device) {
    registry.upsert(device, source: PeerSource.paired, pinned: true);
  }

  void removePaired(String deviceId) {
    registry.remove(deviceId);
  }

  Future<void> refresh() async {
    await _udp?.sendOnce();
  }

  Future<void> stop() async {
    await _udp?.stop();
    await _mdns?.stop();
    _udp = null;
    _mdns = null;
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    await registry.dispose();
  }
}

/// Hints shown when discovery finds nothing: AP isolation and firewall are the
/// two most common reasons on real networks.
class DiscoveryDiagnostics {
  static const String apIsolationHint =
      'You are on the same Wi-Fi but devices cannot see each other. Guest '
      'networks often block device-to-device traffic. Try a hotspot or scan a QR code.';
  static const String firewallHint =
      'No peers found. Allow FlowDrop through your firewall (TCP ${FlowDropProtocol.defaultPort}, UDP ${FlowDropProtocol.discoveryPort}).';
  static const String iosBackgroundHint =
      'On iOS the server only runs while FlowDrop is open. Keep the app in the foreground.';
}
