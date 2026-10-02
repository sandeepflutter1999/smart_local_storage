import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

import 'test_setup.dart';

void main() {
  late Directory root;

  setUpAll(() => root = setUpStorage());
  tearDownAll(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File logOf(String name) =>
      File('${root.path}/smart_local_storage/$name.slog');

  test('add / get / update / delete', () async {
    final box = await SmartLazyBox.open('l_crud');
    final id = await box.add({'title': 'Milk'});
    expect(await box.get(id), {'title': 'Milk', 'id': id});
    await box.update(id, {'done': true});
    expect((await box.get(id))!['done'], true);
    await box.delete(id);
    expect(await box.get(id), isNull);
    expect(box.length, 0);
    await box.close();
  });

  test('survives reopen; auto-id continues', () async {
    final a = await SmartLazyBox.open('l_persist');
    await a.addAll([
      {'n': 1},
      {'n': 2},
      {'n': 3},
    ]);
    await a.delete('2');
    await a.put('custom', {'n': 9});
    await a.close();

    final b = await SmartLazyBox.open('l_persist');
    expect(b.length, 3);
    expect((await b.get('custom'))!['n'], 9);
    expect(await b.add({'n': 4}), '3');
    await b.close();
  });

  test('a half-written last line is dropped on open', () async {
    final a = await SmartLazyBox.open('l_crash');
    await a.add({'n': 1});
    await a.add({'n': 2});
    await a.close();

    // Simulate a crash in the middle of a write.
    logOf('l_crash').writeAsBytesSync('P\t7\t{"n":'.codeUnits,
        mode: FileMode.append);

    final b = await SmartLazyBox.open('l_crash');
    expect(b.length, 2);
    await b.add({'n': 3});
    await b.close();

    final c = await SmartLazyBox.open('l_crash');
    expect(c.length, 3);
    await c.close();
  });

  test('compaction shrinks the file and keeps live data', () async {
    final box = await SmartLazyBox.open('l_compact', compactMinBytes: 1);
    await box.addAll([
      for (var i = 0; i < 20; i++) {'n': i, 'pad': 'x' * 50},
    ]);
    final before = box.diskBytes;
    await box.deleteAll([for (var i = 0; i < 15; i++) '$i']);
    await box.compact();
    expect(box.diskBytes, lessThan(before));
    expect(box.length, 5);
    await box.close();

    final again = await SmartLazyBox.open('l_compact');
    expect(again.length, 5);
    expect((await again.get('19'))!['n'], 19);
    expect(await again.add({'n': 99}), '20'); // counter survived compaction
    await again.close();
  });

  test('indexes: findBy and findRange follow updates and deletes', () async {
    final box =
        await SmartLazyBox.open('l_index', indexes: ['city', 'age']);
    await box.addAll([
      {'city': 'Delhi', 'age': 20},
      {'city': 'Delhi', 'age': 35},
      {'city': 'Pune', 'age': 28},
    ]);

    expect((await box.findBy('city', 'Delhi')).length, 2);
    expect((await box.findRange('age', min: 21, max: 30)).single['city'], 'Pune');

    await box.update('0', {'city': 'Pune'});
    expect((await box.findBy('city', 'Delhi')).length, 1);
    expect((await box.findBy('city', 'Pune')).length, 2);

    await box.delete('2');
    expect((await box.findBy('city', 'Pune')).length, 1);

    final sorted = await box.findRange('age', descending: true);
    expect(sorted.map((r) => r['age']), [35, 20]);

    expect(box.findBy('name', 'x'), throwsArgumentError); // not indexed
    await box.close();
  });

  test('query streams, filters and stops early with a limit', () async {
    final box = await SmartLazyBox.open('l_query');
    await box.addAll([
      for (var i = 0; i < 50; i++) {'n': i},
    ]);
    final rows = await box.query(where: (r) => (r['n'] as int) % 2 == 0, limit: 3);
    expect(rows.map((r) => r['n']), [0, 2, 4]);
    expect(await box.count((r) => (r['n'] as int) < 10), 10);
    await box.close();
  });

  test('encrypted records are not readable on disk', () async {
    final box = await SmartLazyBox.open('l_secret', encrypted: true);
    final id = await box.add({'token': 'super-secret-value'});
    await box.close();
    expect(String.fromCharCodes(logOf('l_secret').readAsBytesSync())
        .contains('super-secret-value'), isFalse);

    final again = await SmartLazyBox.open('l_secret', encrypted: true);
    expect((await again.get(id))!['token'], 'super-secret-value');
    await again.close();
  });

  test('watchAll refreshes after changes', () async {
    final box = await SmartLazyBox.open('l_watch');
    final future = box.watchAll().take(2).toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await box.add({'x': 1});
    final lists = await future;
    expect(lists.last, hasLength(1));
    await box.close();
  });

  test('bad ids are rejected', () async {
    final box = await SmartLazyBox.open('l_ids');
    expect(box.put('a\tb', {'x': 1}), throwsArgumentError);
    await box.close();
  });
}
