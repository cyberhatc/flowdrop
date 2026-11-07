import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SHA-256 fingerprint helpers.
///
/// A fingerprint is always represented as lowercase hex (64 characters). The
/// UI may display it grouped, but comparisons must use the normalized form.

const String _hexAlphabet = '0123456789abcdef';

String fingerprintFromDer(List<int> der) => sha256.convert(der).toString();

/// Reads a PEM certificate and hashes its DER body.
String fingerprintFromPem(String pem) {
  final body = pem
      .replaceAll(RegExp('-----BEGIN [^-]+-----'), '')
      .replaceAll(RegExp('-----END [^-]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) throw const FormatException('Empty certificate');
  return fingerprintFromDer(base64.decode(body));
}

String normalizeFingerprint(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

bool isValidFingerprint(String value) {
  final normalized = normalizeFingerprint(value);
  return normalized.length == 64 &&
      normalized.split('').every(_hexAlphabet.contains);
}

/// Constant-time comparison. Fingerprints are public values, but avoiding a
/// short-circuit keeps this safe if it is ever reused for secrets.
bool fingerprintsEqual(String a, String b) {
  final left = normalizeFingerprint(a);
  final right = normalizeFingerprint(b);
  if (left.length != right.length) return false;
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return diff == 0;
}

/// `a1b2c3d4e5f6` -> `a1b2 c3d4 e5f6`
String formatFingerprint(String fingerprint) {
  final normalized = normalizeFingerprint(fingerprint);
  final buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(normalized[i]);
  }
  return buffer.toString();
}

String shortFingerprint(String fingerprint) {
  final normalized = normalizeFingerprint(fingerprint);
  return normalized.length <= 12 ? normalized : normalized.substring(0, 12);
}

const List<String> _phraseWords = [
  'amber',
  'anchor',
  'aster',
  'atlas',
  'aurora',
  'basil',
  'beacon',
  'birch',
  'blaze',
  'bloom',
  'breeze',
  'canyon',
  'cedar',
  'cinder',
  'cobalt',
  'comet',
  'coral',
  'cosmo',
  'crimson',
  'crystal',
  'delta',
  'dune',
  'echo',
  'ember',
  'falcon',
  'fern',
  'flint',
  'forest',
  'frost',
  'galaxy',
  'garnet',
  'glacier',
  'glow',
  'granite',
  'harbor',
  'hazel',
  'ivory',
  'jade',
  'jasper',
  'jungle',
  'lagoon',
  'lantern',
  'lunar',
  'maple',
  'meadow',
  'meteor',
  'mist',
  'nebula',
  'nickel',
  'nova',
  'oasis',
  'ocean',
  'olive',
  'onyx',
  'opal',
  'orbit',
  'pebble',
  'pine',
  'plasma',
  'prism',
  'quartz',
  'raven',
  'reef',
  'river',
  'saffron',
  'sage',
  'sapphire',
  'shadow',
  'silver',
  'solar',
  'spark',
  'spruce',
  'star',
  'storm',
  'summit',
  'sunset',
  'thunder',
  'tiger',
  'topaz',
  'tundra',
  'velvet',
  'violet',
  'wave',
  'willow',
  'winter',
  'zephyr',
  'zinc',
  'zodiac',
];

/// A human-verifiable four-word phrase derived from the fingerprint.
///
/// Both devices show the same phrase for the same certificate, which makes
/// manual verification possible without comparing 64 hex characters.
String fingerprintPhrase(String fingerprint) {
  final normalized = normalizeFingerprint(fingerprint);
  if (normalized.length < 8) return 'unknown phrase';
  final bytes = <int>[];
  for (var i = 0; i < 8; i += 2) {
    bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
  }
  return bytes
      .map((byte) => _phraseWords[byte % _phraseWords.length])
      .join('-');
}
