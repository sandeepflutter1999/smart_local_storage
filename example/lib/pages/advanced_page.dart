import 'package:flutter/material.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

/// Big data + durability + migrations.
class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key});

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  final _log = <String>[];
  SmartBox? _box;

  /// Options you can pass when opening a box (all optional):
  ///  - version + onMigrate : upgrade old records when your data shape changes
  ///  - writeDelay          : batch rapid writes (default 300 ms)
  ///  - isolateThreshold    : records from which saving runs on a background isolate
  ///  - onError             : called if a background save fails
  Future<SmartBox> _open() async {
    return _box ??= await SmartLocalStorage.box(
      'products',
      version: 2, // bump this when the data shape changes...
      onMigrate: (from, to, records) {
        // ...and fix old records here. Runs once, only for older files.
        if (from < 2) {
          for (final r in records.values) {
            r['price'] = (r['price'] ?? 0) * 1.0; // e.g. make sure price exists
          }
        }
      },
      onError: (e, st) => debugPrint('save failed: $e'),
    );
  }

  void _say(String s) => setState(() => _log.insert(0, s));

  Future<void> _insert(int n) async {
    final box = await _open();
    final sw = Stopwatch()..start();
    // addAll = ONE disk write for all records (instead of n writes).
    await box.addAll([
      for (var i = 0; i < n; i++) {'name': 'Item $i', 'price': i % 100, 'tags': ['a', 'b']},
    ]);
    _say('Added $n in ${sw.elapsedMilliseconds} ms (memory). Total: ${box.length}');
  }

  Future<void> _query() async {
    final box = await _open();
    final sw = Stopwatch()..start();
    // Filter + sort + page, all in memory.
    final rows = box.query(
      where: (r) => (r['price'] as num) > 90,
      sort: (a, b) => (b['price'] as num).compareTo(a['price'] as num),
      limit: 5,
    );
    _say('query: ${rows.length} rows (price > 90, top 5) in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _flush() async {
    final box = await _open();
    final sw = Stopwatch()..start();
    // Writes reach disk ~300 ms after the last change anyway, and also when
    // the app goes to the background. Use flush() when you must be sure NOW.
    await box.flush();
    _say('flush(): safely on disk in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _clear() async {
    final box = await _open();
    await box.deleteWhere((r) => (r['price'] as num) < 50);
    _say('deleteWhere(price < 50) -> ${box.length} left');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: Column(
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: () => _insert(1000), child: const Text('Add 1,000')),
            FilledButton(onPressed: () => _insert(20000), child: const Text('Add 20,000')),
            OutlinedButton(onPressed: _query, child: const Text('Query')),
            OutlinedButton(onPressed: _clear, child: const Text('Delete cheap')),
            OutlinedButton(onPressed: _flush, child: const Text('flush()')),
          ]),
          const Divider(),
          Expanded(
            child: ListView(children: [for (final l in _log) ListTile(dense: true, title: Text(l))]),
          ),
        ],
      ),
    );
  }
}
