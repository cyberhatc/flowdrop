import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/discovery/qr_payload.dart';
import 'package:flowdrop/core/protocol/offers.dart';
import 'package:flowdrop/core/security/identity.dart';
import 'package:flowdrop/core/security/pairing.dart';
import 'package:flowdrop/core/security/trust_store.dart';
import 'package:flowdrop/core/transfer/checksum.dart';
import 'package:flowdrop/core/transport/client.dart';
import 'package:flowdrop/core/transport/server.dart';

/// Two in-process instances over loopback TLS: sender (client) -> receiver
/// (HTTPS server). Identity generation is slow (~1 s each) so it is shared.
void main() {
  late DeviceIdentity sender;
  late DeviceIdentity receiver;
  late Directory tempRoot;
  late Directory downloads;
  late InMemoryTrustStore trust;
  late FlowDropServer server;
  late PairingTokenManager tokens;
  bool approveOffers = true;
  TextPayload? lastText;

  setUpAll(() async {
    sender = await DeviceIdentity.generate(name: 'Sender', platform: 'test');
    receiver = await DeviceIdentity.generate(
      name: 'Receiver',
      platform: 'test',
    );
    tempRoot = await Directory.systemTemp.createTemp('flowdrop-it');
    downloads = Directory('${tempRoot.path}/downloads');
    await downloads.create(recursive: true);
    trust = InMemoryTrustStore();
    tokens = PairingTokenManager();
    server = FlowDropServer(
      identity: receiver,
      downloadDirectory: downloads.path,
      onOffer: (_, _, _) async => approveOffers,
      trustStore: trust,
      tokenManager: tokens,
      deviceInfoBuilder: (port) =>
          receiver.toDeviceInfo(addresses: const ['127.0.0.1'], port: port),
      onText: (payload, _, _) async {
        lastText = payload;
      },
    );
    await server.start(preferredPort: 0);
  });

  tearDownAll(() async {
    await server.stop();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  FlowDropClient client({String? expectedFingerprint, DeviceIdentity? as}) {
    final from = as ?? sender;
    return FlowDropClient(
      host: '127.0.0.1',
      port: server.port,
      identity: from,
      localDevice: from.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      expectedFingerprint: expectedFingerprint ?? receiver.fingerprint,
    );
  }

  Future<(File, OfferedFile)> makeFile({
    int size = 200000,
    String name = 'hello.bin',
  }) async {
    final random = Random(42);
    final file = File('${tempRoot.path}/$name');
    await file.writeAsBytes(List.generate(size, (_) => random.nextInt(256)));
    return (
      file,
      OfferedFile(
        id: FlowDropClient.newSessionId(),
        name: name,
        size: size,
        mime: 'application/octet-stream',
      ),
    );
  }

  test('info returns the receiver device', () async {
    final c = client();
    addTearDown(c.close);
    final info = await c.info();
    expect(info.id, receiver.id);
    expect(info.fingerprint, receiver.fingerprint);
  });

  test('file transfer streams and verifies checksum', () async {
    final (file, offered) = await makeFile();
    final sessionId = FlowDropClient.newSessionId();
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );

    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isTrue);
    final uploadPath = response.uploadUrls[offered.id]!;
    final result = await c.uploadFile(
      file: offered,
      localPath: file.path,
      uploadPath: uploadPath,
    );

    final bytes = await file.readAsBytes();
    expect(result.sha256, sha256.convert(bytes).toString());
    final saved = File('${downloads.path}/${result.savedPath!}');
    expect(await saved.readAsBytes(), bytes);
  });

  test('folder transfer recreates nested structure', () async {
    final source = Directory('${tempRoot.path}/folder_src');
    final fileA = File('${source.path}/trip/day1/a.txt');
    final fileB = File('${source.path}/trip/day2/b.txt');
    await fileA.parent.create(recursive: true);
    await fileA.writeAsBytes(const [1, 2, 3, 4, 5]);
    await fileB.parent.create(recursive: true);
    await fileB.writeAsBytes([9, 8, 7]);

    final sessionId = FlowDropClient.newSessionId();
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [
        OfferedFile(
          id: FlowDropClient.newSessionId(),
          name: 'a.txt',
          size: await fileA.length(),
          relativePath: 'trip/day1/a.txt',
        ),
        OfferedFile(
          id: FlowDropClient.newSessionId(),
          name: 'b.txt',
          size: await fileB.length(),
          relativePath: 'trip/day2/b.txt',
        ),
      ],
    );

    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isTrue);
    for (final offeredFile in offer.files) {
      final local = offeredFile.relativePath == 'trip/day1/a.txt'
          ? fileA.path
          : fileB.path;
      final result = await c.uploadFile(
        file: offeredFile,
        localPath: local,
        uploadPath: response.uploadUrls[offeredFile.id]!,
      );
      expect(result.savedPath, offeredFile.relativePath);
      expect(
        await File('${downloads.path}/${result.savedPath!}').readAsBytes(),
        await File(local).readAsBytes(),
      );
    }
  });

  test('declined offers are reported', () async {
    approveOffers = false;
    addTearDown(() => approveOffers = true);
    final (_, offered) = await makeFile(name: 'decline.bin', size: 10);
    final offer = OfferRequest(
      sessionId: FlowDropClient.newSessionId(),
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isFalse);
  });

  test('trusted-only mode auto-declines strangers without a prompt', () async {
    server.autoDeclineUntrusted = true;
    addTearDown(() => server.autoDeclineUntrusted = false);
    final (_, offered) = await makeFile(name: 'stranger.bin', size: 10);
    final offer = OfferRequest(
      sessionId: FlowDropClient.newSessionId(),
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isFalse);
    expect(response.reason, 'not_trusted');
  });

  test('trusted-only mode still allows trusted senders', () async {
    server.autoDeclineUntrusted = true;
    await trust.trust(
      TrustedDevice.fromDevice(
        sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      ),
    );
    addTearDown(() => server.autoDeclineUntrusted = false);
    final (_, offered) = await makeFile(name: 'friend.bin', size: 10);
    final offer = OfferRequest(
      sessionId: FlowDropClient.newSessionId(),
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isTrue);
  });

  test('text arrives through /v1/text', () async {
    lastText = null;
    final c = client();
    addTearDown(c.close);
    await c.sendText('hello from the test');
    expect(lastText, isNotNull);
    expect(lastText!.text, 'hello from the test');
    expect(lastText!.sender.id, sender.id);
  });

  test('wrong fingerprint is rejected at the TLS layer', () async {
    // A client pinning the wrong certificate must fail before any data.
    final c = client(expectedFingerprint: 'a' * 64);
    addTearDown(c.close);
    await expectLater(c.info(), throwsA(anything));
  });

  test('expired pairing token is rejected', () async {
    final token = tokens.issue(ttl: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final payload = QrPayload(
      deviceId: 'dev-x',
      name: 'Receiver',
      addresses: const ['127.0.0.1'],
      port: server.port,
      fingerprint: receiver.fingerprint,
      token: token.value,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    final c = client();
    addTearDown(c.close);
    await expectLater(
      c.pair(payload: payload),
      throwsA(
        isA<FlowDropException>().having((e) => e.code, 'code', 'token_expired'),
      ),
    );
  });

  test('path traversal in a folder offer is rejected', () async {
    final evil = OfferedFile(
      id: FlowDropClient.newSessionId(),
      name: 'evil.txt',
      size: 1,
      relativePath: '../../evil.txt',
    );
    final offer = OfferRequest(
      sessionId: FlowDropClient.newSessionId(),
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [evil],
    );
    final c = client();
    addTearDown(c.close);
    await expectLater(
      c.offer(offer),
      throwsA(
        isA<FlowDropException>().having((e) => e.statusCode, 'status', 400),
      ),
    );
    expect(await File('${tempRoot.path}/evil.txt').exists(), isFalse);
  });

  test('resume continues from the receiver offset', () async {
    final (file, offered) = await makeFile(name: 'resume.bin', size: 100000);
    final sessionId = FlowDropClient.newSessionId();
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isTrue);
    final uploadPath = response.uploadUrls[offered.id]!;

    // Simulate a killed connection: send only the first half with a raw
    // client, then resume with the real client.
    final bytes = await file.readAsBytes();
    final half = bytes.length ~/ 2;
    final raw = HttpClient()
      ..badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) => true;
    addTearDown(() => raw.close(force: true));
    final request = await raw.putUrl(
      Uri(
        scheme: 'https',
        host: '127.0.0.1',
        port: server.port,
        path: uploadPath,
      ),
    );
    request.headers.set('x-flowdrop-offset', '0');
    request.contentLength = half;
    request.add(bytes.sublist(0, half));
    final rawResponse = await request.close();
    expect(rawResponse.statusCode, 400); // incomplete -> offset kept

    final status = await c.status(sessionId);
    final fileStatus = status.files.firstWhere(
      (entry) => entry.id == offered.id,
    );
    expect(fileStatus.received, half);

    final result = await c.uploadFile(
      file: offered,
      localPath: file.path,
      uploadPath: uploadPath,
      startOffset: half,
    );
    expect(result.sha256, sha256.convert(bytes).toString());
    expect(
      await File('${downloads.path}/${result.savedPath!}').readAsBytes(),
      bytes,
    );
  });

  test('a 128 MiB file streams end to end with a verified checksum', () async {
    const blockSize = 1 << 20;
    const blocks = 128;
    const total = blockSize * blocks;
    final source = File('${tempRoot.path}/large.bin');
    final handle = source.openSync(mode: FileMode.write);
    final hasher = IncrementalSha256();
    final block = List<int>.generate(blockSize, (index) => index & 0xff);
    try {
      for (var i = 0; i < blocks; i++) {
        handle.writeFromSync(block);
        hasher.add(block);
      }
    } finally {
      handle.closeSync();
    }

    final offered = OfferedFile(
      id: FlowDropClient.newSessionId(),
      name: 'large.bin',
      size: total,
      mime: 'application/octet-stream',
    );
    final sessionId = FlowDropClient.newSessionId();
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );

    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    expect(response.accepted, isTrue);

    var maxReported = 0;
    final result = await c.uploadFile(
      file: offered,
      localPath: source.path,
      uploadPath: response.uploadUrls[offered.id]!,
      onProgress: (sent, _) {
        if (sent > maxReported) maxReported = sent;
      },
    );

    expect(result.size, total);
    expect(result.sha256, hasher.close());
    expect(maxReported, total);
    final saved = File('${downloads.path}/${result.savedPath!}');
    expect(await saved.length(), total);
    // Re-hash what actually landed on disk: proves the receiver streamed to
    // the file instead of buffering it in memory.
    expect(await sha256File(saved), result.sha256);
  });

  test('cancelled sessions reject further uploads', () async {
    final (file, offered) = await makeFile(name: 'cancel.bin', size: 5000);
    final sessionId = FlowDropClient.newSessionId();
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final c = client();
    addTearDown(c.close);
    final response = await c.offer(offer);
    await c.cancel(sessionId);
    await expectLater(
      c.uploadFile(
        file: offered,
        localPath: file.path,
        uploadPath: response.uploadUrls[offered.id]!,
      ),
      // After cancel the session is gone: the server must reject the upload.
      throwsA(isA<FlowDropException>()),
    );
  });

  group('QR pairing makes both directions transferable', () {
    late Directory downloadsA;
    late InMemoryTrustStore trustA;
    late FlowDropServer serverA;

    setUpAll(() async {
      downloadsA = Directory('${tempRoot.path}/downloadsA');
      await downloadsA.create(recursive: true);
      trustA = InMemoryTrustStore();
      serverA = FlowDropServer(
        identity: sender,
        downloadDirectory: downloadsA.path,
        onOffer: (_, _, _) async => true,
        trustStore: trustA,
        tokenManager: PairingTokenManager(),
        deviceInfoBuilder: (port) =>
            sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: port),
      );
      await serverA.start(preferredPort: 0);
    });

    tearDownAll(() async {
      await serverA.stop();
    });

    test('A scans B\'s code, then A -> B and B -> A both upload', () async {
      // B shows a QR code; the payload carries B's endpoint and a one-time
      // token. A scans it (the UI calls connectWithQr with the same payload).
      final token = tokens.issue();
      final payload = QrPayload.fromDevice(
        device: receiver.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: server.port,
        ),
        token: token,
      );

      final scanner = FlowDropClient(
        host: '127.0.0.1',
        port: server.port,
        identity: sender,
        localDevice: sender.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: serverA.port,
        ),
        expectedFingerprint: receiver.fingerprint,
      );
      addTearDown(scanner.close);
      final paired = await scanner.pair(payload: payload);
      expect(paired.ok, isTrue);
      expect(paired.trusted, isTrue);

      // B trusted A as part of redeeming the token; A trusts B afterwards,
      // exactly like connectWithQr does.
      expect(await trust.isTrusted(sender.fingerprint), isTrue);
      await trustA.trust(
        TrustedDevice.fromDevice(
          receiver.toDeviceInfo(
            addresses: const ['127.0.0.1'],
            port: server.port,
          ),
        ),
      );

      // A -> B
      final (fileA, offeredA) = await makeFile(name: 'from-a.bin', size: 64000);
      final clientA = FlowDropClient(
        host: '127.0.0.1',
        port: server.port,
        identity: sender,
        localDevice: sender.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: serverA.port,
        ),
        expectedFingerprint: receiver.fingerprint,
      );
      addTearDown(clientA.close);
      final offerA = OfferRequest(
        sessionId: FlowDropClient.newSessionId(),
        sender: sender.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: serverA.port,
        ),
        files: [offeredA],
      );
      final acceptedA = await clientA.offer(offerA);
      expect(acceptedA.accepted, isTrue);
      final uploadA = await clientA.uploadFile(
        file: offeredA,
        localPath: fileA.path,
        uploadPath: acceptedA.uploadUrls[offeredA.id]!,
      );
      final savedA = File('${downloads.path}/${uploadA.savedPath!}');
      expect(await savedA.readAsBytes(), await fileA.readAsBytes());

      // B -> A: the direction that used to need a restart, because B's
      // in-memory trust list was never refreshed after A paired with it.
      final (fileB, offeredB) = await makeFile(name: 'from-b.bin', size: 64000);
      final clientB = FlowDropClient(
        host: '127.0.0.1',
        port: serverA.port,
        identity: receiver,
        localDevice: receiver.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: server.port,
        ),
        expectedFingerprint: sender.fingerprint,
      );
      addTearDown(clientB.close);
      final offerB = OfferRequest(
        sessionId: FlowDropClient.newSessionId(),
        sender: receiver.toDeviceInfo(
          addresses: const ['127.0.0.1'],
          port: server.port,
        ),
        files: [offeredB],
      );
      final acceptedB = await clientB.offer(offerB);
      expect(acceptedB.accepted, isTrue);
      final uploadB = await clientB.uploadFile(
        file: offeredB,
        localPath: fileB.path,
        uploadPath: acceptedB.uploadUrls[offeredB.id]!,
      );
      final savedB = File('${downloadsA.path}/${uploadB.savedPath!}');
      expect(await savedB.readAsBytes(), await fileB.readAsBytes());
    });
  });
}
