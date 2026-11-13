import 'package:flutter_test/flutter_test.dart';

import 'package:flowdrop/core/discovery/peer.dart';
import 'package:flowdrop/core/protocol/device.dart';

const _deviceA = DeviceInfo(
  id: 'device-a',
  name: 'Alpha',
  platform: 'macos',
  publicKey: '',
  fingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  addresses: ['192.168.1.10'],
  port: 53317,
);

const _deviceB = DeviceInfo(
  id: 'device-b',
  name: 'Beta',
  platform: 'android',
  publicKey: '',
  fingerprint:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  addresses: ['192.168.1.11'],
  port: 53317,
);

Future<void> _ticks(int count) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  group('PeerRegistry', () {
    late PeerRegistry registry;

    setUp(() {
      registry = PeerRegistry(tick: const Duration(milliseconds: 10));
    });

    tearDown(() => registry.dispose());

    test(
      'pinned paired devices survive pruning, unpinned ones do not',
      () async {
        final stale = DateTime.now().subtract(const Duration(hours: 2));
        registry.seedPaired(_deviceA, lastSeen: stale);
        registry.upsert(_deviceB, source: PeerSource.udp, lastSeen: stale);

        // Let the prune timer run; both entries are older than peerTimeout.
        await _ticks(5);
        final ids = registry.snapshot.map((peer) => peer.device.id);
        expect(ids, contains('device-a'));
        expect(ids, isNot(contains('device-b')));

        final pinned = registry.snapshot.firstWhere(
          (peer) => peer.device.id == 'device-a',
        );
        expect(pinned.pinned, isTrue);
        expect(pinned.isLive, isFalse);
      },
    );

    test('beacons update a paired peer without unpinning it', () {
      registry.seedPaired(_deviceA);
      registry.upsert(
        _deviceA.copyWith(addresses: ['10.0.0.2'], port: 53320),
        source: PeerSource.udp,
      );

      final peer = registry.snapshot.single;
      expect(peer.pinned, isTrue);
      expect(peer.device.addresses, containsAll(['10.0.0.2', '192.168.1.10']));
      expect(peer.device.port, 53320);
      expect(peer.isLive, isTrue);
    });

    test('live peers sort before offline paired peers', () {
      registry.seedPaired(
        _deviceA,
        lastSeen: DateTime.now().subtract(const Duration(days: 1)),
      );
      registry.upsert(_deviceB, source: PeerSource.udp);

      expect(registry.snapshot.first.device.id, 'device-b');
    });

    test('forgetting a paired peer removes it from the radar', () {
      registry.seedPaired(_deviceA);
      expect(registry.snapshot, hasLength(1));
      registry.remove(_deviceA.id);
      expect(registry.snapshot, isEmpty);
    });
  });
}
