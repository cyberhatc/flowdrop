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
//   Both devices connect to  ws://host:port/tunnel
//   with the subprotocol  flowdrop-relay-<CODE>
//   (e.g. flowdrop-relay-a1b2c3). The first connection for a code becomes
//   the host, the second becomes the guest; they are then bridged. Codes are
//   single-use.
//
// NOTE: client-side tunneling through this relay is not wired into the app
// yet. For now this is a building block + documentation; see
// docs/REMOTE_TRANSFER.md.

import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Pair {
  WebSocketChannel? first;
  WebSocketChannel? second;
}

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final pairs = <String, _Pair>{};

  final router = Router()
    ..get('/health', (Request req) => Response.ok('ok\n'))
    ..get(
      '/tunnel',
      webSocketHandler((WebSocketChannel channel, String? protocol) {
        final code = _codeFromProtocol(protocol);
        if (code == null) {
          channel.sink.close(4000, 'missing flowdrop-relay-<code> subprotocol');
          return;
        }

        final pair = pairs.putIfAbsent(code, () => _Pair());

        if (pair.first == null) {
          pair.first = channel;
        } else if (pair.second == null) {
          pair.second = channel;
          pairs.remove(code);
          _bridge(pair.first!, pair.second!);
        } else {
          channel.sink.close(4001, 'code already in use');
          return;
        }

        Timer(const Duration(minutes: 2), () {
          if (pairs.containsKey(code)) {
            final p = pairs.remove(code);
            p?.first?.sink.close(4002, 'timeout waiting for peer');
            p?.second?.sink.close(4002, 'timeout waiting for peer');
          }
        });
      }),
    );

  final server = await shelf_io.serve(
    router.call,
    InternetAddress.anyIPv4,
    port,
  );
  // ignore: avoid_print
  print('FlowDrop relay listening on ${server.address.address}:${server.port}');
}

String? _codeFromProtocol(String? protocol) {
  if (protocol == null) return null;
  if (protocol.startsWith('flowdrop-relay-')) {
    final code = protocol.substring('flowdrop-relay-'.length);
    return code.isEmpty ? null : code;
  }
  if (protocol.startsWith('flowdrop-relay')) return null;
  return protocol.isEmpty ? null : protocol;
}

void _bridge(WebSocketChannel a, WebSocketChannel b) {
  a.stream.listen(
    (data) => b.sink.add(data),
    onDone: () => b.sink.close(),
    onError: (_) => b.sink.close(),
    cancelOnError: true,
  );
  b.stream.listen(
    (data) => a.sink.add(data),
    onDone: () => a.sink.close(),
    onError: (_) => a.sink.close(),
    cancelOnError: true,
  );
}
