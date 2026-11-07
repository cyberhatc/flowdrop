/// File-name and path sanitisation.
///
/// The receiver never trusts a name sent by a peer. A path must resolve inside
/// the download directory, even on Windows where `C:`, backslashes and reserved
/// device names are legal input to `File`.
library;

final RegExp _illegalChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final RegExp _drivePrefix = RegExp(r'^[a-zA-Z]:');
final RegExp _whitespace = RegExp(r'\s+');

const Set<String> _windowsReserved = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Turns untrusted input into a safe single path segment.
///
/// - strips directory components, drive letters, control characters,
/// - collapses whitespace and trims dots/spaces (Windows rejects trailing ones),
/// - escapes reserved device names,
/// - enforces a 180-character limit (leaving room for `.part` and suffixes),
/// - never returns an empty name.
String sanitizeFileName(String input) {
  var name = input.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(_drivePrefix, '');
  name = name.replaceAll(_illegalChars, '_');
  name = name.replaceAll(_whitespace, ' ').trim();
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  name = name.replaceAll(RegExp(r'^[.]+'), '');
  if (name.isEmpty || name == '.' || name == '..') return 'file';

  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  if (_windowsReserved.contains(stem.toUpperCase())) {
    name = '${stem}_$extension';
  }
  if (name.length > 180) {
    final keep = extension.length <= 16 ? extension : '';
    final stemPart = name.substring(0, 180 - keep.length);
    name = '$stemPart$keep';
  }
  return name.isEmpty ? 'file' : name;
}

/// Sanitises a relative path for folder transfers.
///
/// Returns a `/`-separated path with every segment sanitised. Absolute paths,
/// `..`, `.`, drive letters and empty segments are rejected (not silently
/// repaired) because they indicate a malicious or broken sender.
String sanitizeRelativePath(String input) {
  if (input.isEmpty) throw const FormatException('Empty path');
  if (input.startsWith('/') || input.startsWith('\\')) {
    throw const FormatException('Absolute paths are not allowed');
  }
  if (_drivePrefix.hasMatch(input)) {
    throw const FormatException('Drive paths are not allowed');
  }
  final segments = input
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) throw const FormatException('Empty path');
  if (segments.length > 64) throw const FormatException('Path too deep');
  final safe = <String>[];
  for (final segment in segments) {
    if (segment == '.' || segment == '..') {
      throw const FormatException('Path traversal is not allowed');
    }
    safe.add(sanitizeFileName(segment));
  }
  return safe.join('/');
}

/// Returns a non-colliding name for [desired] inside a set of existing names.
///
/// `photo.jpg` -> `photo (1).jpg` -> `photo (2).jpg` ...
String dedupeFileName(String desired, Set<String> existing) {
  final lower = existing.map((e) => e.toLowerCase()).toSet();
  if (!lower.contains(desired.toLowerCase())) return desired;
  final dot = desired.lastIndexOf('.');
  final stem = dot > 0 ? desired.substring(0, dot) : desired;
  final extension = dot > 0 ? desired.substring(dot) : '';
  for (var i = 1; i < 10000; i++) {
    final candidate = '$stem ($i)$extension';
    if (!lower.contains(candidate.toLowerCase())) return candidate;
  }
  throw StateError('Could not find a free file name');
}
