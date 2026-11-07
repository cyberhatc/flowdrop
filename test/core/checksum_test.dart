import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/transfer/checksum.dart';

void main() {
  group('IncrementalSha256', () {
    test('matches crypto for chunked input', () {
      final hasher = IncrementalSha256();
      hasher.add([1, 2, 3]);
      hasher.add([4, 5, 6, 7, 8, 9]);
      expect(
        hasher.close(),
        sha256.convert([1, 2, 3, 4, 5, 6, 7, 8, 9]).toString(),
      );
      expect(hasher.length, 9);
    });

    test('second close returns the same digest', () {
      final hasher = IncrementalSha256();
      hasher.add([42]);
      final first = hasher.close();
      expect(hasher.close(), first);
    });

    test('adding after close throws', () {
      final hasher = IncrementalSha256();
      hasher.close();
      expect(() => hasher.add([1]), throwsStateError);
    });
  });

  group('file hashing + resume prefix', () {
    late Directory temp;
    late File file;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('flowdrop-hash');
      file = File('${temp.path}/sample.bin');
      await file.writeAsBytes(List.generate(10000, (i) => i % 251));
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('sha256File matches crypto digest', () async {
      final digest = await sha256File(file);
      final bytes = await file.readAsBytes();
      expect(digest, sha256.convert(bytes).toString());
    });

    test('sha256FilePrefix hashes only the prefix', () async {
      final digest = await sha256FilePrefix(file, 1000);
      final bytes = (await file.readAsBytes()).sublist(0, 1000);
      expect(digest, sha256.convert(bytes).toString());
    });

    test('addFilePrefix then suffix split equals full digest', () async {
      final hasher = IncrementalSha256();
      await addFilePrefix(hasher, file, 4000);
      await for (final chunk in file.openRead(4000)) {
        hasher.add(chunk);
      }
      expect(hasher.close(), await sha256File(file));
    });
  });

  group('formatting', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });

    test('formatSpeed', () {
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(2048), '2.0 KB/s');
      expect(formatSpeed(5 * 1024 * 1024), '5.0 MB/s');
      expect(formatSpeed(2 * 1024 * 1024 * 1024), '2.00 GB/s');
    });
  });
}
