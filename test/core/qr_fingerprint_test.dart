import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/discovery/qr_payload.dart';
import 'package:flowdrop/core/security/fingerprint.dart';
import 'package:flowdrop/core/security/pairing.dart';
import 'package:flowdrop/core/protocol/constants.dart';

void main() {
  group('fingerprint', () {
    test('fromDer hashes DER bytes with SHA-256', () {
      final der = [1, 2, 3, 4];
      expect(fingerprintFromDer(der), sha256.convert(der).toString());
    });

    test('normalize strips separators and lowercases', () {
      expect(normalizeFingerprint('AB:CD EF-12'), 'abcdef12');
    });

    test('isValidFingerprint requires 64 hex chars', () {
      expect(isValidFingerprint('a' * 64), isTrue);
      expect(isValidFingerprint('a' * 63), isFalse);
      expect(isValidFingerprint('z' * 64), isFalse);
    });

    test('fingerprintsEqual is exact after normalization', () {
      final a = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
      expect(a.length, 64);
      final spaced =
          a.toUpperCase().split('').asMap().entries.map((e) =>
              '${e.value}${e.key % 4 == 3 ? ' ' : ''}').join();
      expect(fingerprintsEqual(a, spaced), isTrue);
      expect(fingerprintsEqual(a, '${a.substring(0, 63)}0'), isFalse);
      expect(fingerprintsEqual(a, a.substring(0, 32)), isFalse);
    });

    test('phrase is deterministic and four words', () {
      const fp = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789ab';
      final phrase = fingerprintPhrase(fp);
      expect(phrase, fingerprintPhrase(fp));
      expect(phrase.split('-'), hasLength(4));
      expect(fingerprintPhrase('short'), 'unknown phrase');
    });

    test('formatFingerprint groups in fours', () {
      expect(formatFingerprint('aabbccdd'), 'aabb ccdd');
    });
  });

  group('QrPayload', () {
    QrPayload sample() => QrPayload(
          deviceId: 'dev-1',
          name: 'My Phone',
          addresses: const ['192.168.1.5', '192.168.1.6'],
          port: FlowDropProtocol.defaultPort,
          fingerprint: 'a' * 64,
          token: 'token-abc',
          expiresAt: DateTime.now().add(const Duration(seconds: 120)),
        );

    test('encode/parse round-trips', () {
      final payload = sample();
      final parsed = QrPayload.parse(payload.encode());
      expect(parsed.deviceId, payload.deviceId);
      expect(parsed.name, 'My Phone');
      expect(parsed.addresses, payload.addresses);
      expect(parsed.port, payload.port);
      expect(parsed.fingerprint, payload.fingerprint);
      expect(parsed.token, 'token-abc');
    });

    test('rejects expired payloads', () {
      final expired = QrPayload(
        deviceId: 'dev-1',
        name: 'x',
        addresses: const ['127.0.0.1'],
        port: 53317,
        fingerprint: 'a' * 64,
        token: 't',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(
        () => QrPayload.parse(expired.encode()),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects wrong scheme, bad fingerprint and missing fields', () {
      expect(
        () => QrPayload.parse('https://example.com'),
        throwsA(isA<FormatException>()),
      );
      final badFp = QrPayload(
        deviceId: 'd',
        name: 'n',
        addresses: const ['127.0.0.1'],
        port: 53317,
        fingerprint: 'zzz',
        token: 't',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      expect(
        () => QrPayload.parse(badFp.encode()),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrPayload.parse('flowdrop://connect?v=1&id=only'),
        throwsA(isA<FormatException>()),
      );
    });

    test('remaining is zero after expiry', () {
      final payload = QrPayload(
        deviceId: 'd',
        name: 'n',
        addresses: const ['127.0.0.1'],
        port: 53317,
        fingerprint: 'a' * 64,
        token: 't',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      expect(payload.isExpired, isTrue);
      expect(payload.remaining, Duration.zero);
    });
  });

  group('PairingTokenManager', () {
    test('issue + redeem works exactly once', () {
      final manager = PairingTokenManager();
      final token = manager.issue();
      expect(token.value.length, 24);
      expect(manager.redeem(token.value, clientIp: '1.2.3.4'),
          PairingResult.ok);
      expect(manager.redeem(token.value, clientIp: '1.2.3.4'),
          PairingResult.used);
    });

    test('invalid tokens are rejected', () {
      final manager = PairingTokenManager();
      expect(manager.redeem('nope', clientIp: '1.2.3.4'),
          PairingResult.invalid);
    });

    test('expired tokens are rejected', () {
      final manager = PairingTokenManager();
      final at = DateTime(2024, 1, 1, 12);
      final token = manager.issue(now: at);
      expect(
        manager.redeem(token.value,
            clientIp: '1.2.3.4', now: at.add(const Duration(minutes: 3))),
        PairingResult.expired,
      );
    });

    test('rate limits per IP', () {
      final manager =
          PairingTokenManager(maxAttemptsPerMinute: 3);
      final at = DateTime(2024, 1, 1, 12);
      expect(manager.redeem('x', clientIp: '9.9.9.9', now: at),
          PairingResult.invalid);
      expect(manager.redeem('x', clientIp: '9.9.9.9', now: at),
          PairingResult.invalid);
      expect(manager.redeem('x', clientIp: '9.9.9.9', now: at),
          PairingResult.invalid);
      expect(manager.redeem('x', clientIp: '9.9.9.9', now: at),
          PairingResult.rateLimited);
      // Other IPs are unaffected.
      expect(manager.redeem('x', clientIp: '8.8.8.8', now: at),
          PairingResult.invalid);
    });
  });
}
