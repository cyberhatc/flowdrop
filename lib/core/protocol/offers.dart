import 'constants.dart';
import 'device.dart';

class OfferedFile {
  const OfferedFile({
    required this.id,
    required this.name,
    required this.size,
    this.mime = 'application/octet-stream',
    this.relativePath,
  });

  final String id;
  final String name;
  final int size;
  final String mime;

  /// For folder transfers: a sanitized relative path such as `trip/a.jpg`.
  final String? relativePath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'mime': mime,
        if (relativePath != null) 'relativePath': relativePath,
      };

  factory OfferedFile.fromJson(Map<String, dynamic> json) {
    final size = json['size'];
    if (size is! num || size < 0 || size > FlowDropProtocol.maxFileSize) {
      throw const FormatException('Invalid file size');
    }
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('Invalid file entry');
    }
    return OfferedFile(
      id: id,
      name: name,
      size: size.toInt(),
      mime: json['mime'] is String
          ? json['mime'] as String
          : 'application/octet-stream',
      relativePath:
          json['relativePath'] is String ? json['relativePath'] as String : null,
    );
  }
}

/// Metadata-only offer. Files are uploaded only after the receiver accepts.
class OfferRequest {
  const OfferRequest({
    required this.sessionId,
    required this.sender,
    required this.files,
    this.text,
  });

  final String sessionId;
  final DeviceInfo sender;
  final List<OfferedFile> files;
  final String? text;

  int get totalSize => files.fold(0, (sum, file) => sum + file.size);
  int get fileCount => files.length;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'sender': sender.toJson(),
        'text': text,
        'files': files.map((f) => f.toJson()).toList(growable: false),
        'totalSize': totalSize,
      };

  factory OfferRequest.fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId'];
    final sender = json['sender'];
    final filesJson = json['files'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException('Invalid session id');
    }
    if (sender is! Map<String, dynamic>) {
      throw const FormatException('Invalid sender');
    }
    if (filesJson is! List<dynamic> ||
        filesJson.length > FlowDropProtocol.maxFilesPerOffer) {
      throw const FormatException('Invalid file list');
    }
    final files = <OfferedFile>[];
    final seenIds = <String>{};
    for (final entry in filesJson) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid file entry');
      }
      final file = OfferedFile.fromJson(entry);
      if (!seenIds.add(file.id)) {
        throw const FormatException('Duplicate file id');
      }
      files.add(file);
    }
    final text = json['text'];
    if (text != null && text is! String) {
      throw const FormatException('Invalid text');
    }
    if (text != null && text.length > FlowDropProtocol.maxTextBytes) {
      throw const FormatException('Text too large');
    }
    if (files.isEmpty && (text == null || text.isEmpty)) {
      throw const FormatException('Offer is empty');
    }
    return OfferRequest(
      sessionId: sessionId,
      sender: DeviceInfo.fromJson(sender),
      files: List.unmodifiable(files),
      text: text,
    );
  }
}

class OfferResponse {
  const OfferResponse({
    required this.accepted,
    required this.sessionId,
    this.reason,
    this.uploadUrls = const {},
  });

  final bool accepted;
  final String sessionId;
  final String? reason;
  final Map<String, String> uploadUrls;

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'sessionId': sessionId,
        if (reason != null) 'reason': reason,
        if (uploadUrls.isNotEmpty) 'uploadUrls': uploadUrls,
      };

  factory OfferResponse.fromJson(Map<String, dynamic> json) {
    final accepted = json['accepted'];
    final sessionId = json['sessionId'];
    if (accepted is! bool || sessionId is! String) {
      throw const FormatException('Invalid offer response');
    }
    final urls = <String, String>{};
    final rawUrls = json['uploadUrls'];
    if (rawUrls is Map<String, dynamic>) {
      for (final entry in rawUrls.entries) {
        if (entry.value is String) {
          urls[entry.key] = entry.value as String;
        }
      }
    }
    return OfferResponse(
      accepted: accepted,
      sessionId: sessionId,
      reason: json['reason'] is String ? json['reason'] as String : null,
      uploadUrls: Map.unmodifiable(urls),
    );
  }
}

class TextPayload {
  const TextPayload({required this.sender, required this.text});

