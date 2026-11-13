import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flowdrop/app/storage/json_trust_store.dart';
import 'package:flowdrop/core/protocol/device.dart';
import 'package:flowdrop/core/security/trust_store.dart';

void main() {
  group('TrustedDevice persistence', () {
    late Directory temp;
    late File file;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('flowdrop-trust');
      file = File(p.join(temp.path, 'trusted_devices.json'));
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('addresses and port survive a restart', () async {
      const device = DeviceInfo(
        id: 'peer-1',
        name: 'Pixel 8',
        platform: 'android',
        publicKey: 'cHViag==',
        fingerprint:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        addresses: ['192.168.1.20'],
        port: 53317,
      );

      final store = JsonTrustStore(file);
      await store.trust(TrustedDevice.fromDevice(device));

      // A fresh instance simulates the next app launch.
      final reloaded = await JsonTrustStore(file).all();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.addresses, ['192.168.1.20']);
      expect(reloaded.single.port, 53317);
      expect(reloaded.single.lastSeen, isNotNull);
    });

    test('mergeDevice keeps fallback addresses and refreshes endpoint', () {
      final device = TrustedDevice.fromDevice(
        const DeviceInfo(
          id: 'peer-1',
          name: 'Pixel 8',
          platform: 'android',
          publicKey: '',
          fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          addresses: ['192.168.1.20'],
          port: 53317,
        ),
      );

      final merged = device.mergeDevice(
        const DeviceInfo(
          id: 'peer-1',
          name: 'Pixel 8',
          platform: 'android',
          publicKey: '',
          fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          addresses: ['10.0.0.7'],
          port: 53318,
        ),
      );

      expect(merged.addresses, ['10.0.0.7', '192.168.1.20']);
      expect(merged.port, 53318);
    });

    test('legacy entries without addresses still load', () async {
      await file.writeAsString(
        '[{"deviceId":"old","name":"Old phone","platform":"ios",'
        '"fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
        '"addedAt":"2024-01-01T00:00:00.000"}]',
      );
      final devices = await JsonTrustStore(file).all();
      expect(devices.single.addresses, isEmpty);
      expect(devices.single.port, 53317);
    });

    test('writes are atomic and leave no temporary file behind', () async {
      final store = JsonTrustStore(file);
      await store.trust(
        TrustedDevice.fromDevice(
          const DeviceInfo(
            id: 'peer-2',
            name: 'Laptop',
            platform: 'linux',
            publicKey: '',
            fingerprint: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            addresses: ['10.0.0.4'],
            port: 53317,
          ),
        ),
      );

      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);
      // A second write must replace the file, not append to it.
      await store.trust(
        TrustedDevice.fromDevice(
          const DeviceInfo(
            id: 'peer-3',
            name: 'Phone',
            platform: 'android',
            publicKey: '',
            fingerprint: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            addresses: ['10.0.0.5'],
            port: 53317,
          ),
        ),
      );
      expect(await JsonTrustStore(file).all(), hasLength(2));
    });

    test('falls back to the backup when the main file is corrupt', () async {
      final store = JsonTrustStore(file);
      await store.trust(
        TrustedDevice.fromDevice(
          const DeviceInfo(
            id: 'peer-4',
            name: 'Tablet',
            platform: 'android',
            publicKey: '',
            fingerprint: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            addresses: ['10.0.0.6'],
            port: 53317,
          ),
        ),
      );
      // A second write creates the .bak copy of the previous good file.
      await store.trust(
        TrustedDevice.fromDevice(
          const DeviceInfo(
            id: 'peer-5',
            name: 'Desktop',
            platform: 'windows',
            publicKey: '',
            fingerprint: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            addresses: ['10.0.0.7'],
            port: 53317,
          ),
        ),
      );
      await file.writeAsString('{not json');

      final recovered = await JsonTrustStore(file).all();
      expect(recovered, isNotEmpty);
      expect(recovered.map((device) => device.deviceId), contains('peer-4'));
    });
  });
}
