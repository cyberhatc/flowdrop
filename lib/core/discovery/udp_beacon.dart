import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/constants.dart';
import '../protocol/device.dart';
import 'network_interfaces.dart';

/// UDP broadcast/multicast beacon.
///
/// This is the discovery path that always works when two devices share a
/// network: no avahi/Bonjour daemon, no permission prompts on most systems.
/// mDNS is a bonus, not a dependency.
class UdpBeaconService {
  UdpBeaconService({
    required this.deviceInfo,
    required this.onDevice,
    this.port = FlowDropProtocol.discoveryPort,
    this.interval = FlowDropProtocol.beaconInterval,
    this.onError,
  });

  final DeviceInfo Function() deviceInfo;
  final void Function(DeviceInfo device, InternetAddress source) onDevice;
  final int port;
  final Duration interval;
  final void Function(Object error)? onError;

  RawDatagramSocket? _socket;
  Timer? _timer;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _sending = false;

  static const _multicastAddress = '239.255.42.99';

  bool get isRunning => _socket != null;

  Future<void> start({bool announce = true}) async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        ttl: 1,
      );
      socket.broadcastEnabled = true;
      _socket = socket;

      // Join the multicast group on every interface we can reach. Failures are
      // non-fatal: the broadcast path may still work.
      final group = InternetAddress(_multicastAddress);
      try {
        socket.joinMulticast(group);
      } on Object catch (error) {
        onError?.call(error);
      }
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final interface in interfaces) {
          try {
            socket.joinMulticast(group, interface);
          } on Object catch (error) {
            onError?.call(error);
          }
        }
      } on Object catch (error) {
        onError?.call(error);
      }

      _subscription = socket.listen((event) => _handleEvent(socket, event));
      if (announce) {
        _timer = Timer.periodic(interval, (_) => sendOnce());
        await sendOnce();
      }
    } on Object catch (error) {
      onError?.call(error);
      rethrow;
    }
  }

  /// Announces this device once. Also used by "refresh".
  Future<void> sendOnce() async {
    final socket = _socket;
    if (socket == null) return;
    if (_sending) return;
    _sending = true;
    try {
      final info = deviceInfo();
      final payload = jsonEncode({'t': 'fd-beacon', 'info': info.toJson()});
      final bytes = utf8.encode(payload);
      if (bytes.length > 60000) throw StateError('Beacon payload too large');

      // Global broadcast (works on most home networks).
      socket.send(bytes, InternetAddress('255.255.255.255'), port);
      // Multicast (works where global broadcast is filtered).
      socket.send(bytes, InternetAddress(_multicastAddress), port);

      // Per-interface /24 broadcast. This is what makes Android hotspots and
      // some enterprise APs reliable when 255.255.255.255 is dropped.
      final addresses = await localIPv4Addresses();
      for (final address in addresses) {
        final broadcast = broadcastAddressFor(address);
        if (broadcast == null) continue;
        socket.send(bytes, InternetAddress(broadcast), port);
      }
    } on Object catch (error) {
      onError?.call(error);
    } finally {
      _sending = false;
    }
  }

  void _handleEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    if (datagram.data.length > 60000) return;
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['t'] != 'fd-beacon') return;
      final info = decoded['info'];
      if (info is! Map<String, dynamic>) return;
      final device = DeviceInfo.fromJson(info);
      if (!device.isCompatible) return;
      if (device.id == deviceInfo().id) return;
      onDevice(device, datagram.address);
    } on Object catch (error) {
      // Malformed beacons are expected on a shared network; ignore them.
      onError?.call(error);
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}