  final DeviceInfo sender;
  final String text;

  Map<String, dynamic> toJson() => {
        'sender': sender.toJson(),
        'text': text,
      };

  factory TextPayload.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    final text = json['text'];
    if (sender is! Map<String, dynamic> || text is! String) {
      throw const FormatException('Invalid text payload');
    }
    if (text.length > FlowDropProtocol.maxTextBytes) {
      throw const FormatException('Text too large');
    }
    return TextPayload(sender: DeviceInfo.fromJson(sender), text: text);
  }
}

class PairRequest {
  const PairRequest({
    required this.token,
    required this.device,
    required this.signature,
    this.alwaysTrust = false,
  });

  final String token;
  final DeviceInfo device;

  /// Base64 Ed25519 signature over the UTF-8 token using `device.publicKey`.
  final String signature;
  final bool alwaysTrust;

  Map<String, dynamic> toJson() => {
        'token': token,
        'device': device.toJson(),
        'signature': signature,
        'alwaysTrust': alwaysTrust,
      };

  factory PairRequest.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final device = json['device'];
    final signature = json['signature'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Invalid token');
    }
    if (device is! Map<String, dynamic>) {
      throw const FormatException('Invalid device');
    }
    if (signature is! String || signature.isEmpty) {
      throw const FormatException('Invalid signature');
    }
    return PairRequest(
      token: token,
      device: DeviceInfo.fromJson(device),
      signature: signature,
      alwaysTrust: json['alwaysTrust'] == true,
    );
  }
}

class PairResponse {
  const PairResponse({
    required this.ok,
    required this.trusted,
    this.device,
    this.error,
  });

  final bool ok;
  final bool trusted;
  final DeviceInfo? device;
  final String? error;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'trusted': trusted,
        if (device != null) 'device': device!.toJson(),
        if (error != null) 'error': error,
      };

  factory PairResponse.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    return PairResponse(
      ok: json['ok'] == true,
      trusted: json['trusted'] == true,
      device:
          device is Map<String, dynamic> ? DeviceInfo.fromJson(device) : null,
      error: json['error'] is String ? json['error'] as String : null,
    );
  }
}

class FileStatus {
  const FileStatus({
    required this.id,
    required this.received,
    required this.size,
    required this.state,
  });

  final String id;
  final int received;
  final int size;

  /// `pending`, `receiving`, `completed`, `failed` or `cancelled`.
  final String state;

  Map<String, dynamic> toJson() => {
        'id': id,
        'received': received,
        'size': size,
        'state': state,
      };
}

class StatusResponse {
  const StatusResponse({
    required this.sessionId,
    required this.state,
    required this.files,
  });

  final String sessionId;

  /// `pending`, `receiving`, `completed` or `cancelled`.
  final String state;
  final List<FileStatus> files;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'state': state,
        'files': files.map((f) => f.toJson()).toList(growable: false),
      };
}

/// Server -> client realtime events delivered on `/v1/events`.
class ServerEvent {
  const ServerEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {'type': type, ...data};

  factory ServerEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) throw const FormatException('Missing event type');
    return ServerEvent(type, Map<String, dynamic>.from(json)..remove('type'));
  }

  static ServerEvent offer(OfferRequest offer) =>
      ServerEvent('offer', {'offer': offer.toJson()});
  static ServerEvent progress({
    required String sessionId,
    required String fileId,
    required int received,
    required int total,
  }) =>
      ServerEvent('progress', {
        'sessionId': sessionId,
        'fileId': fileId,
        'received': received,
        'total': total,
      });
  static ServerEvent completed(String sessionId) =>
      ServerEvent('completed', {'sessionId': sessionId});
  static ServerEvent cancelled(String sessionId) =>
      ServerEvent('cancelled', {'sessionId': sessionId});
  static ServerEvent text(TextPayload payload) =>
      ServerEvent('text', payload.toJson());
  static ServerEvent clipboard({
    required String fingerprint,
    required String data,
  }) =>
      ServerEvent('clipboard', {'from': fingerprint, 'data': data});
  static ServerEvent ping() =>
      ServerEvent('ping', {'at': DateTime.now().millisecondsSinceEpoch});
}
