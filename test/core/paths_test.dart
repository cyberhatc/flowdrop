import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/protocol/paths.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips directory traversal and drives', () {
      expect(sanitizeFileName('../../evil.txt'), 'evil.txt');
      expect(sanitizeFileName(r'C:\Windows\evil.txt'), 'evil.txt');
      expect(sanitizeFileName('/etc/passwd'), 'passwd');
    });

    test('replaces illegal characters', () {
      // No separators here: a slash would be treated as a directory split.
      expect(sanitizeFileName('a<b>c:"d"e!f|g?h*i'), 'a_b_c__d_e!f_g_h_i');
    });

    test('escapes Windows reserved names', () {
      expect(sanitizeFileName('CON'), 'CON_');
      expect(sanitizeFileName('con.txt'), 'con_.txt');
      expect(sanitizeFileName('LPT1.log'), 'LPT1_.log');
      expect(sanitizeFileName('normal.txt'), 'normal.txt');
    });

    test('never returns empty or dot names', () {
      expect(sanitizeFileName(''), 'file');
      expect(sanitizeFileName('..'), 'file');
      expect(sanitizeFileName('.'), 'file');
      expect(sanitizeFileName('   ...   '), 'file');
    });

    test('truncates long names and keeps extension', () {
      final long = '${'a' * 300}.pdf';
      final safe = sanitizeFileName(long);
      expect(safe.length, lessThanOrEqualTo(180));
      expect(safe.endsWith('.pdf'), isTrue);
    });
  });

  group('sanitizeRelativePath', () {
    test('accepts nested folder paths', () {
      expect(sanitizeRelativePath('trip/a.jpg'), 'trip/a.jpg');
      expect(sanitizeRelativePath('a/b/c.txt'), 'a/b/c.txt');
    });

    test('rejects traversal and absolute paths', () {
      expect(
        () => sanitizeRelativePath('../evil.txt'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => sanitizeRelativePath('a/../../evil.txt'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => sanitizeRelativePath('/abs/path.txt'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => sanitizeRelativePath(r'C:\evil.txt'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => sanitizeRelativePath(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('sanitizes reserved segments instead of keeping them', () {
      expect(sanitizeRelativePath('CON/report.txt'), 'CON_/report.txt');
    });
  });

  group('dedupeFileName', () {
    test('adds numbered suffixes', () {
      expect(
        dedupeFileName('photo.jpg', {'photo.jpg'}),
        'photo (1).jpg',
      );
      expect(
        dedupeFileName('photo.jpg', {'photo.jpg', 'photo (1).jpg'}),
        'photo (2).jpg',
      );
    });

    test('is case-insensitive', () {
      expect(dedupeFileName('Photo.JPG', {'photo.jpg'}), 'Photo (1).JPG');
    });

    test('keeps unique names unchanged', () {
      expect(dedupeFileName('a.txt', {'b.txt'}), 'a.txt');
    });
  });
}
