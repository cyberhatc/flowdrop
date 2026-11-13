import '../protocol/constants.dart';
import '../protocol/device.dart';

/// A paired device.
///
/// Addresses and the port are persisted on purpose: a paired device must be
/// reachable again after both apps restart, even when no discovery datagram
/// arrives. Without them the last-known endpoint is lost and the user has to
/// re-enter the IP and fingerprint every time.
class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.addedAt,
    this.autoAccept = false,
    this.lastSeen,
    this.addresses = const [],
    this.port = FlowDropProtocol.defaultPort,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String fingerprint;
  final DateTime addedAt;
  final bool autoAccept;
  final DateTime? lastSeen;

  /// Last known reachable IPv4 addresses, most recent first.
  final List<String> addresses;

  /// Port the device was listening on the last time it was reached.
  final int port;

  TrustedDevice copyWith({
    bool? autoAccept,
    DateTime? lastSeen,
    String? name,
    List<String>? addresses,
    int? port,
  }) {
    return TrustedDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      platform: platform,
      fingerprint: fingerprint,
      addedAt: addedAt,
      autoAccept: autoAccept ?? this.autoAccept,
      lastSeen: lastSeen ?? this.lastSeen,
      addresses: addresses ?? this.addresses,
      port: port ?? this.port,
    );
  }

  /// Returns this entry updated with the endpoint a live device just
  /// presented, keeping previously known addresses as fallbacks.
  TrustedDevice mergeDevice(DeviceInfo device, {DateTime? seenAt}) {
    final merged = <String>{
      ...device.addresses,
      ...addresses,
    }.take(8).toList(growable: false);
    return copyWith(
      name: device.name.trim().isEmpty ? name : device.name,
      addresses: merged,
      port: device.port > 0 ? device.port : port,
      lastSeen: seenAt ?? DateTime.now(),
    );
  }

  DeviceInfo toDeviceInfo() => DeviceInfo(
    id: deviceId,
    name: name,
    platform: platform,
    publicKey: '',
    fingerprint: fingerprint,
    addresses: addresses,
    port: port,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'fingerprint': fingerprint,
    'addedAt': addedAt.toIso8601String(),
    if (autoAccept) 'autoAccept': true,
    if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
    if (addresses.isNotEmpty) 'addresses': addresses,
    if (port > 0) 'port': port,
  };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    final rawAddresses = json['addresses'];
    return TrustedDevice(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String? ?? 'Unknown device',
      platform: json['platform'] as String? ?? 'unknown',
      fingerprint: json['fingerprint'] as String,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      autoAccept: json['autoAccept'] == true,
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
      addresses: rawAddresses is List<dynamic>
          ? rawAddresses.whereType<String>().toList(growable: false)
          : const [],
      port: json['port'] as int? ?? FlowDropProtocol.defaultPort,
    );
  }

  factory TrustedDevice.fromDevice(
    DeviceInfo device, {
    bool autoAccept = false,
  }) {
    return TrustedDevice(
      deviceId: device.id,
      name: device.name,
      platform: device.platform,
      fingerprint: device.fingerprint,
      addedAt: DateTime.now(),
      autoAccept: autoAccept,
      lastSeen: DateTime.now(),
      addresses: device.addresses.take(8).toList(growable: false),
      port: device.port,
    );
  }
}

/// Persistence boundary for paired devices.
abstract class TrustStore {
  Future<bool> isTrusted(String fingerprint);
  Future<void> trust(TrustedDevice device);
  Future<void> forget(String fingerprint);
  Future<List<TrustedDevice>> all();
}

/// Useful for tests and for the first launch before storage is ready.
class InMemoryTrustStore implements TrustStore {
  final Map<String, TrustedDevice> _devices = {};

  @override
  Future<List<TrustedDevice>> all() async => _devices.values.toList();

  @override
  Future<void> forget(String fingerprint) async {
    _devices.remove(fingerprint);
  }

  @override
  Future<bool> isTrusted(String fingerprint) async =>
      _devices.containsKey(fingerprint);

  @override
  Future<void> trust(TrustedDevice device) async {
    _devices[device.fingerprint] = device;
  }
}
