import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/constants.dart';
import '../protocol/device.dart';
import '../protocol/offers.dart';
import '../protocol/paths.dart';
import '../security/identity.dart';
import '../security/pairing.dart';
import '../security/trust_store.dart';
import '../transfer/checksum.dart';
import 'tls.dart';

/// Called when a peer offers files/text. The app shows an Accept/Decline
/// dialog and completes the future with the user's decision.
typedef OfferApproval = Future<bool> Function(
  OfferRequest offer,
  String remoteIp,
  bool trusted,
);

/// Local HTTPS server implementing FlowDrop Protocol v1.
///
/// Security invariants:
///  * TLS only, certificate generated from [identity].
///  * Every incoming path segment is validated before touching the disk.
///  * Files are written to a hidden staging directory and only moved into the
///    download folder after the full size and hash are verified.
///  * Clipboard pushes are accepted only from paired devices.
class FlowDropServer {
  FlowDropServer({
    required this.identity,
    required this.downloadDirectory,
    required this.onOffer,
    required this.trustStore,
    required this.tokenManager,
    required this.deviceInfoBuilder,
    this.onText,
    this.onClipboard,
    this.onEvent,
    this.maxFileSize = FlowDropProtocol.maxFileSize,
  });

  final DeviceIdentity identity;

  /// Where verified files are moved after a session completes. Mutable so the
  /// user can change the folder without restarting the server.
  String downloadDirectory;
  final OfferApproval onOffer;
  final TrustStore trustStore;
  final PairingTokenManager tokenManager;

  /// When true (visibility = trusted only), offers and text from devices
  /// that are not in the trust store are declined without a prompt.
  /// Mutable so the setting can change without restarting the server.
  bool autoDeclineUntrusted = false;

  /// Rebuilt on every request so address changes (Wi-Fi roam) are reflected.
  final DeviceInfo Function(int port) deviceInfoBuilder;

  final Future<void> Function(
    TextPayload payload,
    String remoteIp,
    bool trusted,
  )?
  onText;
  final void Function(String fromFingerprint, String data)? onClipboard;
  final void Function(ServerEvent event)? onEvent;
  final int maxFileSize;

  HttpServer? _server;
  int _port = 0;
  final Map<String, _ReceiveSession> _sessions = {};
  final Set<WebSocketChannel> _eventSockets = {};

  int get port => _port;
  bool get isRunning => _server != null;
  DeviceInfo get localDevice => deviceInfoBuilder(_port);

