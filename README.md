# smart_local_storage

Pure Dart/Flutter local storage. **No third-party pub.dev packages** — not
even `shared_preferences`, `path_provider`, `hive`, or `isar`. Just:

- `dart:io` to read/write a JSON file per "box"
- a tiny native plugin (Android Kotlin + iOS Swift, written for this
  package, not pulled from pub.dev) that returns the app's own private
  storage folder path

## Why not Hive / Isar?

Both need a model class + generated `TypeAdapter`/schema before you can
save anything. `SmartBox` skips that entirely — you pass a plain
`Map<String, dynamic>`, get an id back, and can list/fetch/update/delete
by that id.

## Setup

No `init()` step needed for the box itself — just open a box by name:

```dart
final notes = await SmartLocalStorage.box('notes');
```

## Usage — list + detail by id, like Hive/Isar, no model class

```dart
// add a record — id is auto-generated
final id = await notes.add({'title': 'Groceries', 'detail': 'Milk, eggs'});

// show the whole list
final all = notes.getAll(); // List<Map<String,dynamic>>, each has 'id'

// show one record's detail, by id
final one = notes.get(id); // {'id': ..., 'title': ..., 'detail': ...}

// update / delete
await notes.update(id, {'detail': 'Milk, eggs, bread'});
await notes.delete(id);

// or choose your own id instead of auto-generating one
await notes.put('user_42', {'name': 'Sandeep'});
```

See `example/lib/main.dart` for a full notes list + detail screen.

## Using your own model class instead of Maps

If you'd rather work with a typed model than raw Maps, wrap the box in
`SmartModelBox<T>` — still no annotations or `build_runner`, just two
functions you write yourself:

```dart
class Note {
  Note({this.id, required this.title, required this.detail});
  final String? id;
  final String title;
  final String detail;

  Map<String, dynamic> toMap() => {'title': title, 'detail': detail};

  static Note fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as String?,
        title: map['title'] as String,
        detail: map['detail'] as String,
      );
}

final notesBox = SmartModelBox<Note>(
  await SmartLocalStorage.box('notes'),
  toMap: (n) => n.toMap(),
  fromMap: Note.fromMap,
);

final id = await notesBox.add(Note(title: 'Milk', detail: 'Buy 1L'));
final note = notesBox.get(id);   // Note?
final all = notesBox.getAll();   // List<Note>
```


# smart_local_storage
# smart_local_storage
# smart_local_storage
# smart_local_storage
