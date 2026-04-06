// Exemplo simples usando drift — cria 3 tabelas e insere dados.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_devtools/drift_devtools.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'flutter_drift_example.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().nullable()();
}

class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get author => text().nullable()();
}

class Loans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get bookId => integer().references(Books, #id)();
  DateTimeColumn get borrowedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Users, Books, Loans])
class AppDatabase extends _$AppDatabase {
  String dbName = 'drift_devtools_example.sqlite';
  AppDatabase()
    : super(
        LazyDatabase(() async {
          final dbFolder = await getApplicationDocumentsDirectory();
          final file = File(
            p.join(dbFolder.path, 'drift_devtools_example.sqlite'),
          );
          return NativeDatabase(file);
        }),
      );

  @override
  int get schemaVersion => 1;

  Future<void> seed() async {
    final existing = await select(users).get();
    if (existing.isNotEmpty) return;

    final alice = await into(users).insert(
      UsersCompanion.insert(name: 'Alice', email: Value('alice@example.com')),
    );
    final bob = await into(users).insert(
      UsersCompanion.insert(name: 'Bob', email: Value('bob@example.com')),
    );

    final b1 = await into(books).insert(
      BooksCompanion.insert(title: 'Drift Cookbook', author: Value('Dev')),
    );
    final b2 = await into(books).insert(
      BooksCompanion.insert(
        title: 'Flutter Recipes',
        author: Value('Community'),
      ),
    );
    final b3 = await into(books).insert(
      BooksCompanion.insert(
        title: 'Effective Dart',
        author: Value('Dart Team'),
      ),
    );

    await into(loans).insert(LoansCompanion.insert(userId: alice, bookId: b1));
    await into(loans).insert(LoansCompanion.insert(userId: bob, bookId: b2));
    await into(loans).insert(LoansCompanion.insert(userId: bob, bookId: b3));

    final dbFilePath = (await getApplicationDocumentsDirectory()).path;
    print('DB criado/em seed em: $dbFilePath/drift_devtools_example.sqlite');
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, dbName));
    if (await file.exists()) {
      await sendDbFileToDevTools(file.path);
    } else {
      print('Arquivo de banco de dados não encontrado para o Drift DevTools.');
    }
  }

  Future<List<Map<String, dynamic>>> allUsers() async =>
      (await select(users).get()).map((r) => r.toJson()).toList();
  Future<List<Map<String, dynamic>>> allBooks() async =>
      (await select(books).get()).map((r) => r.toJson()).toList();
  Future<List<Map<String, dynamic>>> allLoans() async =>
      (await select(loans).get()).map((r) => r.toJson()).toList();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  try {
    await db.seed();
    print('DB criado/em seed em: drift_devtools_example.sqlite');

    final u = await db.allUsers();
    final b = await db.allBooks();
    final l = await db.allLoans();

    print('\nUsers:');
    for (final x in u) print(x);

    print('\nBooks:');
    for (final x in b) print(x);

    print('\nLoans:');
    for (final x in l) print(x);
  } finally {
    await db.close();
  }
}
