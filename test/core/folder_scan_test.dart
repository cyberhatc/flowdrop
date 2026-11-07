import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/transfer/folder_scan.dart';

void main() {
  group('scanFolder', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flowdrop-folder');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<File> write(String relative, int bytes) async {
      final file = File('${root.path}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.generate(bytes, (i) => i % 97));
      return file;
    }

    test('lists nested files with sanitized relative paths', () async {
      await write('a.txt', 10);
      await write('trip/day1/a.jpg', 200);
      await write('trip/day2/b.jpg', 50);

      final result = await scanFolder(root.path);
      expect(result.truncated, isFalse);
      expect(result.skipped, 0);
      expect(result.entries, hasLength(3));
      final relatives =
          result.entries.map((entry) => entry.relativePath).toList()..sort();
      expect(relatives, ['a.txt', 'trip/day1/a.jpg', 'trip/day2/b.jpg']);
      final aJpg = result.entries.firstWhere(
        (entry) => entry.relativePath == 'trip/day1/a.jpg',
      );
      expect(aJpg.size, 200);
      expect(await File(aJpg.fullPath).exists(), isTrue);
    });

    test('missing root returns empty', () async {
      final result = await scanFolder('${root.path}/nope');
      expect(result.entries, isEmpty);
      expect(result.truncated, isFalse);
    });

    test('truncates when the folder exceeds maxFiles', () async {
      for (var i = 0; i < 5; i++) {
        await write('f$i.txt', 1);
      }
      final result = await scanFolder(root.path, maxFiles: 3);
      expect(result.entries, hasLength(3));
      expect(result.truncated, isTrue);
    });

    test('does not follow symlinks into files', () async {
      await write('real.txt', 5);
      final target = await Directory.systemTemp.createTemp('fd-target');
      addTearDown(() => target.delete(recursive: true));
      final targetFile = await File('${target.path}/secret.txt')
          .writeAsBytes(const [1, 2, 3]);
      final link = Link('${root.path}/linked.txt');
      try {
        await link.create(targetFile.path);
      } on FileSystemException {
        // Windows without Developer Mode: skip the assertion.
        return;
      }
      final result = await scanFolder(root.path);
      expect(
        result.entries.any((entry) => entry.relativePath == 'linked.txt'),
        isFalse,
      );
      expect(
        result.entries.map((entry) => entry.relativePath),
        contains('real.txt'),
      );
    });
  });
}
