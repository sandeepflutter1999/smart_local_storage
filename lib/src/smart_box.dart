import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'smart_crypto.dart';
import 'smart_paths.dart';

/// Called once when a box is opened with a higher `version` than the one
/// stored on disk. Mutate [records] in place (id -> record) to upgrade them.
typedef SmartMigration = FutureOr<void> Function(
  int fromVersion,
  int toVersion,
  Map<String, Map<String, dynamic>> records,
);

/// Kinds of change a box can report on [SmartBox.events].
enum SmartBoxEventType { added, updated, deleted, cleared }

/// One change in a box. [id] is null for [SmartBoxEventType.cleared].
class SmartBoxEvent {
  const SmartBoxEvent(this.type, this.id);

  final SmartBoxEventType type;
  final String? id;

  @override
  String toString() => 'SmartBoxEvent($type, $id)';
}

/// A named, disk-backed collection of records with plain [Map] data.
///
/// How it works:
/// * The whole box lives in memory, so reads are instant.
/// * Writes update memory immediately, then are saved to disk in one batch
///   after a short delay - 1000 quick `add()` calls cost one file write,
///   not 1000.
/// * Every disk write is atomic (temp file + rename) and the previous good
///   copy is kept as a backup, so a crash cannot leave a half-written file.
/// * Big boxes are encoded / decoded on a background isolate, so the UI
///   thread does not stall.
/// * [watchAll] / [watch] give you streams that fire when data changes.
class SmartBox {
  SmartBox._(
    this.name,
    this._file, {
    required this.version,
    required Duration writeDelay,
    required int isolateThreshold,
    required bool encrypted,
    required void Function(Object error, StackTrace stackTrace)? onError,
  })  : _tmp = File('${_file.path}.tmp'),
        _bak = File('${_file.path}.bak'),
        _writeDelay = writeDelay,
        _isolateThreshold = isolateThreshold,
        _encrypted = encrypted,
        _onError = onError;

