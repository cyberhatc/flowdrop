import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../discovery/qr_payload.dart';
import '../protocol/constants.dart';
import '../protocol/device.dart';
import '../protocol/offers.dart';
import '../security/fingerprint.dart';
import '../security/identity.dart';
import '../transfer/checksum.dart';
import 'tls.dart';

class FlowDropException implements Exception {
  FlowDropException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'FlowDropException($code, $message)';
}

class UploadResult {
  const UploadResult({
    required this.sha256,
    required this.size,
    this.savedPath,
  });

  final String sha256;
  final int size;
  final String? savedPath;
}

class _JsonReply {
  const _JsonReply(this.statusCode, this.body);
  final int statusCode;
  final Map<String, dynamic> body;
}

/// Client for one remote FlowDrop server.
///
/// The client is bound to a certificate fingerprint. It cannot be constructed
/// without one, which is what makes the QR/manual pairing MITM-resistant.
class FlowDropClient {
  FlowDropClient({
    required String host,
    required int port,
    required this.identity,
    required this.localDevice,
    required String expectedFingerprint,
  }) : host = host,
       port = port,
       expectedFingerprint = normalizeFingerprint(expectedFingerprint),
       _base = Uri(scheme: 'https', host: host, port: port) {
    _http = createPinnedHttpClient(
      expectedFingerprint: expectedFingerprint,
      connectionTimeout: const Duration(seconds: 8),
    );
  }

  final String host;
  final int port;
  final DeviceIdentity identity;
  final DeviceInfo localDevice;
  final String expectedFingerprint;
  final Uri _base;
  late final HttpClient _http;
  bool _closed = false;

  /// Fetches and validates the remote identity.
  Future<DeviceInfo> info() async {
    final reply = await _sendJson('GET', '/v1/info');
    final device = DeviceInfo.fromJson(reply.body);
    if (!device.isCompatible) {
      throw FlowDropException(
        'unsupported_version',
        'This device speaks protocol ${device.protocolVersion}, not ${FlowDropProtocol.version}',
      );
    }
    if (!fingerprintsEqual(device.fingerprint, expectedFingerprint) &&
        !device.fingerprint.startsWith(expectedFingerprint)) {
      throw FlowDropException(
        'fingerprint_mismatch',
        'The device certificate does not match the scanned fingerprint',
      );
    }
    return device;
  }

  /// Redeems the one-time token from a QR code and signs it with our key.
  Future<PairResponse> pair({
    required QrPayload payload,
    bool alwaysTrust = false,
  }) async {
    final signature = await identity.sign(payload.token);
    final reply = await _sendJson(
      'POST',
      '/v1/pair',
      body: PairRequest(
        token: payload.token,
        device: localDevice,
        signature: signature,
        alwaysTrust: alwaysTrust,
      ).toJson(),
    );
    return PairResponse.fromJson(reply.body);
  }

  Future<OfferResponse> offer(OfferRequest offer) async {
    final reply = await _sendJson('POST', '/v1/offer', body: offer.toJson());
    return OfferResponse.fromJson(reply.body);
  }

