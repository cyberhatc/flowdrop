import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class RelayBridge {
  RelayBridge({required this.relayUrl, required this.code});

  final String relayUrl;
  final String code;

  String get _wsUrl {
    var url = relayUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring('https://'.length)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring('http://'.length)}';
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'ws://$url';
    }
    return '$url/tunnel';
  }

  Future<void> startReceiver({
    required String targetHost,
    required int targetPort,
    bool Function()? isStopped,
  }) async {
    while (isStopped == null || !isStopped()) {
      Socket? target;
      WebSocketChannel? channel;
      try {
        channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
        await channel.ready;
        channel.sink.add(code);
        target = await Socket.connect(targetHost, targetPort);
        await _bridgeSocketAndChannel(target, channel);
      } catch (_) {
      } finally {
        try {
          await target?.close();
        } catch (_) {}
        try {
          await channel?.sink.close();
        } catch (_) {}
      }
      if (isStopped != null && isStopped()) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<ServerSocket> startSenderProxy({required int localPort}) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      localPort,
    );
    server.listen((socket) {
      _handleSenderConnection(socket);
    }, onError: (_) {});
    return server;
  }

  Future<void> _handleSenderConnection(Socket socket) async {
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await channel.ready;
      channel.sink.add(code);
      await _bridgeSocketAndChannel(socket, channel);
    } catch (_) {
    } finally {
      try {
        await socket.close();
      } catch (_) {}
      try {
        await channel?.sink.close();
      } catch (_) {}
    }
  }

  Future<void> _bridgeSocketAndChannel(
    Socket socket,
    WebSocketChannel channel,
  ) async {
    final completer = Completer<void>();
    late StreamSubscription socketSub;
    late StreamSubscription wsSub;

    socketSub = socket.listen(
      (data) {
        try {
          channel.sink.add(data);
        } catch (_) {}
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    wsSub = channel.stream.listen(
      (data) {
        try {
          if (data is String) {
            socket.add(utf8.encode(data));
          } else if (data is List<int>) {
            socket.add(data);
          }
        } catch (_) {}
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
    await socketSub.cancel();
    await wsSub.cancel();
  }
}
