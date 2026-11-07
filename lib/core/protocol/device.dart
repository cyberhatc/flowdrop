import 'constants.dart';

/// Everything a peer needs to know about this device.
///
/// `fingerprint` is the SHA-256 of the TLS certificate in DER form, lowercase
/// hex without separators. It is the only value that grants trust.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.fingerprint,
    required this.addresses,
    required this.port,
    this.protocolVersion = FlowDropProtocol.version,
  });

  final String id;
  final String name;
  final String platform;

  /// Base64 Ed25519 public key used to sign pairing handshakes.
  final String publicKey;

  /// SHA-256 of the TLS certificate (DER), lowercase hex.
  final String fingerprint;

  /// Reachable IPv4 addresses. The port applies to all of them.
  final List<String> addresses;
  final int port;
  final int protocolVersion;

  bool get isCompatible => protocolVersion == FlowDropProtocol.version;

  DeviceInfo copyWith({String? name, List<String>? addresses, int? port}) {
    return DeviceInfo(
      id: id,
      name: name ?? this.name,
      platform: platform,
      publicKey: publicKey,
      fingerprint: fingerprint,
      addresses: addresses ?? this.addresses,
      port: port ?? this.port,
      protocolVersion: protocolVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'version': protocolVersion,
    'publicKey': publicKey,
    'fingerprint': fingerprint,
    'addresses': addresses,
    'port': port,
  };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    final addresses = (json['addresses'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return DeviceInfo(
      id: _requiredString(json, 'id'),
      name: _optionalString(json, 'name') ?? 'Unknown device',
      platform: _optionalString(json, 'platform') ?? 'unknown',
      publicKey: _optionalString(json, 'publicKey') ?? '',
      fingerprint: _normalizeFingerprint(_requiredString(json, 'fingerprint')),
      addresses: addresses,
      port: _requiredInt(json, 'port'),
      protocolVersion: _optionalInt(json, 'version') ?? 0,
    );
  }

  @override
  String toString() => 'DeviceInfo($name, $id, $addresses:$port)';
}

String _normalizeFingerprint(String input) =>
    input.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid "$key"');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Missing or invalid "$key"');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
