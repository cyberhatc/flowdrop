import 'dart:io';

import 'package:path/path.dart' as p;

import '../protocol/constants.dart';
import '../protocol/paths.dart';

/// One file found while scanning a picked folder.
class FolderScanEntry {
  const FolderScanEntry({
    required this.fullPath,
    required this.relativePath,
    required this.size,
  });

  /// Absolute path of the file on this device.
  final String fullPath;

  /// Sanitized `/`-separated path relative to the picked folder,
  /// e.g. `trip/day1/a.jpg`.
  final String relativePath;
  final int size;
}

class FolderScanResult {
  const FolderScanResult({
    required this.entries,
    this.skipped = 0,
    this.truncated = false,
  });

  final List<FolderScanEntry> entries;

  /// Files skipped because a segment could not be sanitized safely
  /// (e.g. a file literally named `..` on a weird filesystem).
  final int skipped;

  /// True when the folder had more files than the protocol allows, so the
  /// tail was not included.
  final bool truncated;
}

/// Recursively scans [root] and returns every file with its sanitized
/// relative path — the shape the sender needs for folder transfers.
///
/// * Symlinks are not followed (only regular files are returned).
/// * Names that cannot be sanitized safely are skipped and counted.
/// * At most [maxFiles] entries are returned (protocol limit);
///   [FolderScanResult.truncated] reports when more existed.
Future<FolderScanResult> scanFolder(
  String root, {
  int maxFiles = FlowDropProtocol.maxFilesPerOffer,
}) async {
  final entries = <FolderScanEntry>[];
  var skipped = 0;
  var truncated = false;

  final rootDir = Directory(root);
  if (!await rootDir.exists()) {
    return const FolderScanResult(entries: [], skipped: 0);
  }

  await for (final entity in rootDir.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    // list(followLinks: false) already excludes symlinked dirs, but a file
    // could itself be a symlink — skip it to avoid sending anything outside
    // the picked folder tree.
    final typeName = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    if (typeName != FileSystemEntityType.file) continue;
    final stat = await entity.stat();

    final relative = p.relative(entity.path, from: rootDir.path);
    String safe;
    try {
      safe = sanitizeRelativePath(p.toUri(relative).path);
    } on FormatException {
      skipped++;
      continue;
    }
    if (entries.length >= maxFiles) {
      truncated = true;
      continue;
    }
    entries.add(
      FolderScanEntry(
        fullPath: entity.path,
        relativePath: safe,
        size: stat.size,
      ),
    );
  }

  return FolderScanResult(
    entries: List.unmodifiable(entries),
    skipped: skipped,
    truncated: truncated,
  );
}
