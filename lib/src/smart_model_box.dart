import 'smart_box.dart';

/// A typed view over a [SmartBox], for when you'd rather work with your own
/// model class than raw `Map<String, dynamic>`.
///
/// No annotations, no `build_runner`, no generated adapters — you just write
/// two plain functions: how to turn your model into a Map, and how to turn
/// a Map back into your model.
///
/// ```dart
/// class Note {
///   Note({this.id, required this.title, required this.detail});
///   final String? id;
///   final String title;
///   final String detail;
///
///   Map<String, dynamic> toMap() => {'title': title, 'detail': detail};
///
///   static Note fromMap(Map<String, dynamic> map) => Note(
///         id: map['id'] as String?,
///         title: map['title'] as String,
///         detail: map['detail'] as String,
///       );
/// }
///
/// final notesBox = SmartModelBox<Note>(
///   await SmartLocalStorage.box('notes'),
///   toMap: (note) => note.toMap(),
///   fromMap: Note.fromMap,
/// );
///
/// final id = await notesBox.add(Note(title: 'Milk', detail: 'Buy 1L'));
/// final note = notesBox.get(id);        // Note?
/// final all = notesBox.getAll();        // List<Note>
/// ```
class SmartModelBox<T> {
  SmartModelBox(
    this._box, {
    required Map<String, dynamic> Function(T model) toMap,
    required T Function(Map<String, dynamic> map) fromMap,
  })  : _toMap = toMap,
        _fromMap = fromMap;

  final SmartBox _box;
  final Map<String, dynamic> Function(T model) _toMap;
  final T Function(Map<String, dynamic> map) _fromMap;

  /// Adds [model] as a new record with an auto-generated id. Returns the id.
  Future<String> add(T model) => _box.add(_toMap(model));

  /// Inserts/overwrites the record at [id] with [model].
  Future<void> put(String id, T model) => _box.put(id, _toMap(model));

  /// Merges [model]'s fields into the existing record at [id].
  Future<void> update(String id, T model) => _box.update(id, _toMap(model));

  /// The model stored at [id], or null if it doesn't exist. The map passed
  /// to [fromMap] includes the id as `'id'`, same as [SmartBox.get].
  T? get(String id) {
    final map = _box.get(id);
    if (map == null) return null;
    return _fromMap(map);
  }

  /// Every record in the box, converted to your model type.
  List<T> getAll() => _box.getAll().map(_fromMap).toList();

  Future<void> delete(String id) => _box.delete(id);

  Future<void> clear() => _box.clear();

  int get length => _box.length;
}
