import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' hide Signature;
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../protocol/device.dart';
import 'fingerprint.dart';

/// The long-lived identity of this installation.
///
/// Two independent key pairs are used:
///  * Ed25519 for signing pairing handshakes (cheap, modern),
///  * RSA-2048 only because `dart:io`'s TLS stack needs an RSA/ECDSA
///    certificate that it can serialize from PEM.
///
/// The private seed and the certificate's private key must be stored in the
/// OS secure store. They are deliberately kept in one object so a caller
/// cannot accidentally persist only half of the identity.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.privateSeed,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String id;
  final String name;
  final String platform;

  /// Base64 Ed25519 public key (32 bytes).
  final String publicKey;

  /// Base64 Ed25519 seed (32 bytes). Never log or transmit this.
  final String privateSeed;

  /// PEM encoded self-signed TLS certificate.
  final String certificatePem;

  /// PEM encoded RSA private key for [certificatePem]. Never log or transmit.
  final String privateKeyPem;

  /// SHA-256 of the DER certificate, lowercase hex.
  final String fingerprint;

  DeviceInfo toDeviceInfo({
    required List<String> addresses,
    required int port,
    String? name,
  }) {
    return DeviceInfo(
      id: id,
      name: name ?? this.name,
      platform: platform,
      publicKey: publicKey,
      fingerprint: fingerprint,
      addresses: addresses,
      port: port,
    );
  }

  DeviceIdentity copyWith({String? name}) => DeviceIdentity(
        id: id,
        name: name ?? this.name,
        platform: platform,
        publicKey: publicKey,
        privateSeed: privateSeed,
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
        fingerprint: fingerprint,
      );

  /// Signs [message] with the Ed25519 identity key.
  Future<String> sign(String message) async {
    final keyPair = await _keyPairFromSeed(privateSeed);
    final signature = await Ed25519().sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return base64.encode(signature.bytes);
  }

  /// Verifies a base64 signature created by [sign].
  static Future<bool> verifySignature({
    required String message,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    try {
      final publicKey = SimplePublicKey(
        base64.decode(publicKeyBase64),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        base64.decode(signatureBase64),
        publicKey: publicKey,
      );
      return await Ed25519().verify(utf8.encode(message), signature: signature);
    } on Object {
      return false;
    }
  }

  /// Generates a fresh identity. Expensive (~1 s) and only done once.
  static Future<DeviceIdentity> generate({
    required String name,
    required String platform,
    String? id,
  }) async {
    final keyPair = await Ed25519().newKeyPair();
    final extracted = await keyPair.extract();
    final seed = base64.encode(extracted.bytes);
    final publicKey = base64.encode(extracted.publicKey.bytes);

    final rsaPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final rsaPrivate = rsaPair.privateKey as RSAPrivateKey;
    final rsaPublic = rsaPair.publicKey as RSAPublicKey;
    final subject = <String, String>{
      'CN': 'flowdrop-${id ?? const Uuid().v4()}',
      'O': 'FlowDrop',
    };
    final csr = X509Utils.generateRsaCsrPem(
      subject,
      rsaPrivate,
      rsaPublic,
      san: const ['localhost'],
    );
    final certPem = X509Utils.generateSelfSignedCertificate(
      rsaPrivate,
      csr,
      3650,
      sans: const ['localhost'],
      // NOTE: basic_utils emits a malformed Key Usage BIT STRING with a
      // trailing byte, which BoringSSL (dart:io) rejects with
      // CANNOT_PARSE_LEAF_CERT. Key/elast usage extensions are not needed
      // here because clients pin the certificate fingerprint directly.
      cA: true,
      serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(rsaPrivate);

    return DeviceIdentity(
      id: id ?? const Uuid().v4(),
      name: name,
      platform: platform,
      publicKey: publicKey,
      privateSeed: seed,
      certificatePem: certPem,
      privateKeyPem: keyPem,
      fingerprint: fingerprintFromPem(certPem),
    );
  }

  static Future<SimpleKeyPair> _keyPairFromSeed(String seedBase64) {
    return Ed25519().newKeyPairFromSeed(base64.decode(seedBase64));
  }

  /// Serialized form for secure storage. Never expose this through logs.
  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'publicKey': publicKey,
        'privateSeed': privateSeed,
        'certificatePem': certificatePem,
        'privateKeyPem': privateKeyPem,
        'fingerprint': fingerprint,
      };

  factory DeviceIdentity.fromStorageJson(Map<String, dynamic> json) {
    final identity = DeviceIdentity(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      publicKey: json['publicKey'] as String,
      privateSeed: json['privateSeed'] as String,
      certificatePem: json['certificatePem'] as String,
      privateKeyPem: json['privateKeyPem'] as String,
      fingerprint: json['fingerprint'] as String,
    );
    final actual = fingerprintFromPem(identity.certificatePem);
    if (!fingerprintsEqual(actual, identity.fingerprint)) {
      throw const FormatException('Stored certificate does not match pin');
    }
    return identity;
  }

  @override
  String toString() =>
      'DeviceIdentity($name, $id, fp=${shortFingerprint(fingerprint)})';
}
