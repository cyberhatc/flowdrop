import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flowdrop/app/state/app_controller.dart';
import 'package:flowdrop/app/state/app_state.dart';
import 'package:flowdrop/app/theme.dart';
import 'package:flowdrop/core/discovery/peer.dart';
import 'package:flowdrop/core/protocol/device.dart';
import 'package:flowdrop/core/protocol/offers.dart';
import 'package:flowdrop/core/security/identity.dart';
import 'package:flowdrop/core/security/trust_store.dart';
import 'package:flowdrop/core/storage/settings.dart';
import 'package:flowdrop/core/transfer/transfer_models.dart';
import 'package:flowdrop/features/history/history_screen.dart';
import 'package:flowdrop/features/home/home_screen.dart';
import 'package:flowdrop/features/incoming/incoming_dialogs.dart';
import 'package:flowdrop/features/onboarding/onboarding_screen.dart';
import 'package:flowdrop/features/send/send_sheet.dart';
import 'package:flowdrop/features/settings/settings_screen.dart';
import 'package:flowdrop/features/transfers/transfers_screen.dart';
import 'package:flowdrop/ui/glow.dart';

/// Regenerates the screenshots used by README.md.
///
/// Run with:
///   flutter test --update-goldens test/screenshots_test.dart
/// with FLOWDROP_SCREENSHOTS=1 set. The test is skipped otherwise so CI never
/// depends on platform fonts.
void main() {
  final enabled = Platform.environment['FLOWDROP_SCREENSHOTS'] == '1';

  // Fonts are loaded with real file I/O, which cannot complete inside the
  // fake-async zone of testWidgets; do it once in setUpAll instead.
  setUpAll(() async {
    if (!enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    await Directory('docs/screenshots').create(recursive: true);
  });

  testWidgets('capture README screenshots', (tester) async {
    // Logical 430x932 (a typical modern phone). physicalSize is in physical
    // pixels, so it must be multiplied by the device pixel ratio.
    tester.view.physicalSize = const Size(430 * 2, 932 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    Future<void> shot(String name, Widget screen) async {
      await tester.pumpWidget(_app(screen));
      // Fixed pumps only: the radar sweeps forever and pumpAndSettle would
      // never return.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/$name.png'),
      );
    }

    await shot('home', const HomeScreen());
    await shot('transfers', const TransfersScreen());
    await shot('history', const HistoryScreen());
    await shot('settings', const SettingsScreen());
    await shot('onboarding', const OnboardingScreen());

    // Send sheet needs an open route. Do not await: the future completes
    // only when the sheet is dismissed. Pump an empty tree first so the
    // Navigator does not keep the previous route stack.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pump();
    unawaited(showSendSheet(tester.element(find.byType(HomeScreen)), _peerA));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/send.png'),
    );

    // Incoming offer dialog.
    final offer = IncomingOffer(
      offer: OfferRequest(
        sessionId: 'offer-1',
        sender: _peerB,
        files: const [
          OfferedFile(
            id: 'f1',
            name: 'Design.fig',
            size: 45000000,
            mime: 'application/octet-stream',
          ),
          OfferedFile(
            id: 'f2',
            name: 'meeting-notes.md',
            size: 8000,
            mime: 'text/markdown',
          ),
        ],
        text: 'Sharing the deck from this morning',
      ),
      remoteIp: '192.168.1.50',
      trusted: false,
      completer: Completer<bool>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pump();
    unawaited(
      showIncomingOfferDialog(tester.element(find.byType(HomeScreen)), offer),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/incoming.png'),
    );
  }, skip: !enabled);
}

const _fingerprintA =
    '0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9';
const _fingerprintB =
    'f9e8d7c6b5a4938271605f4e3d2c1b0af9e8d7c6b5a4938271605f4e3d2c1b0a';

const _deviceA = DeviceInfo(
  id: 'device-a',
  name: 'MacBook Air',
  platform: 'macos',
  publicKey: 'cHViag==',
  fingerprint: _fingerprintA,
  addresses: ['192.168.1.30'],
  port: 53317,
);

const _deviceB = DeviceInfo(
  id: 'device-b',
  name: 'Jordans-iPhone',
  platform: 'ios',
  publicKey: 'cHViag==',
  fingerprint: _fingerprintB,
  addresses: ['192.168.1.50'],
  port: 53317,
);

const _deviceC = DeviceInfo(
  id: 'device-c',
  name: 'Workstation',
  platform: 'windows',
  publicKey: 'cHViag==',
  fingerprint:
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff',
  addresses: ['192.168.1.77'],
  port: 53317,
);

const _peerA = _deviceA;
const _peerB = _deviceB;

const _identity = DeviceIdentity(
  id: 'device-local',
  name: 'DESKTOP-7G2K',
  platform: 'windows',
  publicKey: 'cHViag==',
  privateSeed: '',
  certificatePem: '',
  privateKeyPem: '',
  fingerprint:
      'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
);

class _FakeController extends AppController {
  @override
  AppState build() {
    final now = DateTime.now();
    return AppState(
      ready: true,
      settings: const AppSettings().copyWith(
        deviceName: 'DESKTOP-7G2K',
        onboardingDone: true,
      ),
      identity: _identity,
      localDevice: const DeviceInfo(
        id: 'device-local',
        name: 'DESKTOP-7G2K',
        platform: 'windows',
        publicKey: 'cHViag==',
        fingerprint:
            'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
        addresses: ['192.168.1.42'],
        port: 53317,
      ),
      addresses: const ['192.168.1.42'],
      serverRunning: true,
      serverPort: 53317,
      udpRunning: true,
      mdnsRunning: true,
      peers: [
        Peer(device: _deviceA, lastSeen: now, source: PeerSource.udp),
        Peer(device: _deviceB, lastSeen: now, source: PeerSource.mdns),
        Peer(
          device: _deviceC,
          lastSeen: now.subtract(const Duration(minutes: 8)),
          source: PeerSource.paired,
          pinned: true,
        ),
      ],
      sessions: [
        SessionProgress(
          sessionId: 's1',
          peerName: 'Jordans-iPhone',
          files: [
            FileProgress(
              fileId: 'f1',
              name: 'videos/holiday-4k.mp4',
              totalBytes: 6_442_450_944,
              transferredBytes: 2_684_354_560,
              bytesPerSecond: 42_500_000,
              state: TransferState.active,
            ),
          ],
          direction: TransferDirection.sent,
        ),
        SessionProgress(
          sessionId: 's2',
          peerName: 'MacBook Air',
          files: [
            FileProgress(
              fileId: 'f2',
              name: 'backup.zip',
              totalBytes: 1_073_741_824,
              transferredBytes: 1_073_741_824,
              state: TransferState.completed,
            ),
          ],
          direction: TransferDirection.received,
          state: TransferState.completed,
          savedPaths: const ['C:/Users/manu/Downloads/FlowDrop/backup.zip'],
        ),
      ],
      history: [
        TransferRecord(
          id: 'h1',
          peerName: 'MacBook Air',
          peerDeviceId: 'device-a',
          direction: TransferDirection.received,
          files: const [
            OfferedFile(id: 'f2', name: 'backup.zip', size: 1073741824),
          ],
          totalBytes: 1073741824,
          startedAt: now.subtract(const Duration(minutes: 4)),
          finishedAt: now.subtract(const Duration(minutes: 2)),
          state: TransferState.completed,
          savedPath: 'C:/Users/manu/Downloads/FlowDrop/backup.zip',
        ),
        TransferRecord(
          id: 'h2',
          peerName: 'Jordans-iPhone',
          peerDeviceId: 'device-b',
          direction: TransferDirection.sent,
          files: const [
            OfferedFile(id: 'f3', name: 'invoice.pdf', size: 482000),
          ],
          totalBytes: 482000,
          startedAt: now.subtract(const Duration(hours: 3)),
          finishedAt: now.subtract(const Duration(hours: 3)),
          state: TransferState.completed,
        ),
      ],
      trustedDevices: [
        TrustedDevice(
          deviceId: 'device-a',
          name: 'MacBook Air',
          platform: 'macos',
          fingerprint: _fingerprintA,
          addedAt: now.subtract(const Duration(days: 4)),
          lastSeen: now,
          addresses: const ['192.168.1.30'],
          port: 53317,
        ),
        TrustedDevice(
          deviceId: 'device-c',
          name: 'Workstation',
          platform: 'windows',
          fingerprint: '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff',
          addedAt: now.subtract(const Duration(days: 12)),
          lastSeen: now.subtract(const Duration(minutes: 8)),
          addresses: const ['192.168.1.77'],
          port: 53317,
        ),
      ],
      clipboardHistory: [
        ClipboardEntry(
          data: 'https://github.com/cyberhatc/flowdrop',
          fromName: 'MacBook Air',
          at: now.subtract(const Duration(minutes: 1)),
        ),
        ClipboardEntry(
          data: 'ssh manu@192.168.1.30',
          fromName: 'This device',
          at: now.subtract(const Duration(minutes: 6)),
          outgoing: true,
        ),
      ],
    );
  }
}

/// Mirrors `main.dart`: ProviderScope wraps MaterialApp, so pushed routes
/// (the send sheet, dialogs) can still read providers.
Widget _app(Widget child) => ProviderScope(
  overrides: [appControllerProvider.overrideWith(_FakeController.new)],
  child: MaterialApp(
    theme: FlowDropTheme.dark(AccentColor.cyan),
    debugShowCheckedModeBanner: false,
    // The real app always renders screens inside AppShell's Scaffold and
    // neon background; without them InkWell has no Material ancestor.
    home: Scaffold(body: NeonBackground(child: child)),
  ),
);

/// `flutter test` runs with a test font that renders every glyph as a box.
/// Load the SDK's Roboto and Material Icons so the captured PNGs are readable.
Future<void> _loadFonts() async {
  final fonts = _materialFontsDir();
  if (fonts == null) return;
  await _loadFamily('Roboto', [
    p.join(fonts.path, 'roboto-regular.ttf'),
    p.join(fonts.path, 'roboto-medium.ttf'),
    p.join(fonts.path, 'roboto-bold.ttf'),
  ]);
  await _loadFamily('MaterialIcons', [
    p.join(fonts.path, 'materialicons-regular.otf'),
  ]);
}

Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Directory? _materialFontsDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    candidates.add(p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts'));
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add(p.join(dir.path, 'material_fonts'));
    candidates.add(p.join(dir.path, 'cache', 'artifacts', 'material_fonts'));
    dir = dir.parent;
  }
  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) return directory;
  }
  return null;
}