  static const int _formatVersion = 2;
  static const String _magic = '__smart_box__';
  // 'SLC1' - first bytes of an encrypted box file.
  static const List<int> _encMagic = [0x53, 0x4C, 0x43, 0x31];
  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_\-]+$');

  final String name;

  /// Schema version of the records in this box (see [SmartMigration]).
  final int version;

  final File _file;
  final File _tmp;
  final File _bak;
  final Duration _writeDelay;
  final int _isolateThreshold;
  final bool _encrypted;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  /// id -> record. Records are never mutated after they are stored (an
  /// update replaces the record), which keeps background encoding safe.
  final Map<String, Map<String, dynamic>> _data = {};
  final StreamController<SmartBoxEvent> _events =
      StreamController<SmartBoxEvent>.broadcast();

  int _autoId = 0;
  int _schema = 1;
  bool _dirty = false;
  bool _closed = false;
  Timer? _timer;
  Future<void> _writing = Future<void>.value();

  // ---------------------------------------------------------------- open

  /// Opens (creating if needed) the box called [name]. Prefer
  /// `SmartLocalStorage.box`, which caches instances for you.
  static Future<SmartBox> open(
    String name, {
    int version = 1,
    SmartMigration? onMigrate,
    Duration writeDelay = const Duration(milliseconds: 300),
    int isolateThreshold = 500,
    bool encrypted = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (!_validName.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Box names may only contain letters, digits, "_" and "-".',
      );
    }
    final root = await SmartPaths.getStorageRoot();
    final dir = Directory('$root/smart_local_storage');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final box = SmartBox._(
      name,
      File('${dir.path}/$name.json'),
      version: version,
      writeDelay: writeDelay,
      isolateThreshold: isolateThreshold,
      encrypted: encrypted,
      onError: onError,
    );
    await box._load();
    if (version > box._schema) {
      if (onMigrate != null) {
        await onMigrate(box._schema, version, box._data);
      }
      box._schema = version;
      box._markDirty();
    }
    return box;
  }

  Future<void> _load() async {
    for (final file in [_file, _tmp, _bak]) {
      try {
        final map = await _tryRead(file);
        if (map == null) continue;
        _ingest(map);
        // Recovered from a backup / temp file: rewrite the main file soon.
        if (file.path != _file.path) _markDirty();
        return;
      } catch (e, st) {
        _report(e, st);
        // Keep the unreadable file for inspection instead of overwriting it.
        try {
          await file.rename('${file.path}.corrupt');
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>?> _tryRead(File file) async {
    if (!await file.exists()) return null;
    var bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    // Encrypted files start with a marker. We always decrypt them when we
    // see it, so turning `encrypted` off later still reads old data.
    if (_hasMagic(bytes)) {
      bytes = await SmartCrypto.decrypt(Uint8List.sublistView(bytes, _encMagic.length));
    }
    final Object? decoded = bytes.length >= 100000
        ? await _decodeInIsolate(bytes)
        : jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw FormatException('Box "$name" file is not a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static bool _hasMagic(Uint8List bytes) {
    if (bytes.length < _encMagic.length) return false;
    for (var i = 0; i < _encMagic.length; i++) {
      if (bytes[i] != _encMagic[i]) return false;
    }
    return true;
  }

  void _ingest(Map<String, dynamic> map) {
    final Map raw;
    if (map[_magic] != null && map['data'] is Map) {
      raw = map['data'] as Map;
      _autoId = (map['nextId'] as num?)?.toInt() ?? 0;
      _schema = (map['schema'] as num?)?.toInt() ?? 1;
    } else {
      // Older files were just { id: record }.
      raw = map;
    }
    raw.forEach((key, value) {
      if (value is! Map) return;
      final id = key as String;
      _data[id] = Map<String, dynamic>.from(value);
      final n = int.tryParse(id);
      if (n != null && n >= _autoId) _autoId = n + 1;
    });
  }

  // -------------------------------------------------------------- writes

  /// Adds a new record with an auto-generated id. Returns the id.
  ///
  /// The change is visible immediately. Set [flush] to `true` to also wait
  /// until it is safely on disk.
  Future<String> add(Map<String, dynamic> data, {bool flush = false}) async {
    _ensureOpen();
    final record = _cloneRecord(data);
    final id = (_autoId++).toString();
    _data[id] = record;
    await _commit([SmartBoxEvent(SmartBoxEventType.added, id)], flush);
    return id;
  }

  /// Adds many records at once (one disk write). Returns their ids in order.
  Future<List<String>> addAll(
    Iterable<Map<String, dynamic>> items, {
    bool flush = false,
  }) async {
    _ensureOpen();
    final records = items.map(_cloneRecord).toList();
    final ids = <String>[];
    final events = <SmartBoxEvent>[];
    for (final record in records) {
      final id = (_autoId++).toString();
      _data[id] = record;
      ids.add(id);
      events.add(SmartBoxEvent(SmartBoxEventType.added, id));
    }
    await _commit(events, flush);
    return ids;
  }

  /// Inserts or overwrites the record at a specific id you choose.
  Future<void> put(
    String id,
    Map<String, dynamic> data, {
    bool flush = false,
  }) async {
    _ensureOpen();
    final record = _cloneRecord(data);
    final existed = _data.containsKey(id);
    _data[id] = record;
    _bumpAutoId(id);
    await _commit([_putEvent(id, existed)], flush);
  }

  /// Inserts or overwrites many records at once (one disk write).
  Future<void> putAll(
    Map<String, Map<String, dynamic>> items, {
    bool flush = false,
  }) async {
    _ensureOpen();
    final cleaned = items.map((id, data) => MapEntry(id, _cloneRecord(data)));
    final events = <SmartBoxEvent>[];
    cleaned.forEach((id, record) {
      final existed = _data.containsKey(id);
      _data[id] = record;
      _bumpAutoId(id);
      events.add(_putEvent(id, existed));
    });
    await _commit(events, flush);
  }

  /// Merges [data] into the existing record at [id] (record must exist).
  Future<void> update(
    String id,
    Map<String, dynamic> data, {
    bool flush = false,
  }) async {
    _ensureOpen();
    final existing = _data[id];
    if (existing == null) {
      throw StateError('No record with id "$id" in box "$name".');
    }
    _data[id] = {...existing, ..._cloneRecord(data)};
    await _commit([SmartBoxEvent(SmartBoxEventType.updated, id)], flush);
  }

  Future<void> delete(String id, {bool flush = false}) async {
    _ensureOpen();
    if (_data.remove(id) == null) return;
    await _commit([SmartBoxEvent(SmartBoxEventType.deleted, id)], flush);
  }

  /// Deletes many ids at once (one disk write).
  Future<void> deleteAll(Iterable<String> ids, {bool flush = false}) async {
    _ensureOpen();
    final events = <SmartBoxEvent>[];
    for (final id in ids) {
      if (_data.remove(id) != null) {
        events.add(SmartBoxEvent(SmartBoxEventType.deleted, id));
      }
    }
    if (events.isEmpty) return;
    await _commit(events, flush);
  }

  /// Deletes every record for which [test] returns true. Returns the count.
  Future<int> deleteWhere(
    bool Function(Map<String, dynamic> record) test, {
    bool flush = false,
  }) async {
    _ensureOpen();
    final matched = <String>[];
    _data.forEach((id, record) {
      if (test({...record, 'id': id})) matched.add(id);
    });
    await deleteAll(matched, flush: flush);
    return matched.length;
  }

  /// Removes every record and resets the auto-id counter.
  Future<void> clear({bool flush = false}) async {
    _ensureOpen();
    _data.clear();
    _autoId = 0;
    await _commit(
      [const SmartBoxEvent(SmartBoxEventType.cleared, null)],
      flush,
    );
  }

  // --------------------------------------------------------------- reads

  /// The single record for [id], with its id included as `'id'`, or null.
  /// The returned map is a copy - changing it does not change the box.
  Map<String, dynamic>? get(String id) {
    final record = _data[id];
    if (record == null) return null;
    return {..._cloneMap(record), 'id': id};
  }

  /// Several records by id (missing ids are skipped).
  List<Map<String, dynamic>> getMany(Iterable<String> ids) {
    return [
      for (final id in ids)
        if (_data.containsKey(id)) get(id)!,
    ];
  }

  /// Every record in the box (insertion order), each with `'id'` included.
  List<Map<String, dynamic>> getAll() => query();

  /// Filter / sort / page through records without leaving memory.
  ///
  /// * [where] - keep records for which it returns true.
  /// * [sort] - comparator, like `List.sort`.
  /// * [offset] / [limit] - simple paging.
  ///
  /// The maps handed to [where] and [sort] are read-only views: do not
  /// modify them. The returned records are safe copies.
  List<Map<String, dynamic>> query({
    bool Function(Map<String, dynamic> record)? where,
    int Function(Map<String, dynamic> a, Map<String, dynamic> b)? sort,
    int offset = 0,
    int? limit,
  }) {
    var rows = <Map<String, dynamic>>[];
    _data.forEach((id, record) {
      final view = <String, dynamic>{...record, 'id': id};
      if (where == null || where(view)) rows.add(view);
    });
    if (sort != null) rows.sort(sort);
    if (offset > 0) rows = rows.skip(offset).toList();
    if (limit != null) rows = rows.take(limit).toList();
    return rows.map(_cloneMap).toList();
  }

  /// First record matching [where], or null.
  Map<String, dynamic>? firstWhere(
    bool Function(Map<String, dynamic> record) where,
  ) {
    for (final entry in _data.entries) {
      final view = <String, dynamic>{...entry.value, 'id': entry.key};
      if (where(view)) return _cloneMap(view);
    }
    return null;
  }

  /// Number of records, optionally only those matching [where].
  int count([bool Function(Map<String, dynamic> record)? where]) {
    if (where == null) return _data.length;
    var n = 0;
    _data.forEach((id, record) {
      if (where({...record, 'id': id})) n++;
    });
    return n;
  }

  bool containsId(String id) => _data.containsKey(id);

  /// All ids, in insertion order.
  List<String> get ids => List<String>.unmodifiable(_data.keys);

  int get length => _data.length;
  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  // ------------------------------------------------------------ reactive

  /// Every change, as it happens.
  Stream<SmartBoxEvent> get events => _events.stream;

  /// Emits the current records right away, then again after every change.
  /// Perfect for `StreamBuilder`. Accepts the same options as [query].
  Stream<List<Map<String, dynamic>>> watchAll({
    bool Function(Map<String, dynamic> record)? where,
    int Function(Map<String, dynamic> a, Map<String, dynamic> b)? sort,
    int offset = 0,
    int? limit,
  }) {
    return _watch<List<Map<String, dynamic>>>(
      () => query(where: where, sort: sort, offset: offset, limit: limit),
      (_) => true,
    );
  }

  /// Emits the record at [id] right away (null if missing), then again
  /// whenever that record changes or the box is cleared.
  Stream<Map<String, dynamic>?> watch(String id) {
    return _watch<Map<String, dynamic>?>(
      () => get(id),
      (e) => e.id == null || e.id == id,
    );
  }

  Stream<T> _watch<T>(T Function() read, bool Function(SmartBoxEvent e) match) {
    late final StreamController<T> controller;
    StreamSubscription<SmartBoxEvent>? sub;
    var pending = false;

    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        sub = _events.stream.listen((event) {
          if (!match(event) || pending) return;
          pending = true;
          // Several changes in the same tick become a single emission.
          scheduleMicrotask(() {
            pending = false;
            if (!controller.isClosed) controller.add(read());
          });
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  // ---------------------------------------------------------- durability

  /// Waits until everything written so far is safely on disk.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _persist();
  }

  /// Saves pending changes and releases this box. Using it afterwards
  /// throws. Usually you never need this - boxes live for the whole app.
  Future<void> close() async {
    if (_closed) return;
    await flush();
    _closed = true;
    await _events.close();
  }

  bool get isClosed => _closed;

  void _ensureOpen() {
    if (_closed) throw StateError('Box "$name" is closed.');
  }

  Future<void> _commit(List<SmartBoxEvent> events, bool flushNow) {
    _markDirty();
    if (!_events.isClosed) {
      for (final event in events) {
        _events.add(event);
      }
    }
    if (flushNow || _writeDelay == Duration.zero) return flush();
    return Future<void>.value();
  }

  void _markDirty() {
    _dirty = true;
    if (_writeDelay == Duration.zero) return;
    _timer?.cancel();
    _timer = Timer(_writeDelay, () {
      _timer = null;
      _persist().catchError((Object e, StackTrace st) => _report(e, st));
    });
  }

  Future<void> _persist() {
    final next = _writing.then((_) => _writeIfDirty());
    // Keep the chain alive even if this write fails.
    _writing = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeIfDirty() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await _writeSnapshot();
    } catch (_) {
      _dirty = true; // try again on the next write / flush
      rethrow;
    }
  }

  Future<void> _writeSnapshot() async {
    final payload = <String, dynamic>{
      _magic: _formatVersion,
      'schema': _schema,
      'nextId': _autoId,
      // Shallow copy is enough: stored records are never mutated.
      'data': Map<String, Map<String, dynamic>>.of(_data),
    };
    Uint8List bytes = _data.length >= _isolateThreshold
        ? await _encodeInIsolate(payload)
        : Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (_encrypted) {
      final cipher = await SmartCrypto.encrypt(bytes);
      bytes = Uint8List(_encMagic.length + cipher.length)
        ..setRange(0, _encMagic.length, _encMagic)
        ..setRange(_encMagic.length, _encMagic.length + cipher.length, cipher);
    }

    // Atomic write: temp file first, then rename over the real file.
    await _tmp.writeAsBytes(bytes, flush: true);
    if (await _file.exists()) {
      await _file.rename(_bak.path); // keep last good copy
    }
    await _tmp.rename(_file.path);
  }

  void _report(Object error, StackTrace stackTrace) {
    final handler = _onError;
    if (handler != null) {
      handler(error, stackTrace);
    } else {
      debugPrint('smart_local_storage [$name]: $error');
    }
  }

  // ------------------------------------------------------------- helpers

  SmartBoxEvent _putEvent(String id, bool existed) => SmartBoxEvent(
        existed ? SmartBoxEventType.updated : SmartBoxEventType.added,
        id,
      );

  void _bumpAutoId(String id) {
    final n = int.tryParse(id);
    if (n != null && n >= _autoId) _autoId = n + 1;
  }

  /// Validates + deep-copies user data. `'id'` is reserved for the record id.
  Map<String, dynamic> _cloneRecord(Map<String, dynamic> data) {
    final copy = _cloneMap(data);
    copy.remove('id');
    return copy;
  }

  static Map<String, dynamic> _cloneMap(Map source) {
    final out = <String, dynamic>{};
    source.forEach((key, value) {
      if (key is! String) {
        throw ArgumentError('Map keys must be Strings, got "$key".');
      }
      out[key] = _cloneValue(value);
    });
    return out;
  }

  static Object? _cloneValue(Object? value) {
    if (value == null || value is bool || value is String) return value;
    if (value is num) {
      if (value is double && !value.isFinite) {
        throw ArgumentError('NaN / Infinity cannot be stored.');
      }
      return value;
    }
    if (value is List) return value.map(_cloneValue).toList();
    if (value is Map) return _cloneMap(value);
    throw ArgumentError(
      'Cannot store a ${value.runtimeType}. Use String, num, bool, null, '
      'List or Map (e.g. DateTime -> toIso8601String()).',
    );
  }
}

// Top-level so the isolate closure never captures a SmartBox (which holds
// files and streams that cannot be sent between isolates).
Future<Uint8List> _encodeInIsolate(Map<String, dynamic> payload) =>
    Isolate.run(() => Uint8List.fromList(utf8.encode(jsonEncode(payload))));

Future<Object?> _decodeInIsolate(Uint8List bytes) =>
    Isolate.run(() => jsonDecode(utf8.decode(bytes)));
