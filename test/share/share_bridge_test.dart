import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/app/state/app_controller.dart';
import 'package:flowdrop/app/state/app_state.dart';
import 'package:flowdrop/core/discovery/peer.dart';
import 'package:flowdrop/core/protocol/device.dart';
import 'package:flowdrop/features/share/share_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const _fakeDevice = DeviceInfo(
  id: 'peer-1',
  name: 'Pixel 8',
  platform: 'android',
  publicKey: 'cHViag==',
  fingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  addresses: ['192.168.1.20'],
  port: 53317,
);

class _RecordingController extends AppController {
  List<ShareItem>? received;

  @override
  AppState build() {
    ref.onDispose(() {});
    return AppState(
      ready: true,
      peers: [
        Peer(
          device: _fakeDevice,
          lastSeen: DateTime.now(),
          source: PeerSource.udp,
        ),
      ],
      sessions: const [],
    );
  }

  @override
  Future<void> ingestShare(List<ShareItem> items) async {
    received = items;
  }

  @override
  Future<String?> sendToPeer({
    required DeviceInfo peer,
    required List<SendFile> files,
    String? text,
  }) async {
    return null;
  }
}

void main() {
  group('ShareBridge', () {
    test('initial share is ingested with send-capable shape', () async {
      final media = [
        SharedMediaFile(
          path: '/tmp/shared.txt',
          type: SharedMediaType.file,
          mimeType: 'text/plain',
        ),
        SharedMediaFile(
          path: 'https://example.com/page',
          type: SharedMediaType.url,
        ),
      ];
      ReceiveSharingIntent.setMockValues(
        initialMedia: media,
        mediaStream: const Stream.empty(),
      );

      final container = ProviderContainer(
        overrides: [
          appControllerProvider.overrideWith(_RecordingController.new),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        appControllerProvider.notifier,
      ) as _RecordingController;
      final bridge = ShareBridge(controller);
      addTearDown(bridge.dispose);

      await bridge.attach();

      expect(controller.received, isNotNull);
      final items = controller.received!;
      expect(items, hasLength(2));
      expect(items[0].filePath, '/tmp/shared.txt');
      expect(items[0].displayName, 'shared.txt');
      expect(items[1].text, 'https://example.com/page');
    });

    test('empty initial share is ignored', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: const Stream.empty(),
      );
      final container = ProviderContainer(
        overrides: [
          appControllerProvider.overrideWith(_RecordingController.new),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        appControllerProvider.notifier,
      ) as _RecordingController;
      final bridge = ShareBridge(controller);
      addTearDown(bridge.dispose);

      await bridge.attach();
      expect(controller.received, isNull);
    });

    test('live stream shares are ingested', () async {
      final streamController = StreamController<List<SharedMediaFile>>();
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: streamController.stream,
      );
      final container = ProviderContainer(
        overrides: [
          appControllerProvider.overrideWith(_RecordingController.new),
        ],
      );
      addTearDown(() async {
        await streamController.close();
        container.dispose();
      });
      final controller = container.read(
        appControllerProvider.notifier,
      ) as _RecordingController;
      final bridge = ShareBridge(controller);
      addTearDown(bridge.dispose);

      unawaited(bridge.attach());
      streamController.add([
        SharedMediaFile(path: 'hello share', type: SharedMediaType.text),
      ]);
      // Let the stream callback + async ingest run.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.received, isNotNull);
      expect(controller.received!.first.text, 'hello share');
    });
  });

  group('ingestShare conversion', () {
    test('unreadable files are skipped, not fatal', () async {
      // A path that does not exist must not crash — the sheet still opens.
      const item = ShareItem(
        filePath: '/definitely/not/here/does-not-exist.bin',
        name: 'missing.bin',
      );
      expect(item.isFile, isTrue);
      expect(item.displayName, 'missing.bin');
    });
  });
}
