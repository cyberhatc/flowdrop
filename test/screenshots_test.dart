import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowdrop/app/state/app_controller.dart';
import 'package:flowdrop/app/state/app_state.dart';
import 'package:flowdrop/app/theme.dart';
import 'package:flowdrop/core/discovery/peer.dart';
import 'package:flowdrop/core/discovery/qr_payload.dart';
import 'package:flowdrop/core/protocol/device.dart';
import 'package:flowdrop/core/protocol/offers.dart';
import 'package:flowdrop/core/security/trust_store.dart';
import 'package:flowdrop/core/storage/settings.dart';
import 'package:flowdrop/core/transfer/transfer_models.dart';
import 'package:flowdrop/features/home/home_screen.dart';
import 'package:flowdrop/features/incoming/incoming_dialogs.dart';
import 'package:flowdrop/features/send/send_sheet.dart';

const _fakeDevice = DeviceInfo(
  id: 'peer-1',
  name: 'Pixel 8',
  platform: 'android',
  publicKey: 'cHViag==',
  fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  addresses: ['192.168.1.20'],
  port: 53317,
);

class _FakeController extends AppController {
  @override
  AppState build() {
    return AppState(
      ready: true,
      settings: const AppSettings()
          .copyWith(deviceName: 'DESKTOP-7G2K', onboardingDone: true),
      addresses: const ['192.168.1.42'],
      serverRunning: true,
      serverPort: 53317,
      udpRunning: true,
      peers: [
        Peer(
          device: _fakeDevice,
          lastSeen: DateTime.now(),
          source: PeerSource.udp,
        ),
        Peer(
          device: const DeviceInfo(
            id: 'peer-2',
            name: 'MacBook Air',
            platform: 'macos',
            publicKey: 'cHViag==',
            fingerprint:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            addresses: ['192.168.1.30'],
            port: 53317,
          ),
          lastSeen: DateTime.now(),
          source: PeerSource.mdns,
        ),
      ],
      sessions: [
        SessionProgress(
          sessionId: 's1',
          peerName: 'Pixel 8',
          files: [
            FileProgress(
              fileId: 'f1',
              name: 'downloads/videos/clip.mp4',
              totalBytes: 200_000_000,
              transferredBytes: 123_456_789,
              bytesPerSecond: 8_500_000,
              state: TransferState.active,
            ),
          ],
          direction: TransferDirection.sent,
        ),
      ],
      trustedDevices: [
        TrustedDevice(
          deviceId: 'peer-1',
          name: 'Pixel 8',
          platform: 'android',
          fingerprint:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          addedAt: DateTime.now(),
        ),
      ],
      clipboardHistory: [
        ClipboardEntry(
          data: 'https://example.com/repo/issues/42',
          fromName: 'This device',
          at: DateTime.now(),
          outgoing: true,
        ),
      ],
    );
  }
}

Future<void> _capture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

ProviderScope _withFake({required Widget child}) => ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(_FakeController.new),
      ],
      child: RepaintBoundary(child: child),
    );

MaterialApp _app(Widget child) => MaterialApp(
      theme: FlowDropTheme.dark(AccentColor.cyan),
      home: _withFake(child: child),
    );

void main() {
  testWidgets('screenshots', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const HomeScreen()));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await _capture(tester, 'assets/screenshots/home.png');

    // Send sheet over a plain scaffold
    await tester.pumpWidget(
      MaterialApp(
        theme: FlowDropTheme.dark(AccentColor.cyan),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: RepaintBoundary(
                child: Center(
                  child: ElevatedButton(
                    onPressed: () => showSendSheet(context, _fakeDevice),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await _capture(tester, 'assets/screenshots/send.png');

    // Incoming offer dialog
    final offer = IncomingOffer(
      offer: OfferRequest(
        sessionId: 'offer-1',
        sender: const DeviceInfo(
          id: 'peer-9',
          name: 'Jordans-iPhone',
          platform: 'ios',
          publicKey: 'cHViag==',
          fingerprint:
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          addresses: ['192.168.1.50'],
          port: 53317,
        ),
        files: const [
          OfferedFile(id: 'f1', name: 'Design.fig', size: 45_000_000, mime: 'application/octet-stream'),
          OfferedFile(id: 'f2', name: 'meeting-notes.md', size: 8_000, mime: 'text/markdown'),
        ],
        text: 'Sharing the deck from this morning',
      ),
      remoteIp: '192.168.1.50',
      trusted: false,
      completer: Completer<bool>(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlowDropTheme.dark(AccentColor.cyan),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: RepaintBoundary(
                child: Center(
                  child: ElevatedButton(
                    onPressed: () => showIncomingOfferDialog(context, offer),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await _capture(tester, 'assets/screenshots/incoming.png');

    expect(await File('assets/screenshots/home.png').exists(), isTrue);
  });
}
