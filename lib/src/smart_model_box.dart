import 'smart_box.dart';

/// A typed view over a [SmartBox], for when you'd rather work with your own
/// model class than raw `Map<String, dynamic>`.
///
/// No annotations, no `build_runner`, no generated adapters - you just write
/// two plain functions: how to turn your model into a Map, and how to turn
/// a Map back into your model (the map includes the record id as `'id'`).
///
/// ```dart
/// final notes = SmartModelBox<Note>(
///   await SmartLocalStorage.box('notes'),
///   toMap: (n) => n.toMap(),
///   fromMap: Note.fromMap,
/// );
///
/// final id = await notes.add(Note(title: 'Milk', detail: 'Buy 1L'));
/// final one = notes.get(id);          // Note?
/// final all = notes.getAll();         // List<Note>
///
/// StreamBuilder<List<Note>>(stream: notes.watchAll(), ...)
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

  /// The untyped box underneath (for `flush()`, `events`, etc.).
  SmartBox get box => _box;

  // ---- writes

  /// Adds [model] as a new record with an auto-generated id. Returns the id.
  Future<String> add(T model, {bool flush = false}) =>
      _box.add(_toMap(model), flush: flush);

  /// Adds many models at once (one disk write). Returns their ids.
  Future<List<String>> addAll(Iterable<T> models, {bool flush = false}) =>
      _box.addAll(models.map(_toMap), flush: flush);

  /// Inserts/overwrites the record at [id] with [model].
  Future<void> put(String id, T model, {bool flush = false}) =>
      _box.put(id, _toMap(model), flush: flush);

  /// Merges [model]'s fields into the existing record at [id].
  Future<void> update(String id, T model, {bool flush = false}) =>
      _box.update(id, _toMap(model), flush: flush);

  Future<void> delete(String id, {bool flush = false}) =>
      _box.delete(id, flush: flush);

  Future<void> deleteAll(Iterable<String> ids, {bool flush = false}) =>
      _box.deleteAll(ids, flush: flush);

  /// Deletes every model for which [test] returns true. Returns the count.
  Future<int> deleteWhere(bool Function(T model) test, {bool flush = false}) =>
      _box.deleteWhere((map) => test(_fromMap(map)), flush: flush);

  Future<void> clear({bool flush = false}) => _box.clear(flush: flush);

  // ---- reads

  /// The model stored at [id], or null if it doesn't exist.
  T? get(String id) {
    final map = _box.get(id);
    if (map == null) return null;
    return _fromMap(map);
  }

  /// Every record in the box, converted to your model type.
  List<T> getAll() => _box.getAll().map(_fromMap).toList();

  /// Filter / sort / page, using your model type.
  List<T> query({
    bool Function(T model)? where,
    int Function(T a, T b)? sort,
    int offset = 0,
    int? limit,
  }) {
    var rows = _box.getAll().map(_fromMap).toList();
    if (where != null) rows = rows.where(where).toList();
    if (sort != null) rows.sort(sort);
    if (offset > 0) rows = rows.skip(offset).toList();
    if (limit != null) rows = rows.take(limit).toList();
    return rows;
  }

  T? firstWhere(bool Function(T model) where) {
    for (final map in _box.getAll()) {
      final model = _fromMap(map);
      if (where(model)) return model;
    }
    return null;
  }

  int count([bool Function(T model)? where]) => where == null
      ? _box.length
      : _box.getAll().map(_fromMap).where(where).length;

  bool containsId(String id) => _box.containsId(id);

  int get length => _box.length;

  // ---- reactive

  /// Current models right away, then again after every change.
  Stream<List<T>> watchAll({
    bool Function(T model)? where,
    int Function(T a, T b)? sort,
    int offset = 0,
    int? limit,
  }) =>
      _box.watchAll().map((_) => query(
            where: where,
            sort: sort,
            offset: offset,
            limit: limit,
          ));

  /// The model at [id] right away (null if missing), then on every change.
  Stream<T?> watch(String id) =>
      _box.watch(id).map((map) => map == null ? null : _fromMap(map));

  Future<void> flush() => _box.flush();
}
