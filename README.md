# smart_local_cache

Fast local storage for Flutter with **zero third-party packages** - no
`shared_preferences`, `path_provider`, `hive` or `isar`. Plain `Map`s in,
plain `Map`s out. No model classes, no `build_runner`.

- Everything is cached in memory - reads are instant
- Writes are batched, atomic and crash-safe (temp file + rename + backup)
- Big boxes are saved/loaded on a background isolate - no UI jank
- Live updates with `Stream` (`watchAll`, `watch`) - works with `StreamBuilder`
- Filter / sort / page with `query()`, batch ops, schema migrations

## 1. Open a box (no init needed)

```dart
final todos = await SmartLocalStorage.box('todos');
```

Same name = same box everywhere in your app.

## 2. Save, read, update, delete

```dart
final id = await todos.add({'title': 'Milk', 'done': false}); // auto id
await todos.put('user_42', {'name': 'Sandeep'});              // your own id
await todos.update(id, {'done': true});                       // merges
await todos.delete(id);

final one = todos.get(id);     // {'id': ..., 'title': ..., 'done': ...} or null
final all = todos.getAll();    // List<Map>, each has 'id'
```

`'id'` is reserved - the box always puts the record id there. Values must be
`String, num, bool, null, List, Map<String, ...>` (use `toIso8601String()` for
dates). Anything else throws right away instead of failing later.

## 3. Show it in the UI - auto refresh

```dart
StreamBuilder<List<Map<String, dynamic>>>(
  stream: todos.watchAll(),
  builder: (context, snap) {
    final list = snap.data ?? [];
    return ListView(children: [for (final t in list) Text(t['title'])]);
  },
)
```

No `setState` needed - the stream fires after every add / update / delete.
Follow a single record with `todos.watch(id)`.

## 4. Search, sort, page

```dart
todos.query(
  where: (r) => r['done'] == false,
  sort: (a, b) => (a['title'] as String).compareTo(b['title'] as String),
  offset: 0,
  limit: 20,
);
todos.count((r) => r['done'] == true);
todos.firstWhere((r) => r['title'] == 'Milk');
todos.watchAll(where: ..., sort: ..., limit: ...); // same options, live
```

## 5. Many records at once

```dart
await todos.addAll([{...}, {...}]);       // one disk write
await todos.putAll({'a': {...}, 'b': {...}});
await todos.deleteAll(['1', '2']);
await todos.deleteWhere((r) => r['done'] == true);
```

## 6. Your own model class (optional)

```dart
class Note {
  Note({this.id, required this.title});
  final String? id;
  final String title;
  Map<String, dynamic> toMap() => {'title': title};
  static Note fromMap(Map<String, dynamic> m) =>
      Note(id: m['id'] as String?, title: m['title'] as String);
}

final notes = SmartModelBox<Note>(
  await SmartLocalStorage.box('notes'),
  toMap: (n) => n.toMap(),
  fromMap: Note.fromMap,
);

await notes.add(Note(title: 'Milk'));
StreamBuilder<List<Note>>(stream: notes.watchAll(), builder: ...);
```

## 7. When does data reach the disk?

Changes are visible instantly and saved ~300 ms later, in one batch. Pending
writes are also flushed automatically when the app goes to the background.

```dart
await todos.add({...}, flush: true); // wait until it is on disk
await todos.flush();                 // flush this box
await SmartLocalStorage.flushAll();  // flush every box
```

## 8. Changing your data shape later (migration)

```dart
final products = await SmartLocalStorage.box(
  'products',
  version: 2, // bumped from 1
  onMigrate: (from, to, records) {
    if (from < 2) {
      for (final r in records.values) { r['currency'] = 'INR'; }
    }
  },
);
```

## Other options

```dart
SmartLocalStorage.box('x',
  writeDelay: Duration.zero,        // save on every change
  isolateThreshold: 500,            // records from which saving uses an isolate
  onError: (e, st) => log(e),       // background save failures
);
```

## Honest limits

Great for settings, game data, caches and lists up to tens of thousands of
small records. The whole box is kept in memory and saved as one file, so for
hundreds of thousands of records, indexes or relations use SQLite / Drift / Isar.

## Example app

`example/` has 3 screens: plain Maps with live search, a typed model, and a
20,000-record stress test with queries, flush and migration.
