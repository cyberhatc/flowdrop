import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../protocol/offers.dart';
import '../transfer/transfer_models.dart';

/// SQLite-backed transfer history.
///
/// Only metadata is stored, never file contents. The store is deliberately
/// small and hand-written so it works in tests without code generation.
class HistoryStore {
  HistoryStore._(this._db);

  final Database _db;

  static const int _maxRows = 1000;

  /// Opens (and migrates) the database at [path].
  factory HistoryStore.open(String path) {
    final directory = Directory(File(path).parent.path);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return HistoryStore._(sqlite3.open(path)).._migrate();
  }

  /// In-memory database, used by tests and as a fallback.
  factory HistoryStore.inMemory() {
    return HistoryStore._(sqlite3.openInMemory()).._migrate();
  }

  void _migrate() {
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS transfers (
        id TEXT PRIMARY KEY,
        peer_name TEXT NOT NULL,
        peer_device_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        files_json TEXT NOT NULL,
        total_bytes INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        state TEXT NOT NULL,
        saved_path TEXT,
        text_preview TEXT
      );
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS transfers_started_at '
      'ON transfers (started_at DESC);',
    );
  }

  /// Inserts or replaces [record] (used for progress -> completion updates).
  void upsert(TransferRecord record) {
    _db.execute(
      '''
      INSERT INTO transfers (
        id, peer_name, peer_device_id, direction, files_json,
        total_bytes, started_at, finished_at, state, saved_path, text_preview
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        state = excluded.state,
        finished_at = excluded.finished_at,
        saved_path = excluded.saved_path,
        total_bytes = excluded.total_bytes
      ''',
      [
        record.id,
        record.peerName,
        record.peerDeviceId,
        record.direction.name,
        jsonEncode(record.files.map((file) => file.toJson()).toList()),
        record.totalBytes,
        record.startedAt.toIso8601String(),
        record.finishedAt?.toIso8601String(),
        record.state.name,
        record.savedPath,
        record.textPreview,
      ],
    );
    _trim();
  }

  void _trim() {
    final count = _db.select('SELECT COUNT(*) AS c FROM transfers;').first['c'];
    if (count is int && count > _maxRows) {
      _db.execute(
        'DELETE FROM transfers WHERE id IN ('
        'SELECT id FROM transfers ORDER BY started_at ASC LIMIT ?);',
        [count - _maxRows],
      );
    }
  }

  List<TransferRecord> recent({int limit = 100}) {
    final rows = _db.select(
      'SELECT * FROM transfers ORDER BY started_at DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  int get count =>
      _db.select('SELECT COUNT(*) AS c FROM transfers;').first['c'] as int? ??
      0;

  TransferRecord _fromRow(Row row) {
    final filesJson = row['files_json'] as String? ?? '[]';
    final files = <OfferedFile>[];
    try {
      final decoded = jsonDecode(filesJson);
      if (decoded is List<dynamic>) {
        for (final entry in decoded) {
          if (entry is Map<String, dynamic>) {
            files.add(OfferedFile.fromJson(entry));
          }
        }
      }
    } on Object {
      // Corrupt history must not crash the app.
    }
    final startedAt =
        DateTime.tryParse(row['started_at'] as String? ?? '') ?? DateTime.now();
    final finishedRaw = row['finished_at'] as String?;
    return TransferRecord(
      id: row['id'] as String? ?? '',
      peerName: row['peer_name'] as String? ?? 'Unknown device',
      peerDeviceId: row['peer_device_id'] as String? ?? '',
      direction: TransferDirection.values.firstWhere(
        (value) => value.name == row['direction'],
        orElse: () => TransferDirection.received,
      ),
      files: files,
      totalBytes: row['total_bytes'] as int? ?? 0,
      startedAt: startedAt,
      finishedAt: finishedRaw == null ? null : DateTime.tryParse(finishedRaw),
      state: TransferState.values.firstWhere(
        (value) => value.name == row['state'],
        orElse: () => TransferState.completed,
      ),
      savedPath: row['saved_path'] as String?,
      textPreview: row['text_preview'] as String?,
    );
  }

  void clear() => _db.execute('DELETE FROM transfers;');

  void delete(String id) =>
      _db.execute('DELETE FROM transfers WHERE id = ?;', [id]);

  void close() => _db.close();
}