  Future<void> start({
    int preferredPort = FlowDropProtocol.defaultPort,
    int maxAttempts = 20,
  }) async {
    if (_server != null) return;
    final context = securityContextFromPem(
      certificatePem: identity.certificatePem,
      privateKeyPem: identity.privateKeyPem,
    );
    Object? lastError;
    for (var offset = 0; offset < maxAttempts; offset++) {
      final candidate = preferredPort + offset;
      if (candidate > 65535) break;
      try {
        _server = await shelf_io.serve(
          _buildHandler(),
          InternetAddress.anyIPv4,
          candidate,
          securityContext: context,
        );
        _port = _server!.port;
        return;
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    throw StateError('Could not bind an HTTPS port: $lastError');
  }

  Future<void> stop() async {
    for (final socket in _eventSockets.toList()) {
      try {
        await socket.sink.close();
      } on Object {
        // Already gone.
      }
    }
    _eventSockets.clear();
    for (final session in _sessions.values.toList()) {
      await _deleteQuietly(session.directory);
    }
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Handler _buildHandler() {
    final router = Router(notFoundHandler: _notFound);
    router.get('/v1/info', _handleInfo);
    router.post('/v1/pair', _handlePair);
    router.post('/v1/offer', _handleOffer);
    router.post('/v1/accept', _handleAccept);
    router.put('/v1/upload/<sessionId>/<fileId>', _handleUpload);
    router.get('/v1/status/<sessionId>', _handleStatus);
    router.post('/v1/cancel/<sessionId>', _handleCancel);
    router.post('/v1/text', _handleText);
    router.post('/v1/clipboard', _handleClipboard);
    router.get(
      '/v1/events',
      webSocketHandler(
        _handleWebSocket,
        pingInterval: const Duration(seconds: 20),
      ),
    );

    return const Pipeline()
        .addMiddleware(_noStore)
        .addMiddleware(_errorBoundary)
        .addHandler(router.call);
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Future<Response> _handleInfo(Request request) async {
    return _json(localDevice.toJson());
  }

  Future<Response> _handlePair(Request request) async {
    final PairRequest pair;
    try {
      pair = PairRequest.fromJson(await _readJson(request));
    } on FormatException catch (error) {
      return _error(400, 'bad_request', error.message);
    }
    if (!pair.device.isCompatible) {
      return _error(409, 'unsupported_version', 'Protocol version mismatch');
    }
    final remoteIp = _remoteIp(request);
    final result = tokenManager.redeem(pair.token, clientIp: remoteIp);
    switch (result) {
      case PairingResult.rateLimited:
        return _error(429, 'rate_limited', 'Too many pairing attempts');
      case PairingResult.expired:
        return _error(410, 'token_expired', 'This code has expired');
      case PairingResult.used:
        return _error(409, 'token_used', 'This code was already used');
      case PairingResult.invalid:
        return _error(401, 'unauthorized', 'Invalid pairing code');
      case PairingResult.ok:
        break;
    }

    final signatureValid = await DeviceIdentity.verifySignature(
      message: pair.token,
      signatureBase64: pair.signature,
      publicKeyBase64: pair.device.publicKey,
    );
    if (!signatureValid) {
      return _error(401, 'unauthorized', 'Invalid device signature');
    }

    await trustStore.trust(
      TrustedDevice.fromDevice(pair.device, autoAccept: pair.alwaysTrust),
    );
    return _json(
      PairResponse(ok: true, trusted: true, device: localDevice).toJson(),
    );
  }

  Future<Response> _handleOffer(Request request) async {
    final OfferRequest offer;
    try {
      offer = OfferRequest.fromJson(await _readJson(request));
    } on FormatException catch (error) {
      return _error(400, 'bad_request', error.message);
    }
    if (!offer.sender.isCompatible) {
      return _error(409, 'unsupported_version', 'Protocol version mismatch');
    }
    if (offer.totalSize > maxFileSize * FlowDropProtocol.maxFilesPerOffer) {
      return _error(413, 'too_large', 'Offer is too large');
    }
    for (final file in offer.files) {
      if (file.size > maxFileSize) {
        return _error(413, 'too_large', 'File is too large');
      }
    }
    if (!_validSessionId(offer.sessionId)) {
      return _error(400, 'bad_request', 'Invalid session id');
    }
    if (_sessions.containsKey(offer.sessionId)) {
      return _error(409, 'conflict', 'Session already exists');
    }

    final remoteIp = _remoteIp(request);
    final trusted = await trustStore.isTrusted(offer.sender.fingerprint);
    if (autoDeclineUntrusted && !trusted) {
      return _json(
        OfferResponse(
          accepted: false,
          sessionId: offer.sessionId,
          reason: 'not_trusted',
        ).toJson(),
        status: 200,
      );
    }
    final accepted = await onOffer(offer, remoteIp, trusted);
    if (!accepted) {
      return _json(
        OfferResponse(
          accepted: false,
          sessionId: offer.sessionId,
          reason: 'declined',
        ).toJson(),
        status: 200,
      );
    }

    final session = _ReceiveSession(
      id: offer.sessionId,
      offer: offer,
      directory: Directory(
        p.join(downloadDirectory, '.flowdrop_incoming', offer.sessionId),
      ),
      root: Directory(downloadDirectory),
    );
    try {
      await session.directory.create(recursive: true);
      await _planFiles(session);
    } on FormatException catch (error) {
      await _deleteQuietly(session.directory);
      return _error(400, 'bad_request', error.message);
    } on FileSystemException catch (error) {
      await _deleteQuietly(session.directory);
      return _error(500, 'internal', 'Could not prepare downloads: $error');
    }
    _sessions[offer.sessionId] = session;

    final urls = <String, String>{
      for (final file in offer.files)
        file.id: '/v1/upload/${offer.sessionId}/${file.id}',
    };
    return _json(
      OfferResponse(
        accepted: true,
        sessionId: offer.sessionId,
        uploadUrls: urls,
      ).toJson(),
    );
  }

  Future<Response> _handleAccept(Request request) async {
    final body = await _readJson(request);
    final sessionId = body['sessionId'];
    if (sessionId is! String) {
      return _error(400, 'bad_request', 'Missing session id');
    }
    final session = _sessions[sessionId];
    if (session == null) return _error(404, 'not_found', 'Unknown session');
    final urls = <String, String>{
      for (final file in session.offer.files)
        file.id: '/v1/upload/$sessionId/${file.id}',
    };
    return _json(
      OfferResponse(
        accepted: session.state != 'cancelled',
        sessionId: sessionId,
        uploadUrls: urls,
      ).toJson(),
    );
  }

  Future<Response> _handleUpload(
    Request request,
    String sessionId,
    String fileId,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) return _error(404, 'not_found', 'Unknown session');
    if (session.state == 'cancelled') {
      return _error(409, 'conflict', 'Session was cancelled');
    }
    final file = session.files[fileId];
    if (file == null) return _error(404, 'not_found', 'Unknown file');

    final offsetHeader = request.headers['x-flowdrop-offset'];
    final requestedOffset = offsetHeader == null
        ? 0
        : int.tryParse(offsetHeader);
    if (requestedOffset == null || requestedOffset < 0) {
      return _error(400, 'bad_request', 'Invalid offset');
    }
    if (request.headers['x-flowdrop-reset'] == 'true') {
      await _deleteQuietly(file.partFile);
      file.received = 0;
    }

    var currentOffset = 0;
    if (await file.partFile.exists()) {
      currentOffset = await file.partFile.length();
    }
    if (requestedOffset != currentOffset) {
      return _json({
        'error': 'conflict',
        'message': 'Offset mismatch',
        'offset': currentOffset,
      }, status: 409);
    }
    if (currentOffset > file.offer.size) {
      await _deleteQuietly(file.partFile);
      return _error(400, 'bad_request', 'Offset exceeds file size');
    }
    final contentLength = request.contentLength;
    if (contentLength != null &&
        currentOffset + contentLength > file.offer.size) {
      return _error(413, 'too_large', 'Upload exceeds declared size');
    }

    final hasher = IncrementalSha256();
    try {
      if (currentOffset > 0) {
        // Re-hash the prefix that is already on disk so the digest covers the
        // whole file after a resume.
        await addFilePrefix(hasher, file.partFile, currentOffset);
      }
    } on FileSystemException catch (error) {
      return _error(500, 'internal', 'Could not read partial file: $error');
    }

    RandomAccessFile? handle;
    try {
      handle = await file.partFile.open(mode: FileMode.append);
      final sink = handle;
      file.state = 'receiving';
      session.state = 'receiving';
      var received = currentOffset;
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in request.read()) {
        await sink.writeFrom(chunk);
        hasher.add(chunk);
        received += chunk.length;
        file.received = received;
        if (received > file.offer.size) {
          await sink.close();
          handle = null;
          await _deleteQuietly(file.partFile);
          file.state = 'failed';
          return _error(413, 'too_large', 'Upload exceeds declared size');
        }
        final now = DateTime.now();
        if (now.difference(lastEmit) >= const Duration(milliseconds: 150)) {
          lastEmit = now;
          _broadcast(
            ServerEvent.progress(
              sessionId: sessionId,
              fileId: fileId,
              received: received,
              total: file.offer.size,
            ),
          );
        }
      }
      await sink.flush();
      await sink.close();
      handle = null;

      file.received = received;
      if (received != file.offer.size) {
        file.state = 'pending';
        return _json({
          'error': 'bad_request',
          'message': 'Upload is incomplete',
          'offset': received,
        }, status: 400);
      }

      final digest = hasher.close();
      final declaredHash = request.headers['x-flowdrop-sha256'];
      if (declaredHash != null &&
          declaredHash.isNotEmpty &&
          !_constantTimeEquals(declaredHash.toLowerCase(), digest)) {
        await _deleteQuietly(file.partFile);
        file.state = 'failed';
        return _error(422, 'bad_request', 'Checksum mismatch');
      }

      await file.finalFile.parent.create(recursive: true);
      if (await file.finalFile.exists()) {
        await file.finalFile.delete();
      }
      await file.partFile.rename(file.finalFile.path);
      file.sha256 = digest;
      file.state = 'completed';

      _broadcast(
        ServerEvent.progress(
          sessionId: sessionId,
          fileId: fileId,
          received: received,
          total: file.offer.size,
        ),
      );
      if (session.files.values.every((f) => f.state == 'completed')) {
        session.state = 'completed';
        _broadcast(
          ServerEvent.completed(
            sessionId,
            savedPaths: session.files.values
                .map((f) => f.finalFile.path)
                .toList(growable: false),
          ),
        );
      }

      return _json({
        'ok': true,
        'sha256': digest,
        'size': received,
        'path': file.relativePath,
      });
    } on Object catch (error) {
      file.state = 'pending';
      await handle?.close();
      // Keep the .part file: the sender can resume from `offset`.
      return _error(500, 'internal', 'Upload failed: $error');
    }
  }

  Future<Response> _handleStatus(Request request, String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return _error(404, 'not_found', 'Unknown session');
    return _json(
      StatusResponse(
        sessionId: sessionId,
        state: session.state,
        files: session.files.values
            .map(
              (file) => FileStatus(
                id: file.offer.id,
                received: file.received,
                size: file.offer.size,
                state: file.state,
              ),
            )
            .toList(growable: false),
      ).toJson(),
    );
  }

  Future<Response> _handleCancel(Request request, String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return _error(404, 'not_found', 'Unknown session');
    session.state = 'cancelled';
    for (final file in session.files.values) {
      file.state = 'cancelled';
    }
    await _deleteQuietly(session.directory);
    _broadcast(ServerEvent.cancelled(sessionId));
    return _json({'ok': true});
  }

  Future<Response> _handleText(Request request) async {
    final payload = TextPayload.fromJson(await _readJson(request));
    if (!payload.sender.isCompatible) {
      return _error(409, 'unsupported_version', 'Protocol version mismatch');
    }
    final trusted = await trustStore.isTrusted(payload.sender.fingerprint);
    await onText?.call(payload, _remoteIp(request), trusted);
    _broadcast(ServerEvent.text(payload));
    return _json({'ok': true});
  }

  Future<Response> _handleClipboard(Request request) async {
    final payload = TextPayload.fromJson(await _readJson(request));
    final trusted = await trustStore.isTrusted(payload.sender.fingerprint);
    if (!trusted) {
      return _error(
        403,
        'unauthorized',
        'Clipboard sync requires a paired device',
      );
    }
    onClipboard?.call(payload.sender.fingerprint, payload.text);
    return _json({'ok': true});
  }

  void _handleWebSocket(WebSocketChannel channel, String? protocol) {
    _eventSockets.add(channel);
    try {
      channel.sink.add(
        jsonEncode(
          ServerEvent('hello', {'device': localDevice.toJson()}).toJson(),
        ),
      );
    } on Object {
      // The peer disconnected immediately.
    }
    channel.stream.listen(
      (message) {
        if (message is String && message == 'ping') {
          channel.sink.add('pong');
        }
      },
      onDone: () => _eventSockets.remove(channel),
      onError: (_) => _eventSockets.remove(channel),
      cancelOnError: true,
    );
  }

  Response _notFound(Request request) =>
      _error(404, 'not_found', 'Unknown endpoint');

  // ---------------------------------------------------------------------------
  // Session helpers
  // ---------------------------------------------------------------------------

  Future<void> _planFiles(_ReceiveSession session) async {
    final reserved = <String>{};
    for (final file in session.offer.files) {
      final relative = sanitizeRelativePath(
        file.relativePath == null || file.relativePath!.isEmpty
            ? sanitizeFileName(file.name)
            : file.relativePath!,
      );
      final target = await _reserveFinalFile(session.root, relative, reserved);
      session.files[file.id] = _ReceiveFile(
        offer: file,
        relativePath: relative,
        partFile: File(p.join(session.directory.path, '${file.id}.part')),
        finalFile: target,
      );
    }
  }

  /// Resolves a safe destination and reserves its lowercase path.
  Future<File> _reserveFinalFile(
    Directory root,
    String relativePath,
    Set<String> reserved,
  ) async {
    final rootPath = p.normalize(root.absolute.path);
    var candidate = File(p.joinAll([rootPath, ...relativePath.split('/')]));
    final candidatePath = p.normalize(candidate.absolute.path);
    if (!_isInside(rootPath, candidatePath)) {
      throw const FormatException('Path escapes the download folder');
    }

    final directory = candidate.parent;
    if (!_isInside(rootPath, p.normalize(directory.absolute.path))) {
      throw const FormatException('Path escapes the download folder');
    }
    await directory.create(recursive: true);

    final existing = <String>{...reserved};
    await for (final entity in directory.list(followLinks: false)) {
      existing.add(p.basename(entity.path));
    }
    final unique = dedupeFileName(p.basename(candidate.path), existing);
    candidate = File(p.join(directory.path, unique));
    reserved.add(p.join(p.dirname(relativePath), unique).toLowerCase());
    return candidate;
  }

  bool _isInside(String root, String candidate) {
    final normalizedRoot = p.normalize(root);
    final normalizedCandidate = p.normalize(candidate);
    if (Platform.isWindows) {
      final lowerRoot = normalizedRoot.toLowerCase();
      final lowerCandidate = normalizedCandidate.toLowerCase();
      return lowerCandidate == lowerRoot ||
          lowerCandidate.startsWith('$lowerRoot${p.separator}');
    }
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate.startsWith('$normalizedRoot${p.separator}');
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  void _broadcast(ServerEvent event) {
    final payload = jsonEncode(event.toJson());
    for (final socket in _eventSockets.toList()) {
      try {
        socket.sink.add(payload);
      } on Object {
        _eventSockets.remove(socket);
      }
    }
    try {
      onEvent?.call(event);
    } on Object {
      // A UI listener must never take the server down.
    }
  }

  String _remoteIp(Request request) {
    try {
      final info = request.context['shelf.io.connection_info'];
      if (info is HttpConnectionInfo) return info.remoteAddress.address;
    } on Object {
      // Fall through.
    }
    return 'unknown';
  }

  Future<Map<String, dynamic>> _readJson(
    Request request, {
    int maxBytes = 8 << 20,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('Request body is too large');
      }
    }
    final text = utf8.decode(builder.takeBytes());
    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    return decoded;
  }

  bool _validSessionId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value);

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Response _json(Object body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Response _error(
    int status,
    String code,
    String message, [
    Map<String, Object?>? extra,
  ]) {
    return _json({
      'error': code,
      'message': message,
      ...?extra,
    }, status: status);
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }

  static Middleware get _noStore =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(
          headers: {
            ...response.headers,
            'cache-control': 'no-store',
            'x-content-type-options': 'nosniff',
          },
        );
      };

  static Middleware get _errorBoundary =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } on FormatException catch (error) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'bad_request',
              'message': error.message,
            }),
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        } on Object {
          return Response(
            500,
            body: jsonEncode({
              'error': 'internal',
              'message': 'Internal server error',
            }),
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
      };
}

class _ReceiveSession {
  _ReceiveSession({
    required this.id,
    required this.offer,
    required this.directory,
    required this.root,
  });

  final String id;
  final OfferRequest offer;
  final Directory directory;
  final Directory root;
  final Map<String, _ReceiveFile> files = {};
  String state = 'pending';
}

class _ReceiveFile {
  _ReceiveFile({
    required this.offer,
    required this.relativePath,
    required this.partFile,
    required this.finalFile,
  });

  final OfferedFile offer;
  final String relativePath;
  final File partFile;
  final File finalFile;
  int received = 0;
  String state = 'pending';
  String? sha256;
}
