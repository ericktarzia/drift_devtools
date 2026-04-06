import 'package:drift_devtools_example_app/flutter_drift_example.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drift DevTools Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DbViewerPage(),
    );
  }
}

class DbViewerPage extends StatefulWidget {
  const DbViewerPage({super.key});

  @override
  State<DbViewerPage> createState() => _DbViewerPageState();
}

class _DbViewerPageState extends State<DbViewerPage>
    with SingleTickerProviderStateMixin {
  late final AppDatabase _db;
  late final TabController _tabController;
  late Future<void> _initFuture;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _loans = [];

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _tabController = TabController(length: 3, vsync: this);
    _initFuture = _initDb();
  }

  Future<void> _initDb() async {
    await _db.seed();
    _users = await _db.allUsers();
    _books = await _db.allBooks();
    _loans = await _db.allLoans();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drift DevTools Example'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Books'),
            Tab(text: 'Loans'),
          ],
        ),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(context, _users, ['id', 'name', 'email']),
              _buildList(context, _books, ['id', 'title', 'author']),
              _buildList(context, _loans, [
                'id',
                'userId',
                'bookId',
                'borrowedAt',
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Map<String, dynamic>> items,
    List<String> cols,
  ) {
    if (items.isEmpty) {
      return const Center(child: Text('Nenhum registro encontrado'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final row = items[idx];
        return ListTile(
          title: Text(cols.map((c) => '$c: ${row[c]}').join(' • ')),
        );
      },
    );
  }
}
