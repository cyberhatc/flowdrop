import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Opens a file or a parent folder in the OS file explorer.
///
/// Returns false when nothing launcher-compatible is available (e.g. an
/// unsupported platform) so the UI can fall back to copying the path.
Future<bool> revealInFolder(String filePath) async {
  if (filePath.isEmpty) return false;
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
      return true;
    }
    if (Platform.isLinux) {
      final folder = p.dirname(filePath);
      await Process.run('xdg-open', [folder]);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
      return true;
    }
  } on Object {
    return false;
  }
  // Mobile: opening a file:// URL at least tries the system viewer.
  return launchUrl(Uri.file(filePath), mode: LaunchMode.externalApplication);
}

/// Opens an http(s) link in the system browser. Non-URLs return false.
Future<bool> openLink(String text) async {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// True when [text] parses as an http(s) URL.
bool isLink(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
