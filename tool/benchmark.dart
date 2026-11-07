/// FlowDrop transfer benchmark.
///
/// Runs a sender and receiver locally over loopback TLS and reports the
/// achieved throughput with checksum verification, so file-size and buffer
/// tuning decisions are made from data instead of guesses.
///
/// Usage:
///   dart run tool/benchmark.dart [sizeMb]
///
/// Default size is 64 MiB of random data in one file. Output is
/// machine-readable-ish: one line per run with size, elapsed and MB/s.
library;

import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flowdrop/core/protocol/offers.dart';
import 'package:flowdrop/core/security/identity.dart';
import 'package:flowdrop/core/security/pairing.dart';
import 'package:flowdrop/core/security/trust_store.dart';
import 'package:flowdrop/core/transport/client.dart';
import 'package:flowdrop/core/transport/server.dart';

Future<void> main(List<String> args) async {
  final sizeMb = int.tryParse(args.isEmpty ? '64' : args.first) ?? 64;
  final sizeBytes = sizeMb * 1024 * 1024;

  final sender = await DeviceIdentity.generate(name: 'BenchSender', platform: 'bench');
  final receiver = await DeviceIdentity.generate(name: 'BenchReceiver', platform: 'bench');

  final tempRoot = await Directory.systemTemp.createTemp('flowdrop-bench');
  final downloads = Directory('${tempRoot.path}/downloads');
  await downloads.create(recursive: true);

  final payload = File('${tempRoot.path}/payload.bin');
  final random = Random(1234);
  final sink = payload.openWrite();
  const chunk = 1 << 20;
  var written = 0;
  while (written < sizeBytes) {
    final n = min(chunk, sizeBytes - written);
    sink.add(List.generate(n, (_) => random.nextInt(256)));
    written += n;
  }
  await sink.close();
  final expectedSha = sha256.convert(await payload.readAsBytes()).toString();

  final server = FlowDropServer(
    identity: receiver,
    downloadDirectory: downloads.path,
    onOffer: (_, __, ___) async => true,
    trustStore: InMemoryTrustStore(),
    tokenManager: PairingTokenManager(),
    deviceInfoBuilder: (port) => receiver.toDeviceInfo(
      addresses: const ['127.0.0.1'],
      port: port,
    ),
  );
  await server.start(preferredPort: 0);

  try {
    final client = FlowDropClient(
      host: '127.0.0.1',
      port: server.port,
      identity: sender,
      localDevice: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      expectedFingerprint: receiver.fingerprint,
    );
    final offered = OfferedFile(
      id: FlowDropClient.newSessionId(),
      name: 'payload.bin',
      size: sizeBytes,
      mime: 'application/octet-stream',
    );
    final offer = OfferRequest(
      sessionId: FlowDropClient.newSessionId(),
      sender: sender.toDeviceInfo(addresses: const ['127.0.0.1'], port: 0),
      files: [offered],
    );
    final response = await client.offer(offer);
    assert(response.accepted);

    final stopwatch = Stopwatch()..start();
    final result = await client.uploadFile(
      file: offered,
      localPath: payload.path,
      uploadPath: response.uploadUrls[offered.id]!,
    );
    stopwatch.stop();

    final elapsed = stopwatch.elapsedMilliseconds / 1000;
    final mbs = elapsed > 0 ? (sizeBytes / (1024 * 1024)) / elapsed : 0;
    final checksumOk = result.sha256 == expectedSha;
    print('size=${sizeMb}MiB elapsed=${elapsed.toStringAsFixed(2)}s '
        'throughput=${mbs.toStringAsFixed(1)}MB/s checksum=$checksumOk');
    if (!checksumOk) {
      exitCode = 1;
    }
    client.close();
  } finally {
    await server.stop();
    await tempRoot.delete(recursive: true);
  }
}
