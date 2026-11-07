import '../protocol/device.dart';

class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.addedAt,
    this.autoAccept = false,
    this.lastSeen,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String fingerprint;
  final DateTime addedAt;
  final bool autoAccept;
  final DateTime? lastSeen;

  TrustedDevice copyWith({bool? autoAccept, DateTime? lastSeen}) {
    return TrustedDevice(
      deviceId: deviceId,
      name: name,
      platform: platform,
      fingerprint: fingerprint,
      addedAt: addedAt,
      autoAccept: autoAccept ?? this.autoAccept,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'fingerprint': fingerprint,
    'addedAt': addedAt.toIso8601String(),
    if (autoAccept) 'autoAccept': true,
    if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
  };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
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
