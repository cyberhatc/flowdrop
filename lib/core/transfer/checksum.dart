import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Minimal sink that keeps only the final digest.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Incremental SHA-256 hasher used while streaming file bytes.
///
/// This never buffers a whole file: chunks are folded into the digest as they
/// arrive from the disk or the socket.
class IncrementalSha256 {
  final _DigestSink _sink = _DigestSink();
  late final ByteConversionSink _input =
      sha256.startChunkedConversion(_sink);
  bool _closed = false;
  int _length = 0;

  int get length => _length;
  bool get isClosed => _closed;

  void add(List<int> chunk) {
    if (_closed) throw StateError('Hasher is closed');
    _length += chunk.length;
    _input.add(chunk);
  }

  String close() {
    if (!_closed) {
      _closed = true;
      _input.close();
    }
    return _sink.value?.toString() ?? '';
  }
}

/// Hashes only the first [length] bytes of a file.
///
/// Used when resuming an upload: the receiver keeps the already-written prefix,
/// so the sender must include it to produce the same full-file digest.
Future<void> addFilePrefix(
  IncrementalSha256 hasher,
  File file,
  int length,
) async {
  var remaining = length;
  await for (final chunk in file.openRead()) {
    if (remaining <= 0) break;
    if (chunk.length <= remaining) {
      hasher.add(chunk);
      remaining -= chunk.length;
    } else {
      hasher.add(chunk.sublist(0, remaining));
      remaining = 0;
    }
  }
  if (remaining > 0) {
    throw StateError('File shorter than expected while hashing prefix');
  }
}

/// Hashes a file from [offset] to the end.
Future<String> sha256File(File file, {int offset = 0}) async {
  final hasher = IncrementalSha256();
  await for (final chunk in file.openRead(offset)) {
    hasher.add(chunk);
  }
  return hasher.close();
}

/// Hashes only the first [length] bytes of a file.
///
/// Used when resuming an upload: the receiver keeps the already-written prefix,
/// so the sender must include it to produce the same full-file digest.
Future<String> sha256FilePrefix(File file, int length) async {
  final hasher = IncrementalSha256();
  var remaining = length;
  await for (final chunk in file.openRead()) {
    if (remaining <= 0) break;
    if (chunk.length <= remaining) {
      hasher.add(chunk);
      remaining -= chunk.length;
    } else {
      hasher.add(chunk.sublist(0, remaining));
      remaining = 0;
    }
  }
  if (remaining > 0) {
    throw StateError('File shorter than expected while hashing prefix');
  }
  return hasher.close();
}

/// Formats a byte count as MB/s with one decimal.
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
  }
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
