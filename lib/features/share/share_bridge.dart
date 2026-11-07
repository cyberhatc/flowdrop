import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../app/state/app_controller.dart';
import '../../app/state/app_state.dart';

/// Connects the OS share sheet to the app controller.
///
/// * Android: SEND/SEND_MULTIPLE intents delivered by the platform plugin.
/// * iOS: requires a Share Extension target backed by an App Group to hand
///   files to the main app — see docs/ARCHITECTURE.md "Share targets".
///
/// The listener is unsubscribed when [dispose] is called.
class ShareBridge {
  ShareBridge(this.controller);

  final AppController controller;
  StreamSubscription<List<SharedMediaFile>>? _subscription;

  /// Reads the initial share (app was cold-started from the share sheet)
  /// and subscribes to live shares while the app is running.
  Future<void> attach() async {
    if (kIsWeb) return;
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        await _handle(initial);
      }
    } on Object {
      // No share at launch is normal.
    }
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (media) {
        if (media.isNotEmpty) unawaited(_handle(media));
      },
      onError: (_) {
        // The platform may not support share intents (desktop).
      },
      cancelOnError: false,
    );
  }

  Future<void> _handle(List<SharedMediaFile> media) async {
    final items = media
        .map(
          (entry) => ShareItem(
            filePath:
                entry.type == SharedMediaType.text ||
                    entry.type == SharedMediaType.url
                ? null
                : entry.path,
            text:
                entry.type == SharedMediaType.text ||
                    entry.type == SharedMediaType.url
                ? entry.path
                : entry.message,
            mime: entry.mimeType ?? 'application/octet-stream',
            name: entry.path.split('/').last,
          ),
        )
        .toList();
    if (items.isEmpty) return;
    await controller.ingestShare(items);
    try {
      await ReceiveSharingIntent.instance.reset();
    } on Object {
      // Some platforms do not implement reset.
    }
  }

  void dispose() => unawaited(_subscription?.cancel());
}
