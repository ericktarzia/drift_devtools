import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class DriftDevToolsServer {
  final GeneratedDatabase db;

  DriftDevToolsServer(this.db);

  Future<void> start({int port = 38947}) async {
    print('🔥 Iniciando Drift DevTools...');

    Future<Response> handler(Request request) async {
      final segments = request.url.pathSegments;

      print('📡 Request: ${request.url}');

      try {
        // 🔹 /tables
        if (segments.length == 1 && segments[0] == 'tables') {
          print('📦 Listando tabelas');

          final result = await db.customSelect("PRAGMA table_list;").get();

          final tables = result
              .map((e) => e.data['name'] as String)
              .where(
                (name) =>
                    !name.startsWith('sqlite_') && name != 'android_metadata',
              )
              .toList();

          return Response.ok(jsonEncode(tables));
        }

        // 🔹 /table/{name}
        if (segments.length == 2 && segments[0] == 'table') {
          final table = segments[1];

          print('➡️ Tabela solicitada: $table');

          final result = await db
              .customSelect('SELECT * FROM "$table" LIMIT 10;')
              .get();

          final data = result.map((row) {
            final map = row.data;

            return map.map<String, String>((key, value) {
              if (value is Uint8List) return MapEntry(key, '[BLOB]');
              return MapEntry(key, value?.toString() ?? 'null');
            });
          }).toList();

          return Response.ok(jsonEncode(data));
        }

        print('❌ Rota não encontrada');
        return Response.notFound('Not found');
      } catch (e, stack) {
        print('❌ ERRO: $e');
        print(stack);

        return Response.internalServerError(body: e.toString());
      }
    }

    try {
      // 🔥 IMPORTANTE: usar 0.0.0.0 (funciona com emulador)
      final server = await io.serve(handler, '0.0.0.0', port);

      print('🚀 Drift DevTools rodando:');
      print('👉 http://localhost:$port (desktop)');
      print('👉 http://10.0.2.2:$port (emulador Android)');
    } catch (e) {
      print('⚠️ Porta $port ocupada, tentando porta aleatória...');

      final server = await io.serve(handler, '0.0.0.0', 0);

      print('🚀 Drift DevTools rodando na porta ${server.port}');
    }
  }
}
