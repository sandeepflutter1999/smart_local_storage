import 'package:flutter/material.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

/// BIG data, SEARCH indexes and ENCRYPTION.
///
/// 1. lazyBox  -> records stay on disk, only ids are in memory (100k+ is fine)
/// 2. indexes  -> findBy / findRange without scanning every record
/// 3. encrypted -> AES-256-GCM, the key lives in Android Keystore / iOS Keychain
class BigDataPage extends StatefulWidget {
  const BigDataPage({super.key});

  @override
  State<BigDataPage> createState() => _BigDataPageState();
}

class _BigDataPageState extends State<BigDataPage> {
  final _log = <String>[];
  SmartLazyBox? _people;

  void _say(String s) => setState(() => _log.insert(0, s));

  Future<SmartLazyBox> _open() async {
    return _people ??= await SmartLocalStorage.lazyBox(
      'people',
      // Fields you want to search fast. Listed once, used forever.
      indexes: ['city', 'age'],
    );
  }

  Future<void> _insert(int n) async {
    final box = await _open();
    final sw = Stopwatch()..start();
    const cities = ['Delhi', 'Pune', 'Chandigarh', 'Mumbai'];
    await box.addAll([
      for (var i = 0; i < n; i++)
        {'name': 'Person $i', 'city': cities[i % cities.length], 'age': 18 + i % 60},
    ]);
    _say('Added $n in ${sw.elapsedMilliseconds} ms. Total ${box.length}, '
        'file ${(box.diskBytes / 1024).round()} KB');
  }

  Future<void> _findByCity() async {
    final box = await _open();
    final sw = Stopwatch()..start();
    // Indexed lookup: no full scan (the first call builds the index once).
    final rows = await box.findBy('city', 'Chandigarh');
    _say('findBy(city = Chandigarh): ${rows.length} rows in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _findByAge() async {
    final box = await _open();
    final sw = Stopwatch()..start();
    final rows = await box.findRange('age', min: 30, max: 35, limit: 100);
    _say('findRange(age 30..35, first 100): ${rows.length} rows in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _firstPage() async {
    final box = await _open();
    final sw = Stopwatch()..start();
    // query() reads one record at a time and stops early with a limit,
    // so memory stays flat even for a huge box.
    final rows = await box.query(where: (r) => (r['age'] as int) > 70, limit: 20);
    _say('query(age > 70, limit 20): ${rows.length} rows in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _encryptedDemo() async {
    // Same API as a normal box - just add encrypted: true.
    final secrets = await SmartLocalStorage.box('secrets', encrypted: true);
    await secrets.put('api', {'token': 'abc-123'}, flush: true);
    _say('Encrypted box saved. Read back: ${secrets.get('api')!['token']}');
  }

  Future<void> _clear() async {
    final box = await _open();
    await box.clear();
    _say('Cleared');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Big data / index / encrypt')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: () => _insert(10000), child: const Text('Add 10,000')),
              FilledButton(onPressed: () => _insert(100000), child: const Text('Add 100,000')),
              OutlinedButton(onPressed: _findByCity, child: const Text('findBy city')),
              OutlinedButton(onPressed: _findByAge, child: const Text('findRange age')),
              OutlinedButton(onPressed: _firstPage, child: const Text('query + limit')),
              OutlinedButton(onPressed: _encryptedDemo, child: const Text('Encrypted box')),
              OutlinedButton(onPressed: _clear, child: const Text('Clear')),
            ]),
          ),
          const Divider(),
          Expanded(
            child: ListView(children: [for (final l in _log) ListTile(dense: true, title: Text(l))]),
          ),
        ],
      ),
    );
  }
}
