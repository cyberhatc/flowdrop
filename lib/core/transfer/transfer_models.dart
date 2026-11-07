import '../protocol/offers.dart';

/// Direction of a completed transfer, used by history.
enum TransferDirection { sent, received }

/// One entry in the transfer history. Deliberately small: it stores metadata,
/// never file contents.
class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.peerName,
    required this.peerDeviceId,
    required this.direction,
    required this.files,
    required this.totalBytes,
    required this.startedAt,
    this.finishedAt,
    this.state = TransferState.completed,
    this.savedPath,
    this.textPreview,
  });

  final String id;
  final String peerName;
  final String peerDeviceId;
  final TransferDirection direction;
  final List<OfferedFile> files;
  final int totalBytes;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final TransferState state;
  final String? savedPath;
  final String? textPreview;

  TransferRecord copyWith({
    TransferState? state,
    DateTime? finishedAt,
    String? savedPath,
  }) {
    return TransferRecord(
      id: id,
      peerName: peerName,
      peerDeviceId: peerDeviceId,
      direction: direction,
      files: files,
      totalBytes: totalBytes,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      state: state ?? this.state,
      savedPath: savedPath ?? this.savedPath,
      textPreview: textPreview,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerName': peerName,
    'peerDeviceId': peerDeviceId,
    'direction': direction.name,
    'files': files.map((f) => f.toJson()).toList(growable: false),
    'totalBytes': totalBytes,
    'startedAt': startedAt.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    'state': state.name,
    if (savedPath != null) 'savedPath': savedPath,
    if (textPreview != null) 'textPreview': textPreview,
  };

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'] as String,
      peerName: json['peerName'] as String? ?? 'Unknown device',
      peerDeviceId: json['peerDeviceId'] as String? ?? '',
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TransferDirection.received,
      ),
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OfferedFile.fromJson)
          .toList(growable: false),
      totalBytes: json['totalBytes'] as int? ?? 0,
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      state: TransferState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => TransferState.completed,
      ),
      savedPath: json['savedPath'] as String?,
      textPreview: json['textPreview'] as String?,
    );
  }
}

enum TransferState { pending, active, completed, failed, cancelled, declined }

/// Live progress for one file.
class FileProgress {
  const FileProgress({
    required this.fileId,
    required this.name,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.bytesPerSecond = 0,
    this.state = TransferState.pending,
    this.error,
  });

  final String fileId;
  final String name;
  final int totalBytes;
  final int transferredBytes;
  final double bytesPerSecond;
  final TransferState state;
  final String? error;

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = transferredBytes / totalBytes;
    return value.clamp(0, 1).toDouble();
  }

  Duration? get eta {
    if (bytesPerSecond <= 0 || totalBytes <= 0) return null;
    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / bytesPerSecond).ceil());
  }

  FileProgress copyWith({
    int? transferredBytes,
    double? bytesPerSecond,
    TransferState? state,
    String? error,
  }) {
    return FileProgress(
      fileId: fileId,
      name: name,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      state: state ?? this.state,
      error: error ?? this.error,
    );
  }
}

/// Aggregate progress for a session, consumed by the transfer screen.
class SessionProgress {
  const SessionProgress({
    required this.sessionId,
    required this.peerName,
    required this.files,
    this.state = TransferState.active,
    this.text,
    this.direction,
    this.savedPaths = const [],
  });

  final String sessionId;
  final String peerName;
  final List<FileProgress> files;
  final TransferState state;
  final String? text;

  /// `sent` for outgoing sessions, `received` for incoming ones. Null when the
  /// session was restored from history.
  final TransferDirection? direction;

  /// Final saved paths for received files, from the server completion event.
  final List<String> savedPaths;

  /// First saved file, or null for outgoing/pending sessions.
  String? get firstSavedPath => savedPaths.isEmpty ? null : savedPaths.first;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.totalBytes);
  int get transferredBytes =>
      files.fold(0, (sum, file) => sum + file.transferredBytes);
  double get fraction => totalBytes == 0
      ? (state == TransferState.completed ? 1 : 0)
      : (transferredBytes / totalBytes).clamp(0, 1).toDouble();
  double get bytesPerSecond =>
      files.fold(0.0, (sum, file) => sum + file.bytesPerSecond);

  SessionProgress copyWith({
    List<FileProgress>? files,
    TransferState? state,
    List<String>? savedPaths,
  }) {
    return SessionProgress(
      sessionId: sessionId,
      peerName: peerName,
      files: files ?? this.files,
      state: state ?? this.state,
      text: text,
      direction: direction,
      savedPaths: savedPaths ?? this.savedPaths,
    );
  }
}
