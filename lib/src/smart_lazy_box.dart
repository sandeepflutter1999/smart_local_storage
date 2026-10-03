import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'smart_box.dart' show SmartBoxEvent, SmartBoxEventType;
import 'smart_crypto.dart';
import 'smart_paths.dart';

/// A disk-backed box for BIG data. Only the ids (and where each record sits
/// in the file) live in memory - the records themselves stay on disk and are
/// read one at a time. A million records cost tens of MB of RAM, not GBs.
///
/// How it works: an append-only log. Every write adds one line to the end of
/// the file (fast, no rewriting), deletes add a tombstone line, and the file
/// is compacted automatically when too much of it is dead data. A crash can
/// only damage the last unfinished line, which is dropped on the next open.
///
/// Unlike [SmartBox] reads are async (they hit the disk).
class SmartLazyBox {
  SmartLazyBox._(
    this.name,
    this._file, {
    required bool encrypted,
    required List<String> indexedFields,
    required int compactMinBytes,
  })  : _encrypted = encrypted,
        _indexedFields = indexedFields,
        _compactMinBytes = compactMinBytes;

  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_\-]+$');
  static const int _nl = 0x0A;
  static const int _tab = 0x09;

  final String name;
  final File _file;
  final bool _encrypted;
  final List<String> _indexedFields;
  final int _compactMinBytes;

  /// id -> where the payload sits in the log file.
  final LinkedHashMap<String, _Loc> _index = LinkedHashMap();
  final StreamController<SmartBoxEvent> _events =
      StreamController<SmartBoxEvent>.broadcast();

  /// field -> secondary index (built lazily the first time it is used).
  final Map<String, _FieldIndex> _fieldIndexes = {};

  RandomAccessFile? _writer;
  RandomAccessFile? _reader;
  int _length = 0; // bytes in the log file
  int _garbage = 0; // bytes belonging to overwritten / deleted records
  int _autoId = 0;
  bool _closed = false;
  Future<void> _lock = Future<void>.value();

  // ---------------------------------------------------------------- open

  /// Opens (creating if needed) the lazy box called [name]. Prefer
  /// `SmartLocalStorage.lazyBox`.
  static Future<SmartLazyBox> open(
    String name, {
    bool encrypted = false,
    List<String> indexes = const [],
    int compactMinBytes = 1024 * 1024,
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
    if (!await dir.exists()) await dir.create(recursive: true);
    final box = SmartLazyBox._(
      name,
      File('${dir.path}/$name.slog'),
      encrypted: encrypted,
      indexedFields: indexes,
      compactMinBytes: compactMinBytes,
    );
    await box._scan();
    await box._openHandles();
    return box;
  }

  Future<void> _openHandles() async {
    if (!await _file.exists()) await _file.create(recursive: true);
    _writer = await _file.open(mode: FileMode.append);
    _reader = await _file.open(mode: FileMode.read);
  }

  /// Rebuilds the in-memory index by reading the log once, line by line.
  /// Line formats (UTF-8, tab separated):
  /// ```text
  /// P  id  payload   put (payload is JSON, or base64 when encrypted)
  /// D  id            delete
  /// N  number        next auto id (written by compaction)
  /// ```
  Future<void> _scan() async {
    _index.clear();
    _length = 0;
    _garbage = 0;
    _autoId = 0;
    if (!await _file.exists()) return;

    var lineStart = 0; // byte offset where the current line starts
    var goodEnd = 0; // end of the last complete line
    final pending = BytesBuilder();

    void handleLine(Uint8List line, int start) {
      if (line.isEmpty) return;
      final kind = line[0];
      if (kind != 0x4E && kind != 0x50 && kind != 0x44) return; // unknown line
      if (line.length < 3 || line[1] != _tab) return; // damaged line
      if (kind == 0x4E) {
        // N <number>
        final n = int.tryParse(utf8.decode(line.sublist(2)));
        if (n != null && n > _autoId) _autoId = n;
        return;
      }
      final idStart = 2;
      var idEnd = idStart;
      while (idEnd < line.length && line[idEnd] != _tab) {
        idEnd++;
      }
      final id = utf8.decode(line.sublist(idStart, idEnd));
      final asNumber = int.tryParse(id);
      if (asNumber != null && asNumber >= _autoId) _autoId = asNumber + 1;

      final old = _index[id];
      if (old != null) _garbage += old.lineBytes;
      if (kind == 0x50 && idEnd < line.length) {
        final payloadOffset = start + idEnd + 1;
        final payloadLength = line.length - idEnd - 1;
        _index[id] = _Loc(payloadOffset, payloadLength, line.length + 1);
      } else {
        _index.remove(id);
        _garbage += line.length + 1; // the tombstone itself is dead weight
      }
    }

    await for (final raw in _file.openRead()) {
      final chunk = raw is Uint8List ? raw : Uint8List.fromList(raw);
      var from = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != _nl) continue;
        pending.add(Uint8List.sublistView(chunk, from, i));
        final line = pending.takeBytes();
        handleLine(line, lineStart);
        lineStart += line.length + 1;
        goodEnd = lineStart;
        from = i + 1;
      }
      if (from < chunk.length) {
        pending.add(Uint8List.sublistView(chunk, from));
      }
    }

    // Anything after the last newline is an unfinished write (crash): cut it.
    final fileLength = await _file.length();
    if (goodEnd < fileLength) {
      final raf = await _file.open(mode: FileMode.append);
      await raf.truncate(goodEnd);
      await raf.close();
    }
    _length = goodEnd;
  }

  // -------------------------------------------------------------- writes

  /// Adds a record with an auto-generated id. Returns the id.
  Future<String> add(Map<String, dynamic> data, {bool flush = false}) {
    return _locked(() async {
      final id = (_autoId++).toString();
      await _append(id, _cloneRecord(data));
      _emit(SmartBoxEventType.added, id);
      if (flush) await _flushHandle();
      return id;
    });
  }

  /// Adds many records at once. Returns their ids.
  Future<List<String>> addAll(
    Iterable<Map<String, dynamic>> items, {
    bool flush = false,
  }) {
    return _locked(() async {
      final ids = <String>[];
      for (final item in items) {
        final id = (_autoId++).toString();
        await _append(id, _cloneRecord(item));
        ids.add(id);
        _emit(SmartBoxEventType.added, id);
      }
      if (flush) await _flushHandle();
      return ids;
    });
  }

  /// Inserts or overwrites the record at [id].
  Future<void> put(String id, Map<String, dynamic> data, {bool flush = false}) {
    return _locked(() async {
      final existed = _index.containsKey(id);
      await _append(id, _cloneRecord(data));
      _emit(existed ? SmartBoxEventType.updated : SmartBoxEventType.added, id);
      if (flush) await _flushHandle();
    });
  }

  /// Merges [data] into the existing record at [id] (must exist).
  Future<void> update(
    String id,
    Map<String, dynamic> data, {
    bool flush = false,
  }) {
    return _locked(() async {
      final existing = await _readRaw(id);
      if (existing == null) {
        throw StateError('No record with id "$id" in box "$name".');
      }
      await _append(id, {...existing, ..._cloneRecord(data)});
      _emit(SmartBoxEventType.updated, id);
      if (flush) await _flushHandle();
    });
  }

  Future<void> delete(String id, {bool flush = false}) {
    return _locked(() async {
      if (!_index.containsKey(id)) return;
      await _tombstone(id);
      _emit(SmartBoxEventType.deleted, id);
      if (flush) await _flushHandle();
    });
  }

  /// Deletes many ids at once.
  Future<void> deleteAll(Iterable<String> ids, {bool flush = false}) {
    return _locked(() async {
      for (final id in ids.toList()) {
        if (!_index.containsKey(id)) continue;
        await _tombstone(id);
        _emit(SmartBoxEventType.deleted, id);
      }
      if (flush) await _flushHandle();
    });
  }

  /// Deletes every record for which [test] returns true. Returns the count.
  Future<int> deleteWhere(
    bool Function(Map<String, dynamic> record) test, {
    bool flush = false,
  }) async {
    final matched = <String>[];
    await for (final record in stream()) {
      if (test(record)) matched.add(record['id'] as String);
    }
    await deleteAll(matched, flush: flush);
    return matched.length;
  }

  /// Removes every record and resets the auto-id counter.
  Future<void> clear({bool flush = false}) {
    return _locked(() async {
      await _closeHandles();
      await _file.writeAsBytes(const [], flush: true);
      _index.clear();
      _fieldIndexes.clear();
      _length = 0;
      _garbage = 0;
      _autoId = 0;
      await _openHandles();
      _emit(SmartBoxEventType.cleared, null);
    });
  }

  // --------------------------------------------------------------- reads

  /// The record at [id] (with `'id'` included), or null.
  Future<Map<String, dynamic>?> get(String id) {
    return _locked(() async {
      final record = await _readRaw(id);
      if (record == null) return null;
      return {...record, 'id': id};
    });
  }

  /// Several records by id (missing ids are skipped).
  Future<List<Map<String, dynamic>>> getMany(Iterable<String> ids) {
    return _locked(() async {
      final out = <Map<String, dynamic>>[];
      for (final id in ids) {
        final record = await _readRaw(id);
        if (record != null) out.add({...record, 'id': id});
      }
      return out;
    });
  }

  /// Streams every record one at a time - memory stays flat no matter how
  /// big the box is. Prefer this (or [query] with a [limit]) over [getAll]
  /// for large boxes.
  Stream<Map<String, dynamic>> stream() async* {
    final snapshot = _index.keys.toList();
    for (final id in snapshot) {
      final record = await _locked(() => _readRaw(id));
      if (record != null) yield {...record, 'id': id};
    }
  }

  /// Every record as one list. Loads everything into memory.
  Future<List<Map<String, dynamic>>> getAll() => query();

  /// Filter / sort / page. [where] runs one record at a time so memory only
  /// grows with the matches. With [sort] the matches are held in memory.
  Future<List<Map<String, dynamic>>> query({
    bool Function(Map<String, dynamic> record)? where,
    int Function(Map<String, dynamic> a, Map<String, dynamic> b)? sort,
    int offset = 0,
    int? limit,
  }) async {
    final rows = <Map<String, dynamic>>[];
    // Without a sort we can stop early once we have enough rows.
    final stopAt = (sort == null && limit != null) ? offset + limit : null;
    await for (final record in stream()) {
      if (where != null && !where(record)) continue;
      rows.add(record);
      if (stopAt != null && rows.length >= stopAt) break;
    }
    if (sort != null) rows.sort(sort);
    var out = rows;
    if (offset > 0) out = out.skip(offset).toList();
    if (limit != null) out = out.take(limit).toList();
    return out;
  }

  /// Records whose [field] equals [value], using an index (fast, no full
  /// scan). The field must be listed in `indexes:` when opening the box.
  Future<List<Map<String, dynamic>>> findBy(String field, Object? value) async {
    final index = await _indexFor(field);
    return getMany(index.ids(value).toList());
  }

  /// Records whose [field] is between [min] and [max] (inclusive; either may
  /// be null for "no limit"), sorted by that field. Uses an index. Works with
  /// numbers and strings. The field must be listed in `indexes:`.
  Future<List<Map<String, dynamic>>> findRange(
    String field, {
    Object? min,
    Object? max,
    bool descending = false,
    int? limit,
  }) async {
    final index = await _indexFor(field);
    var ids = index.range(min, max).toList();
    if (descending) ids = ids.reversed.toList();
    if (limit != null) ids = ids.take(limit).toList();
    return getMany(ids);
  }

  /// First record matching [where], or null.
  Future<Map<String, dynamic>?> firstWhere(
    bool Function(Map<String, dynamic> record) where,
  ) async {
    await for (final record in stream()) {
      if (where(record)) return record;
    }
    return null;
  }

  /// Number of records, optionally only those matching [where].
  Future<int> count([bool Function(Map<String, dynamic> record)? where]) async {
    if (where == null) return _index.length;
    var n = 0;
    await for (final record in stream()) {
      if (where(record)) n++;
    }
    return n;
  }

  bool containsId(String id) => _index.containsKey(id);
  List<String> get ids => List<String>.unmodifiable(_index.keys);
  int get length => _index.length;
  bool get isEmpty => _index.isEmpty;
  bool get isNotEmpty => _index.isNotEmpty;

  /// Size of the log file on disk, in bytes.
  int get diskBytes => _length;

  // ------------------------------------------------------------ reactive

  /// Every change, as it happens.
  Stream<SmartBoxEvent> get events => _events.stream;

  /// Emits the matching records now and again after every change.
  /// Re-runs [query] each time, so keep [limit] small on big boxes.
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

  /// Emits the record at [id] now (null if missing) and when it changes.
  Stream<Map<String, dynamic>?> watch(String id) {
    return _watch<Map<String, dynamic>?>(
      () => get(id),
      (e) => e.id == null || e.id == id,
    );
  }

  Stream<T> _watch<T>(
    Future<T> Function() read,
    bool Function(SmartBoxEvent e) match,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<SmartBoxEvent>? sub;
    var pending = false;

    Future<void> emit() async {
      try {
        final value = await read();
        if (!controller.isClosed) controller.add(value);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        emit();
        sub = _events.stream.listen((event) {
          if (!match(event) || pending) return;
          pending = true;
          scheduleMicrotask(() {
            pending = false;
            emit();
          });
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  // ---------------------------------------------------------- durability

  /// Forces everything written so far onto the disk surface (fsync).
  /// Writes already survive an app crash without this; use it before
  /// something that could lose power or kill the OS.
  Future<void> flush() => _locked(_flushHandle);

  /// Rewrites the log without dead data. Runs automatically when more than
  /// half the file is garbage; call it yourself after huge deletes.
  Future<void> compact() => _locked(_compact);

  Future<void> close() async {
    if (_closed) return;
    await _locked(() async {
      await _flushHandle();
      await _closeHandles();
      _closed = true;
    });
    await _events.close();
  }

  bool get isClosed => _closed;

  Future<void> _flushHandle() async => _writer?.flush();

  Future<void> _closeHandles() async {
    await _writer?.close();
    await _reader?.close();
    _writer = null;
    _reader = null;
  }

  // ------------------------------------------------------------- internals

  /// Runs one operation at a time so reads/writes/compaction never overlap.
  Future<T> _locked<T>(Future<T> Function() action) {
    if (_closed) {
      return Future<T>.error(StateError('Box "$name" is closed.'));
    }
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _emit(SmartBoxEventType type, String? id) {
    if (!_events.isClosed) _events.add(SmartBoxEvent(type, id));
  }

  Future<Uint8List> _encodePayload(Map<String, dynamic> record) async {
    final json = utf8.encode(jsonEncode(record));
    if (!_encrypted) return Uint8List.fromList(json);
    final cipher = await SmartCrypto.encrypt(Uint8List.fromList(json));
    return Uint8List.fromList(utf8.encode(base64.encode(cipher)));
  }

  Future<Map<String, dynamic>> _decodePayload(Uint8List bytes) async {
    var json = bytes;
    if (_encrypted) {
      json = await SmartCrypto.decrypt(base64.decode(utf8.decode(bytes)));
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(json)) as Map);
  }

  /// Reads a record's data (without 'id') from disk. Call inside the lock.
  Future<Map<String, dynamic>?> _readRaw(String id) async {
    final loc = _index[id];
    if (loc == null) return null;
    final reader = _reader!;
    await reader.setPosition(loc.offset);
    final bytes = await reader.read(loc.length);
    return _decodePayload(bytes);
  }

  Future<void> _append(String id, Map<String, dynamic> record) async {
    _checkId(id);
    final payload = await _encodePayload(record);
    final idBytes = utf8.encode(id);
    final line = BytesBuilder(copy: false)
      ..addByte(0x50) // P
      ..addByte(_tab)
      ..add(idBytes)
      ..addByte(_tab)
      ..add(payload)
      ..addByte(_nl);
    final bytes = line.takeBytes();
    await _writer!.writeFrom(bytes);

    final old = _index[id];
    if (old != null) _garbage += old.lineBytes;
    final payloadOffset = _length + 2 + idBytes.length + 1;
    _index[id] = _Loc(payloadOffset, payload.length, bytes.length);
    _length += bytes.length;

    _updateFieldIndexes(id, record);
    await _maybeCompact();
  }

  Future<void> _tombstone(String id) async {
    final idBytes = utf8.encode(id);
    final line = BytesBuilder(copy: false)
      ..addByte(0x44) // D
      ..addByte(_tab)
      ..add(idBytes)
      ..addByte(_nl);
    final bytes = line.takeBytes();
    await _writer!.writeFrom(bytes);

    final old = _index.remove(id);
    if (old != null) _garbage += old.lineBytes;
    _garbage += bytes.length;
    _length += bytes.length;

    for (final index in _fieldIndexes.values) {
      index.remove(id);
    }
    await _maybeCompact();
  }

  Future<void> _maybeCompact() async {
    if (_garbage >= _compactMinBytes && _garbage > _length ~/ 2) {
      await _compact();
    }
  }

  /// Copies live records into a fresh file, then swaps it in (atomic rename).
  Future<void> _compact() async {
    final tmp = File('${_file.path}.compact');
    final sink = tmp.openWrite();
    final newIndex = <String, _Loc>{};
    var offset = 0;

    void write(List<int> bytes) {
      sink.add(bytes);
      offset += bytes.length;
    }

    // Keep the auto-id counter even though deleted ids disappear.
    write(utf8.encode('N\t$_autoId\n'));
    final reader = _reader!;
    for (final entry in _index.entries) {
      await reader.setPosition(entry.value.offset);
      final payload = await reader.read(entry.value.length);
      final idBytes = utf8.encode(entry.key);
      final header = <int>[0x50, _tab, ...idBytes, _tab];
      final payloadOffset = offset + header.length;
      write(header);
      write(payload);
      write(const [_nl]);
      newIndex[entry.key] =
          _Loc(payloadOffset, payload.length, header.length + payload.length + 1);
    }
    await sink.flush();
    await sink.close();

    await _closeHandles();
    await tmp.rename(_file.path);
    _index
      ..clear()
      ..addAll(newIndex);
    _length = offset;
    _garbage = 0;
    await _openHandles();
  }

  void _checkId(String id) {
    if (id.isEmpty || id.contains('\t') || id.contains('\n')) {
      throw ArgumentError.value(
        id,
        'id',
        'Ids must not be empty or contain tabs / new lines.',
      );
    }
  }

  // ----------------------------------------------------- secondary indexes

  Future<_FieldIndex> _indexFor(String field) {
    if (!_indexedFields.contains(field)) {
      throw ArgumentError.value(
        field,
        'field',
        'Not indexed. Add it to `indexes:` when opening box "$name".',
      );
    }
    return _locked(() async {
      var index = _fieldIndexes[field];
      if (index != null) return index;
      // First use: one pass over the box builds the index; after that it is
      // kept up to date on every write.
      index = _FieldIndex(field);
      for (final id in _index.keys.toList()) {
        final record = await _readRaw(id);
        if (record != null) index.set(id, record[field]);
      }
      _fieldIndexes[field] = index;
      return index;
    });
  }

  void _updateFieldIndexes(String id, Map<String, dynamic> record) {
    for (final index in _fieldIndexes.values) {
      index.set(id, record[index.field]);
    }
  }

  // ------------------------------------------------------------- cloning

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

class _Loc {
  const _Loc(this.offset, this.length, this.lineBytes);

  final int offset; // where the payload starts in the file
  final int length; // payload size in bytes
  final int lineBytes; // whole line incl. header and newline
}

/// Orders mixed values: numbers first, then strings, then booleans.
int _compareValues(Object a, Object b) {
  int rank(Object v) => v is num ? 0 : (v is String ? 1 : 2);
  final ra = rank(a);
  final rb = rank(b);
  if (ra != rb) return ra.compareTo(rb);
  if (a is num) return a.compareTo(b as num);
  if (a is String) return a.compareTo(b as String);
  return (a as bool ? 1 : 0).compareTo((b as bool) ? 1 : 0);
}

/// value -> ids, kept sorted so ranges are cheap. Only num, String and bool
/// values are indexed (null / lists / maps are skipped).
class _FieldIndex {
  _FieldIndex(this.field);

  final String field;
  final SplayTreeMap<Object, Set<String>> _byValue =
      SplayTreeMap<Object, Set<String>>(_compareValues);
  final Map<String, Object> _valueOf = {};

  void set(String id, Object? value) {
    remove(id);
    if (value is num || value is String || value is bool) {
      final v = value as Object;
      _byValue.putIfAbsent(v, () => <String>{}).add(id);
      _valueOf[id] = v;
    }
  }

  void remove(String id) {
    final old = _valueOf.remove(id);
    if (old == null) return;
    final ids = _byValue[old];
    if (ids == null) return;
    ids.remove(id);
    if (ids.isEmpty) _byValue.remove(old);
  }

  Iterable<String> ids(Object? value) {
    if (value is! num && value is! String && value is! bool) return const [];
    return _byValue[value as Object] ?? const <String>{};
  }

  Iterable<String> range(Object? min, Object? max) sync* {
    for (final entry in _byValue.entries) {
      if (min != null && _compareValues(entry.key, min) < 0) continue;
      if (max != null && _compareValues(entry.key, max) > 0) break;
      yield* entry.value;
    }
  }
}
