// Minimal internal client used by the public helper.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;

class DevToolsClient {
  final String host;
  final int port;
  final bool showLogs;
  WebSocket? _ws;
  StreamSubscription? _sub;
  String? _lastDbPath;

  DevToolsClient({
    this.host = '10.0.2.2',
    this.port = 38947,
    this.showLogs = true,
  });

  // ANSI colors for terminal output
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _cyan = '\x1B[36m';
  static const _yellow = '\x1B[33m';
  static const _green = '\x1B[32m';
  static const _magenta = '\x1B[35m';

  void _log(String color, String label, String message) {
    if (!showLogs) return;
    final out = '$color$label$_reset $message';
    print(out);
  }

  void _info(String message) => _log(_cyan, 'INFO:', message);
  void _warn(String message) => _log(_yellow, 'WARN:', message);
  void _success(String message) => _log(_green, 'OK:', message);

  String get _url => 'ws://$host:$port';

  Future<void> connect({Duration? timeout}) async {
    if (_ws != null) return;
    _ws = await WebSocket.connect(
      _url,
    ).timeout(timeout ?? const Duration(seconds: 5));
    _sub = _ws!.listen(
      (dynamic data) async {
        try {
          final msg = jsonDecode(data.toString());
          final type = msg['type'];
          if (type == 'request_table') {
            final table = msg['table'] as String?;
            final limit = (msg['limit'] is int) ? msg['limit'] as int : 200;
            if (table != null && _lastDbPath != null) {
              try {
                final db = await sqflite.openDatabase(
                  _lastDbPath!,
                  readOnly: true,
                );
                try {
                  final rows = await db.rawQuery(
                    'SELECT * FROM "$table" LIMIT ?;',
                    [limit],
                  );
                  final safeRows = rows.map((r) {
                    final map = <String, dynamic>{};
                    r.forEach((k, v) {
                      if (v is List<int>) {
                        map[k] = '[BLOB]';
                      } else {
                        map[k] = v;
                      }
                    });
                    return map;
                  }).toList();
                  _info('Sending ${safeRows.length} row(s) for table $table');
                  _send({
                    'type': 'table_data',
                    'table': table,
                    'rows': safeRows,
                  });
                } finally {
                  await db.close();
                }
              } catch (e) {
                _warn('Failed to serve table request for $table: $e');
                // Inform the extension that serving failed
                _send({
                  'type': 'table_data',
                  'table': table,
                  'rows': [],
                  'error': 'query_failed',
                });
              }
            } else if (table != null) {
              // No DB path available to query; inform the extension so UI can show an informative message
              try {
                _send({
                  'type': 'table_data',
                  'table': table,
                  'rows': [],
                  'error': 'no_db_path',
                });
              } catch (_) {}
            }
          }
        } catch (_) {}
      },
      onDone: _cleanup,
      onError: (_) => _cleanup(),
      cancelOnError: true,
    );
    // send hello so extension knows who's connecting
    _info('Connected to devtools server: $_url');
    _send({'type': 'hello', 'appId': 'flutter_app', 'version': '1.0'});
  }

  void _send(Map<String, dynamic> msg) {
    if (_ws == null) return;
    try {
      _ws!.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> sendDbFile(File f) async {
    if (_ws == null) return;
    _info('Preparing to send DB file: ${f.path}');
    _lastDbPath = f.path;
    final bytes = await f.readAsBytes();
    _send({
      'type': 'db_file_meta',
      'name': f.uri.pathSegments.last,
      'size': bytes.length,
      'encoding': 'none',
    });

    // Try to open the DB read-only and print a short summary (tables, cols, sample, counts).
    try {
      final db = await sqflite.openDatabase(f.path, readOnly: true);
      try {
        final tablesRaw = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
        );
        final tables = tablesRaw
            .map((r) => r['name'])
            .whereType<String>()
            .toList();

        // Send tables list so the extension can update the tree immediately
        try {
          _send({'type': 'tables', 'tables': tables});
        } catch (_) {}

        _info('Found ${tables.length} table(s) in DB:');
        for (final t in tables) {
          try {
            final countRaw = await db.rawQuery(
              'SELECT COUNT(*) as c FROM "$t";',
            );
            final rowCount = (countRaw.first['c'] as num?)?.toInt() ?? 0;

            final colsRaw = await db.rawQuery('PRAGMA table_info("$t");');
            final cols = colsRaw
                .map((r) => r['name'])
                .whereType<String>()
                .toList();

            // Table header
            final header = 'Table: $t ($rowCount rows, ${cols.length} cols)';
            _log(_magenta, '${_bold}TABLE:', header);

            // Columns line
            _log(_cyan, 'COLUMNS:', cols.join(', '));

            // Sample row (mask blobs)
            final sample = await db.rawQuery('SELECT * FROM "$t" LIMIT 1;');
            if (sample.isNotEmpty) {
              final row = sample.first;
              final preview = row.map((k, v) {
                if (v is List<int>) return MapEntry(k, '[BLOB]');
                return MapEntry(k, v?.toString() ?? 'null');
              });
              _log(_yellow, 'SAMPLE:', preview.toString());
            } else {
              _log(_yellow, 'SAMPLE:', '<empty>');
            }
          } catch (e) {
            _warn('Could not inspect table $t: $e');
          }
        }
      } finally {
        await db.close();
      }
    } catch (e) {
      _warn('Unable to open DB for inspection: $e');
    }

    const chunk = 64 * 1024;
    var sent = 0;
    final totalChunks = (bytes.length / chunk).ceil();
    var chunkIndex = 0;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk) > bytes.length ? bytes.length : i + chunk;
      final part = base64Encode(bytes.sublist(i, end));
      final last = end == bytes.length;
      _send({'type': 'db_file_chunk', 'data': part, 'final': last});
      sent += (end - i);
      chunkIndex += 1;
      if (chunkIndex % 4 == 0 || last) {
        _info(
          'Uploading... ${((sent / bytes.length) * 100).toStringAsFixed(0)}% ($chunkIndex/$totalChunks)',
        );
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _success(
      'Upload complete: ${f.uri.pathSegments.last} (${bytes.length} bytes)',
    );
  }

  Future<void> close() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  void _cleanup() {
    _sub = null;
    _ws = null;
  }
}
