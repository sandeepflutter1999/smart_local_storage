import 'dart:convert';
import 'dart:io';

import 'smart_paths.dart';

/// A named, disk-backed collection of records — like a Hive "box" or an
/// Isar collection, but with plain [Map]s: no model classes, no adapters,
/// no code generation. Every record has an id (auto or your own) and a
/// [Map<String, dynamic>] of data.
///
/// Data is kept in memory and written to a single JSON file per box under
/// the app's own storage folder, using dart:io directly — no third-party
/// package.
class SmartBox {
  SmartBox._(this.name, this._file);

  final String name;
  final File _file;

  /// id -> record
  final Map<String, Map<String, dynamic>> _data = {};
  int _autoId = 0;

  /// Opens (creating if needed) the box called [name]. Call this once per
  /// box and keep the returned instance, or fetch it again any time via
  /// [SmartLocalStorage.box].
  static Future<SmartBox> open(String name) async {
    final root = await SmartPaths.getStorageRoot();
    final dir = Directory('$root/smart_local_storage');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$name.json');
    final box = SmartBox._(name, file);
    await box._load();
    return box;
  }

  Future<void> _load() async {
    if (!await _file.exists()) return;
    final content = await _file.readAsString();
    if (content.trim().isEmpty) return;
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    decoded.forEach((id, value) {
      _data[id] = Map<String, dynamic>.from(value as Map);
      final n = int.tryParse(id);
      if (n != null && n >= _autoId) _autoId = n + 1;
    });
  }

  Future<void> _save() => _file.writeAsString(jsonEncode(_data));

  /// Adds a new record with an auto-generated id. Returns the id.
  Future<String> add(Map<String, dynamic> data) async {
    final id = (_autoId++).toString();
    _data[id] = Map<String, dynamic>.from(data);
    await _save();
    return id;
  }

  /// Inserts or overwrites the record at a specific id you choose.
  Future<void> put(String id, Map<String, dynamic> data) async {
    _data[id] = Map<String, dynamic>.from(data);
    await _save();
  }

  /// Merges [data] into the existing record at [id] (record must exist).
  Future<void> update(String id, Map<String, dynamic> data) async {
    final existing = _data[id];
    if (existing == null) {
      throw StateError('No record with id "$id" in box "$name".');
    }
    _data[id] = {...existing, ...data};
    await _save();
  }

  /// The single record for [id], with its id included as `'id'`, or null.
  Map<String, dynamic>? get(String id) {
    final record = _data[id];
    if (record == null) return null;
    return {'id': id, ...record};
  }

  /// Every record in the box, each with its id included as `'id'`.
  List<Map<String, dynamic>> getAll() {
    return _data.entries.map((e) => {'id': e.key, ...e.value}).toList();
  }

  bool containsId(String id) => _data.containsKey(id);

  Future<void> delete(String id) async {
    _data.remove(id);
    await _save();
  }

  Future<void> clear() async {
    _data.clear();
    _autoId = 0;
    await _save();
  }

  int get length => _data.length;
}
