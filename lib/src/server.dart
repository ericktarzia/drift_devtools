import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class DriftDevToolsServer {
  final GeneratedDatabase db;

  DriftDevToolsServer(this.db);

  Future<void> start({int port = 8080}) async {
    Future<Response> handler(Request request) async {
      final path = request.url.path;

      // 🔹 listar tabelas
      if (path == 'tables') {
        final result = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table';")
            .get();

        return Response.ok(
          jsonEncode(result.map((e) => e.data).toList()),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 🔹 dados de uma tabela
      if (path.startsWith('table/')) {
        final table = path.split('/').last;

        final result = await db
            .customSelect("SELECT * FROM $table LIMIT 100;")
            .get();

        return Response.ok(
          jsonEncode(result.map((e) => e.data).toList()),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.notFound('Not found');
    }

    final server = await io.serve(handler, 'localhost', port);

    print('🚀 Drift DevTools rodando em http://localhost:$port');
  }
}
