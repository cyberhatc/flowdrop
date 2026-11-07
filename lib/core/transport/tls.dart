import 'dart:convert';
import 'dart:io';

import '../security/fingerprint.dart';

/// Builds the TLS context used by the local HTTPS server.
///
/// The certificate is self-signed; clients pin its fingerprint instead of
/// relying on a CA.
SecurityContext securityContextFromPem({
  required String certificatePem,
  required String privateKeyPem,
}) {
  final context = SecurityContext(withTrustedRoots: false);
  try {
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
  } on Object catch (error) {
    throw StateError('Invalid certificate or private key: $error');
  }
  return context;
}

/// Creates an HTTP client that accepts exactly one self-signed certificate.
///
/// [expectedFingerprint] may be the full 64-character SHA-256 or a prefix of at
/// least 16 characters (the short code shown on the other device). There is
/// intentionally no parameter to disable pinning: a client without a known
/// fingerprint cannot connect at all.
HttpClient createPinnedHttpClient({
  required String expectedFingerprint,
  Duration connectionTimeout = const Duration(seconds: 8),
  Duration idleTimeout = const Duration(seconds: 30),
}) {
  final expected = normalizeFingerprint(expectedFingerprint);
  if (expected.length < 16 || expected.length > 64) {
    throw ArgumentError.value(
      expectedFingerprint,
      'expectedFingerprint',
      'Expected at least 16 hex characters of the SHA-256 fingerprint',
    );
  }
  final client = HttpClient()
    ..connectionTimeout = connectionTimeout
    ..idleTimeout = idleTimeout;
  client.badCertificateCallback =
      (X509Certificate certificate, String host, int port) {
        final actual = fingerprintFromDer(certificate.der);
        return actual == expected ||
            (expected.length < 64 && actual.startsWith(expected));
      };
  return client;
}

/// Fingerprint of the certificate presented by a live TLS connection.
///
/// Only used by tests and a diagnostic command; never to silently trust a peer.
Future<String> fetchCertificateFingerprint({
  required String host,
  required int port,
  Duration timeout = const Duration(seconds: 5),
}) async {
  String? captured;
  final client = HttpClient()..connectionTimeout = timeout;
  client.badCertificateCallback =
      (X509Certificate certificate, String host, int port) {
        captured = fingerprintFromDer(certificate.der);
        return true;
      };
  try {
    final request = await client
        .getUrl(Uri(scheme: 'https', host: host, port: port, path: '/v1/info'))
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
  if (captured == null) {
    throw StateError('No certificate was presented');
  }
  return captured!;
}
