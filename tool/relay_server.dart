// A minimal, self-hostable relay for FlowDrop.
//
// FlowDrop is LAN-first by design. When two devices are not on the same
// network (different Wi-Fi, cellular, etc.) discovery and direct HTTPS no
// longer work. This relay bridges two WebSocket peers that share a short
// session code, forwarding frames verbatim. Because the frames are the
// existing FlowDrop HTTPS traffic, TLS and certificate pinning stay
// end-to-end: the relay only sees encrypted bytes.
//
// Run with:
//   dart run tool/relay_server.dart            # listens on :8080
//   PORT=9000 dart run tool/relay_server.dart  # custom port
//
// Protocol:
//   1. Both devices open a WebSocket to  ws://host:port/tunnel
//   2. Each sends its first text frame: the shared code (e.g. a device id).
//   3. The relay pairs the two sockets by code and forwards every subsequent
//      frame in both directions. Codes are single-use.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Peer {
  final WebSocketChannel channel;
  final List<dynamic> buffer = [];
  bool ready = false;
  String? code;
  _Peer(this.channel);
}

class _Pair {
  _Peer? a;
  _Peer? b;
  bool active = false;
}

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final pairs = <String, _Pair>{};

  void activate(_Pair pair) {
    if (pair.active) return;
    if (pair.a == null || pair.b == null) return;
    if (!pair.a!.ready || !pair.b!.ready) return;
    pair.active = true;
    final a = pair.a!;
    final b = pair.b!;
    for (final data in a.buffer) {
      try {
        b.channel.sink.add(data);
      } catch (_) {}
    }
    a.buffer.clear();
    for (final data in b.buffer) {
      try {
        a.channel.sink.add(data);
      } catch (_) {}
    }
    b.buffer.clear();
  }

  final router = Router()
    ..get('/health', (Request req) => Response.ok('ok\n'))
    ..get(
      '/tunnel',
      webSocketHandler((WebSocketChannel channel, String? protocol) {
        _Peer? self;
        String? selfCode;

        channel.stream.listen(
          (data) {
            // First frame carries the code.
            if (self == null) {
              String code;
              if (data is String) {
                code = data.trim();
              } else if (data is List<int>) {
                code = utf8.decode(data).trim();
              } else {
                code = data.toString().trim();
              }
              if (code.isEmpty) {
                channel.sink.close(4000, 'empty code');
                return;
              }
              selfCode = code;
              final pair = pairs.putIfAbsent(code, () => _Pair());
              if (pair.a == null) {
                self = _Peer(channel)..code = code;
                pair.a = self;
              } else if (pair.b == null) {
                self = _Peer(channel)..code = code;
                pair.b = self;
              } else {
                channel.sink.close(4001, 'code already in use');
                return;
              }
              self!.ready = true;
              activate(pair);
              return;
            }

            // Subsequent frames.
            if (self == null || selfCode == null) return;
            final pair = pairs[selfCode];
            if (pair == null) {
              // Already bridged and consumed: forward directly.
              return;
            }
            if (!pair.active) {
              final s = self!;
              s.buffer.add(data);
              activate(pair);
              return;
            }
            final other = (pair.a == self) ? pair.b : pair.a;
            if (other != null) {
              try {
                other.channel.sink.add(data);
              } catch (_) {}
            }
          },
          onDone: () {
            if (selfCode != null) {
              final pair = pairs[selfCode];
              if (pair != null) {
                if (pair.a == self) pair.a = null;
                if (pair.b == self) pair.b = null;
                if (pair.a == null && pair.b == null) pairs.remove(selfCode);
              }
            }
          },
          onError: (_) {},
          cancelOnError: false,
        );
      }),
    );

  final server = await shelf_io.serve(router.call, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('FlowDrop relay listening on ${server.address.address}:${server.port}');
}