  /// Streams one file, resuming automatically if the receiver reports a
  /// different offset. The digest covers the whole file and is compared with
  /// the value returned by the receiver.
  Future<UploadResult> uploadFile({
    required OfferedFile file,
    required String localPath,
    required String uploadPath,
    int startOffset = 0,
    void Function(int sent, int total)? onProgress,
  }) async {
    final diskFile = File(localPath);
    final size = await diskFile.length();
    if (size != file.size) {
      throw FlowDropException(
        'size_changed',
        'The file changed on disk since it was selected',
      );
    }

    var offset = startOffset.clamp(0, file.size).toInt();
    for (var attempt = 0; attempt < 4; attempt++) {
      final hasher = IncrementalSha256();
      if (offset > 0) {
        await addFilePrefix(hasher, diskFile, offset);
      }

      final request = await _http.openUrl(
        'PUT',
        _base.replace(path: uploadPath),
      );
      request.headers.contentType = ContentType.binary;
      request.headers.set('x-flowdrop-offset', '$offset');
      request.contentLength = file.size - offset;

      var sent = offset;
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await request.addStream(
          diskFile.openRead(offset).map((chunk) {
            hasher.add(chunk);
            sent += chunk.length;
            final now = DateTime.now();
            if (onProgress != null &&
                now.difference(lastEmit) >= const Duration(milliseconds: 100)) {
              lastEmit = now;
              onProgress(sent, file.size);
            }
            return chunk;
          }),
        );
      } on Object catch (error) {
        throw FlowDropException('network_error', 'Upload failed: $error');
      }

      final response = await request.close();
      final reply = await _decode(response);
      if (response.statusCode == 409) {
        final nextOffset = reply.body['offset'];
        if (nextOffset is num && nextOffset.toInt() != offset) {
          offset = nextOffset.toInt().clamp(0, file.size).toInt();
          continue;
        }
      }
      if (response.statusCode != 200) {
        throw _exceptionFrom(reply);
      }
      onProgress?.call(file.size, file.size);

      final digest = hasher.close();
      final serverDigest = reply.body['sha256'];
      if (serverDigest is! String ||
          reply.body['size'] != file.size ||
          !_constantTimeEquals(serverDigest.toLowerCase(), digest)) {
        throw FlowDropException(
          'checksum_mismatch',
          'The file did not arrive intact. Try again.',
        );
      }
      return UploadResult(
        sha256: digest,
        size: file.size,
        savedPath: reply.body['path'] as String?,
      );
    }
    throw FlowDropException(
      'resume_failed',
      'Could not agree on a resume offset with the receiver',
    );
  }

  Future<void> sendText(String text) async {
    await _sendJson(
      'POST',
      '/v1/text',
      body: TextPayload(sender: localDevice, text: text).toJson(),
    );
  }

  Future<void> sendClipboard(String text) async {
    await _sendJson(
      'POST',
      '/v1/clipboard',
      body: TextPayload(sender: localDevice, text: text).toJson(),
    );
  }

  Future<StatusResponse> status(String sessionId) async {
    final reply = await _sendJson('GET', '/v1/status/$sessionId');
    final raw = reply.body;
    final files = <FileStatus>[];
    final rawFiles = raw['files'];
    if (rawFiles is List<dynamic>) {
      for (final entry in rawFiles) {
        if (entry is Map<String, dynamic>) {
          files.add(
            FileStatus(
              id: entry['id'] as String? ?? '',
              received: entry['received'] as int? ?? 0,
              size: entry['size'] as int? ?? 0,
              state: entry['state'] as String? ?? 'pending',
            ),
          );
        }
      }
    }
    return StatusResponse(
      sessionId: sessionId,
      state: raw['state'] as String? ?? 'unknown',
      files: files,
    );
  }

  Future<void> cancel(String sessionId) async {
    await _sendJson('POST', '/v1/cancel/$sessionId');
  }

  /// Opens the realtime control channel. The caller owns the socket and must
  /// close it.
  Future<WebSocket> openEvents() async {
    return WebSocket.connect(
      _base.replace(scheme: 'wss', path: '/v1/events').toString(),
      customClient: _http,
    );
  }

  Future<DeviceInfo> fetchInfo() => info();

  /// Generates a session id for a new offer.
  static String newSessionId() => const Uuid().v4();

  Future<_JsonReply> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_closed) {
      throw FlowDropException('closed', 'Client is closed');
    }
    final request = await _http
        .openUrl(method, _base.replace(path: path))
        .timeout(timeout);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(timeout);
    final reply = await _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFrom(reply);
    }
    return reply;
  }

  Future<_JsonReply> _decode(HttpClientResponse response) async {
    final text = await utf8.decoder.bind(response).join();
    Map<String, dynamic> body = const {};
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        body = {'message': 'The device sent an unreadable response'};
      }
    }
    return _JsonReply(response.statusCode, body);
  }

  FlowDropException _exceptionFrom(_JsonReply reply) {
    return FlowDropException(
      reply.body['error'] as String? ?? 'http_${reply.statusCode}',
      reply.body['message'] as String? ?? 'Request failed',
      statusCode: reply.statusCode,
    );
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
  }
}
