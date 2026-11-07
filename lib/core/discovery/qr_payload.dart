import '../protocol/constants.dart';
import '../protocol/device.dart';
import '../security/fingerprint.dart';
import '../security/pairing.dart';

/// The contents of the QR code shown by "Show my QR".
///
/// Format (URL-style, one line):
/// `flowdrop://connect?v=1&id=...&n=...&ip=ip1,ip2&p=53317&fp=<sha256>&t=<token>&exp=<unix>`
class QrPayload {
  const QrPayload({
    required this.deviceId,
    required this.name,
    required this.addresses,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
    this.version = FlowDropProtocol.version,
  });

  final int version;
  final String deviceId;
  final String name;
  final List<String> addresses;
  final int port;

  /// SHA-256 of the peer's TLS certificate. The connecting side must reject a
  /// certificate whose fingerprint differs.
  final String fingerprint;
  final String token;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Builds a payload from this device and an already-issued token.
  factory QrPayload.fromDevice({
    required DeviceInfo device,
    required PairingToken token,
  }) {
    return QrPayload(
      deviceId: device.id,
      name: device.name,
      addresses: device.addresses,
      port: device.port,
      fingerprint: device.fingerprint,
      token: token.value,
      expiresAt: token.expiresAt,
    );
  }

  String encode() {
    final addresses = this.addresses.take(8).join(',');
    return Uri(
      scheme: FlowDropProtocol.scheme,
      host: FlowDropProtocol.connectHost,
      queryParameters: {
        'v': '$version',
        'id': deviceId,
        'n': name,
        'ip': addresses,
        'p': '$port',
        'fp': fingerprint,
        't': token,
        'exp': '${expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    ).toString();
  }

  /// Parses and validates a scanned/pasted code.
  ///
  /// Throws [FormatException] with a human-readable reason for malformed,
  /// incompatible or expired payloads. Expiry is checked here so callers cannot
  /// forget it.
  factory QrPayload.parse(String raw, {DateTime? now}) {
    final text = raw.trim();
    if (text.isEmpty) throw const FormatException('Empty code');
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme.toLowerCase() != FlowDropProtocol.scheme ||
        uri.host.toLowerCase() != FlowDropProtocol.connectHost) {
      throw const FormatException('Not a FlowDrop code');
    }
    final params = uri.queryParameters;
    final version = int.tryParse(params['v'] ?? '');
    if (version == null || version != FlowDropProtocol.version) {
      throw const FormatException('Unsupported FlowDrop version');
    }
    final id = params['id'];
    final token = params['t'];
    final port = int.tryParse(params['p'] ?? '');
    final fingerprint = params['fp'] ?? '';
    final expiresSeconds = int.tryParse(params['exp'] ?? '');
    if (id == null || id.isEmpty) throw const FormatException('Missing device id');
    if (token == null || token.isEmpty) throw const FormatException('Missing token');
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('Invalid port');
    }
    if (!isValidFingerprint(fingerprint)) {
      throw const FormatException('Invalid fingerprint');
    }
    if (expiresSeconds == null) throw const FormatException('Missing expiry');
    final addresses = (params['ip'] ?? '')
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (addresses.isEmpty) throw const FormatException('Missing address');
    if (addresses.length > 8) throw const FormatException('Too many addresses');

    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresSeconds * 1000);
    final reference = now ?? DateTime.now();
    if (!reference.isBefore(expiresAt)) {
      throw const FormatException('This code has expired');
    }
    return QrPayload(
      version: version,
      deviceId: id,
      name: params['n'] ?? 'FlowDrop device',
      addresses: addresses,
      port: port,
      fingerprint: normalizeFingerprint(fingerprint),
      token: token,
      expiresAt: expiresAt,
    );
  }
}
