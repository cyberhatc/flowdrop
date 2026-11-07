import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/clipboard/clipboard_sync.dart';
import 'package:flowdrop/core/protocol/constants.dart';

ClipboardEvent remote(String data, {DateTime? at}) => ClipboardEvent(
  data: data,
  originDeviceId: 'remote-device',
  createdAt: at ?? DateTime.now(),
);

void main() {
  group('clipboardHash', () {
    test('is stable and input-sensitive', () {
      expect(clipboardHash('hello'), clipboardHash('hello'));
      expect(clipboardHash('hello'), isNot(clipboardHash('world')));
    });
  });

  group('ClipboardSyncGuard', () {
    test('pushes new non-empty content', () {
      final guard = ClipboardSyncGuard();
      expect(guard.shouldPush('hello world'), isTrue);
      guard.markPushed('hello world');
      expect(guard.shouldPush('hello world'), isFalse);
    });

    test('ignores empty and whitespace-only content', () {
      final guard = ClipboardSyncGuard();
      expect(guard.shouldPush(''), isFalse);
      expect(guard.shouldPush('   \n\t'), isFalse);
    });

    test('ignores oversized content', () {
      final guard = ClipboardSyncGuard();
      final big = 'a' * (FlowDropProtocol.maxTextBytes + 1);
      expect(guard.shouldPush(big), isFalse);
    });

    test('never re-pushes a recent remote value (loop prevention)', () {
      final guard = ClipboardSyncGuard();
      final event = remote('copied on the other device');
      guard.rememberRemote(event);
      expect(guard.shouldPush('copied on the other device'), isFalse);
      expect(guard.isRemoteRecent('copied on the other device'), isTrue);
      // Nearby local edits still push.
      expect(guard.shouldPush('edited locally'), isTrue);
    });

    test('remote suppression expires after the window', () {
      final guard = ClipboardSyncGuard(
        suppressionWindow: const Duration(seconds: 30),
      );
      final start = DateTime(2024, 1, 1, 12);
      final event = remote('shared', at: start);
      guard.rememberRemote(event);
      final later = start.add(const Duration(minutes: 2));
      expect(guard.isRemoteRecent('shared', now: later), isFalse);
      expect(guard.shouldPush('shared', now: later), isTrue);
    });

    test('remote cache is capped', () {
      final guard = ClipboardSyncGuard(maxRecentRemote: 2);
      final base = DateTime.now();
      guard.rememberRemote(remote('first', at: base));
      guard.rememberRemote(
        remote('second', at: base.add(const Duration(seconds: 1))),
      );
      guard.rememberRemote(
        remote('third', at: base.add(const Duration(seconds: 2))),
      );
      expect(guard.isRemoteRecent('third'), isTrue);
      expect(guard.isRemoteRecent('first'), isFalse);
    });

    test('reset clears suppression and last-pushed hash', () {
      final guard = ClipboardSyncGuard();
      final event = remote('shared');
      guard.rememberRemote(event);
      guard.markPushed('local note');
      guard.reset();
      expect(guard.shouldPush('shared'), isTrue);
      expect(guard.shouldPush('local note'), isTrue);
    });
  });

  group('ClipboardEvent', () {
    test('exposes hash and size guards', () {
      final event = remote('hello');
      expect(event.hash, clipboardHash('hello'));
      expect(event.isEmpty, isFalse);
      expect(event.isTooLarge, isFalse);
    });
  });
}
