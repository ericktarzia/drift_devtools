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
      final path = request.url.path;

      try {
        // 🔹 LISTAR TABELAS
        if (path == 'tables') {
          final result = await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table';",
              )
              .get();

          return Response.ok(
            jsonEncode(result.map((e) => e.data).toList()),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 🔹 DADOS DE UMA TABELA
        if (path.startsWith('table/')) {
          final table = path.split('/').last;

          print('➡️ Recebi request da tabela: $table');

          try {
            print('⏳ Antes da query');

            final result = await db
                .customSelect('SELECT * FROM "$table" LIMIT 10;')
                .get();

            print('✅ Query executada');

            final data = result.map((e) => e.data).toList();

            print('📦 Dados convertidos');

            return Response.ok(
              jsonEncode(data),
              headers: {'Content-Type': 'application/json'},
            );
          } catch (e, stack) {
            print('❌ ERRO: $e');
            print(stack);

            return Response.internalServerError(body: e.toString());
          }
        }

        return Response.notFound('Not found');
      } catch (e, stack) {
        print('❌ Erro no Drift DevTools: $e');
        print(stack);

        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
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
