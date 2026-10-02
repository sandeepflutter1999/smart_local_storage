import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

import 'test_setup.dart';

void main() {
  late Directory root;

  setUpAll(() => root = setUpStorage());
  tearDownAll(() async {
    await SmartLocalStorage.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File fileOf(String name) =>
      File('${root.path}/smart_local_storage/$name.json');

  test('add / get / update / delete', () async {
    final box = await SmartLocalStorage.box('crud');
    final id = await box.add({'title': 'Milk', 'done': false});
    expect(box.get(id), {'title': 'Milk', 'done': false, 'id': id});

    await box.update(id, {'done': true});
    expect(box.get(id)!['done'], true);
    expect(box.get(id)!['title'], 'Milk');

    await box.delete(id);
    expect(box.get(id), isNull);
    expect(box.length, 0);
  });

  test('id key inside data is reserved', () async {
    final box = await SmartLocalStorage.box('reserved');
    final id = await box.add({'id': 'hacked', 'a': 1});
    expect(box.get(id)!['id'], id);
  });

  test('returned maps are copies', () async {
    final box = await SmartLocalStorage.box('copies');
    final id = await box.add({'tags': ['a']});
    (box.get(id)!['tags'] as List).add('b');
    expect(box.get(id)!['tags'], ['a']);
  });

  test('unsupported values throw immediately', () async {
    final box = await SmartLocalStorage.box('invalid');
    expect(() => box.add({'when': DateTime.now()}), throwsArgumentError);
    expect(() => box.add({'n': double.nan}), throwsArgumentError);
  });

  test('two simultaneous box() calls share one instance', () async {
    final results =
        await Future.wait([SmartLocalStorage.box('same'), SmartLocalStorage.box('same')]);
    expect(identical(results[0], results[1]), isTrue);
  });

  test('data survives close + reopen, auto-id is not reused', () async {
    final a = await SmartBox.open('persist');
    await a.add({'n': 1});
    final last = await a.add({'n': 2});
    await a.delete(last);
    await a.close();

    final b = await SmartBox.open('persist');
    expect(b.length, 1);
    final next = await b.add({'n': 3});
    expect(int.parse(next), int.parse(last) + 1);
    await b.close();
  });

  test('reads files written by the old format', () async {
    await Directory('${root.path}/smart_local_storage').create(recursive: true);
    await fileOf('legacy').writeAsString(jsonEncode({
      '0': {'a': 1},
      '5': {'a': 2},
    }));
    final box = await SmartBox.open('legacy');
    expect(box.get('5')!['a'], 2);
    expect(await box.add({'a': 3}), '6');
    await box.close();
  });

  test('recovers from a corrupt main file using the backup', () async {
    final a = await SmartBox.open('recover', writeDelay: Duration.zero);
    await a.add({'v': 1});
    await a.add({'v': 2}); // second write creates the .bak of the first
    await a.close();

    await fileOf('recover').writeAsString('{ not json');
    final b = await SmartBox.open('recover');
    expect(b.length, greaterThanOrEqualTo(1)); // came back from .bak
    expect(File('${fileOf('recover').path}.corrupt').existsSync(), isTrue);
    await b.close();
  });

  test('watchAll emits now and after changes', () async {
    final box = await SmartLocalStorage.box('watch');
    final future = box.watchAll().take(2).toList();
    await box.add({'x': 1});
    final lists = await future;
    expect(lists.first, isEmpty);
    expect(lists.last, hasLength(1));
  });

  test('query filters, sorts and pages', () async {
    final box = await SmartLocalStorage.box('query');
    await box.addAll([
      for (var i = 0; i < 10; i++) {'n': i},
    ]);
    final rows = box.query(
      where: (r) => (r['n'] as int) >= 5,
      sort: (a, b) => (b['n'] as int).compareTo(a['n'] as int),
      limit: 2,
    );
    expect(rows.map((r) => r['n']), [9, 8]);
    expect(box.count((r) => (r['n'] as int).isEven), 5);
  });

  test('migration runs once for older data', () async {
    final a = await SmartBox.open('migrate');
    await a.add({'name': 'x'});
    await a.close();

    final b = await SmartBox.open('migrate', version: 2,
        onMigrate: (from, to, records) {
      expect(from, 1);
      expect(to, 2);
      for (final r in records.values) {
        r['currency'] = 'INR';
      }
    });
    expect(b.get('0')!['currency'], 'INR');
    await b.close();

    final c = await SmartBox.open('migrate', version: 2,
        onMigrate: (_, __, ___) => fail('must not run again'));
    expect(c.get('0')!['currency'], 'INR');
    await c.close();
  });

  test('encrypted box is not readable on disk but reads back fine', () async {
    final a = await SmartBox.open('secret', encrypted: true);
    final id = await a.add({'token': 'super-secret-value'});
    await a.close();

    final bytes = fileOf('secret').readAsBytesSync();
    expect(utf8.decode(bytes.sublist(0, 4)), 'SLC1');
    expect(latin1.decode(bytes).contains('super-secret-value'), isFalse);

    final b = await SmartBox.open('secret', encrypted: true);
    expect(b.get(id)!['token'], 'super-secret-value');
    await b.close();
  });

  test('big boxes (isolate path) round-trip', () async {
    final a = await SmartBox.open('big', isolateThreshold: 10);
    await a.addAll([
      for (var i = 0; i < 100; i++) {'n': i, 'text': 'item $i'},
    ]);
    await a.close();
    final b = await SmartBox.open('big', isolateThreshold: 10);
    expect(b.length, 100);
    expect(b.get('99')!['text'], 'item 99');
    await b.close();
  });
}
