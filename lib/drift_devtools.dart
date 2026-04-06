/// Public API for sending a local DB file to the Drift Studio VS Code extension.
///
/// Usage (in your app):
/// ```dart
/// import 'package:drift_devtools/drift_devtools.dart';
///
/// // only call in debug or behind a flag
/// await sendDbFileToDevTools('/data/data/com.example/databases/app.db');
/// ```
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'src/devtools_client.dart';

/// Connects to the extension dev server and sends the DB file at [dbPath].
/// No-op in release builds.
/// Sends the DB file at [dbPath] to the Drift Studio dev server.
///
/// If [keepConnection] is `true`, the helper will keep the underlying
/// `DevToolsClient` connected and return it so the caller can reuse it to
/// respond to `request_table` messages. When `keepConnection` is `false` (the
/// default), the connection is closed after upload and the function returns
/// `null`.
Future<DevToolsClient?> sendDbFileToDevTools(
  String dbPath, {
  String host = '10.0.2.2',
  int port = 38947,
  bool showLogs = true,
  bool keepConnection = false,
}) async {
  if (kReleaseMode) return null; // never run in release
  final file = File(dbPath);
  if (!await file.exists()) {
    throw ArgumentError.value(dbPath, 'dbPath', 'File does not exist');
  }

  final client = DevToolsClient(host: host, port: port, showLogs: showLogs);
  await client.connect();
  await client.sendDbFile(file);

  if (keepConnection) {
    // Return the connected client so the caller can reuse it and close later.
    return client;
  }

  // Close immediately when not keeping the connection.
  await client.close();
  return null;
}

/// Convenience wrapper that attempts to find the typical sqflite DB path
/// using the provided [dbName]. If you know the path, call
/// `sendDbFileToDevTools(dbPath)` directly.
Future<void> sendNamedDbToDevTools(
  String dbName, {
  String host = '10.0.2.2',
  int port = 38947,
  bool showLogs = true,
}) async {
  if (kReleaseMode) return;
  if (kReleaseMode) return;
  // Prefer explicit dbPath. This helper will attempt to locate common paths
  // but behavior varies by project. For Drift-backed apps prefer
  // `sendDriftDbToDevTools(generatedDb)` below.
  throw ArgumentError(
    'sendNamedDbToDevTools is not implemented. Use sendDbFileToDevTools(dbPath) or sendDriftDbToDevTools(generatedDb).',
  );
}

// Placeholder to avoid static import complexities; prefer calling sendDbFileToDevTools with a path.
Future<void> Function()? importLibrary;

/// Attempt to detect and send a Drift database file to the extension.
///
/// - `generatedDb`: a `GeneratedDatabase` instance from your app (pass it when available).
/// - `dbPath`: optional explicit path to the DB file. If provided, it is used directly.
/// - `dbName`: fallback name when locating files created by `sqflite`.
Future<void> sendDriftDbToDevTools(
  dynamic generatedDb, {
  String? dbPath,
  String dbName = 'app.db',
  String? Function(dynamic generatedDb)? extractor,
  String host = '10.0.2.2',
  int port = 38947,
}) async {
  if (kReleaseMode) return;

  // If caller provided an explicit path, use it.
  if (dbPath != null) {
    await sendDbFileToDevTools(dbPath, host: host, port: port);
    return;
  }

  String? pathToSend;

  // If caller provided an extractor callback, prefer its result.
  if (extractor != null) {
    try {
      final extracted = extractor(generatedDb);
      if (extracted is String && extracted.isNotEmpty) {
        pathToSend = extracted;
      }
    } catch (_) {}
  }

  // Try to extract the underlying executor/file from the GeneratedDatabase
  if (pathToSend == null && generatedDb != null) {
    try {
      final exec = (generatedDb as dynamic).executor;
      if (exec != null) {
        // Try several common fields used by Drift/backing executors.
        try {
          final f = (exec as dynamic).file;
          if (f is String) pathToSend = f;
          if (f is File) pathToSend = f.path;
        } catch (_) {}

        if (pathToSend == null) {
          try {
            final pth = (exec as dynamic).databasePath;
            if (pth is String) pathToSend = pth;
          } catch (_) {}
        }

        if (pathToSend == null) {
          try {
            // Alternative field names seen in some setups
            final pth2 = (exec as dynamic).dbPath ?? (exec as dynamic).path;
            if (pth2 is String) pathToSend = pth2;
          } catch (_) {}
        }

        if (pathToSend == null) {
          try {
            final dbFile = (exec as dynamic).database;
            if (dbFile is File) pathToSend = dbFile.path;
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Fallback: try the typical sqflite location
  if (pathToSend == null) {
    try {
      // lazy import sqflite's getDatabasesPath if available
      // to avoid a hard dependency, we attempt to call it dynamically.
      // Many apps already depend on sqflite; if not, caller must pass dbPath.
      Future<Null> getDatabasesPathFunction() async {
        try {
          // Using a direct import would require adding sqflite as dep; instead
          // try to call via Zone/Isolate not possible — skip automatic.
          return null;
        } catch (_) {
          return null;
        }
      }

      final dbDir = await getDatabasesPathFunction();
      if (dbDir is String) {
        final candidate = '$dbDir/$dbName';
        if (await File(candidate).exists()) pathToSend = candidate;
      }
    } catch (_) {}
  }

  if (pathToSend != null && await File(pathToSend).exists()) {
    await sendDbFileToDevTools(pathToSend, host: host, port: port);
    return;
  }

  throw ArgumentError(
    'Could not locate Drift DB file. Pass explicit dbPath or generatedDb.',
  );
}
