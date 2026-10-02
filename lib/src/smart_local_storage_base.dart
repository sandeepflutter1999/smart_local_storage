import 'package:flutter/widgets.dart';

import 'smart_box.dart';
import 'smart_lazy_box.dart';

/// Entry point: open named boxes to store lists of records (with ids)
/// on disk - plain Maps in, plain Maps out, no model classes needed.
class SmartLocalStorage {
  SmartLocalStorage._();

  static final Map<String, SmartBox> _openBoxes = {};
  static final Map<String, Future<SmartBox>> _opening = {};
  static final Map<String, SmartLazyBox> _openLazy = {};
  static final Map<String, Future<SmartLazyBox>> _openingLazy = {};
  static bool _observing = false;

  /// Opens the box called [name] (creating it on first use) and caches it,
  /// so calling this again with the same name returns the same instance -
  /// even if two places ask at the same moment.
  ///
  /// Options (only used the first time a box is opened):
  /// * [version] + [onMigrate] - upgrade old records when your data shape
  ///   changes. Bump [version] and fix records inside [onMigrate].
  /// * [writeDelay] - how long to wait before saving to disk, so rapid
  ///   changes become one write. `Duration.zero` = save on every change.
  /// * [isolateThreshold] - boxes with at least this many records are
  ///   encoded on a background isolate.
  /// * [encrypted] - encrypt the box file with AES-256-GCM using a key kept
  ///   in the Android Keystore / iOS Keychain. Existing plain data is
  ///   encrypted on the next save.
  /// * [onError] - called if a background save fails.
  static Future<SmartBox> box(
    String name, {
    int version = 1,
    SmartMigration? onMigrate,
    Duration writeDelay = const Duration(milliseconds: 300),
    int isolateThreshold = 500,
    bool encrypted = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final open = _openBoxes[name];
    if (open != null && !open.isClosed) return Future.value(open);

    final pending = _opening[name];
    if (pending != null) return pending;

    _ensureLifecycleFlush();
    final future = _openNew(
      name,
      version: version,
      onMigrate: onMigrate,
      writeDelay: writeDelay,
      isolateThreshold: isolateThreshold,
      encrypted: encrypted,
      onError: onError,
    );
    _opening[name] = future;
    return future;
  }

  static Future<SmartBox> _openNew(
    String name, {
    required int version,
    required SmartMigration? onMigrate,
    required Duration writeDelay,
    required int isolateThreshold,
    required bool encrypted,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      final box = await SmartBox.open(
        name,
        version: version,
        onMigrate: onMigrate,
        writeDelay: writeDelay,
        isolateThreshold: isolateThreshold,
        encrypted: encrypted,
        onError: onError,
      );
      _openBoxes[name] = box;
      return box;
    } finally {
      _opening.remove(name);
    }
  }

  /// Opens a disk-backed box for BIG data (see [SmartLazyBox]): only ids live
  /// in memory, records are read from disk on demand. Reads are async.
  ///
  /// * [indexes] - fields you want to search fast with `findBy` / `findRange`.
  /// * [encrypted] - encrypt every record (AES-256-GCM, OS-held key).
  /// * [compactMinBytes] - dead data needed before the file is rewritten.
  static Future<SmartLazyBox> lazyBox(
    String name, {
    List<String> indexes = const [],
    bool encrypted = false,
    int compactMinBytes = 1024 * 1024,
  }) {
    final open = _openLazy[name];
    if (open != null && !open.isClosed) return Future.value(open);

    final pending = _openingLazy[name];
    if (pending != null) return pending;

    _ensureLifecycleFlush();
    final future = _openNewLazy(
      name,
      indexes: indexes,
      encrypted: encrypted,
      compactMinBytes: compactMinBytes,
    );
    _openingLazy[name] = future;
    return future;
  }

  static Future<SmartLazyBox> _openNewLazy(
    String name, {
    required List<String> indexes,
    required bool encrypted,
    required int compactMinBytes,
  }) async {
    try {
      final box = await SmartLazyBox.open(
        name,
        indexes: indexes,
        encrypted: encrypted,
        compactMinBytes: compactMinBytes,
      );
      _openLazy[name] = box;
      return box;
    } finally {
      _openingLazy.remove(name);
    }
  }

  /// Saves every open box to disk right now.
  static Future<void> flushAll() => Future.wait([
        ..._openBoxes.values.map((b) => b.flush()),
        ..._openLazy.values.map((b) => b.flush()),
      ]);

  /// Saves and closes every open box (mostly useful in tests).
  static Future<void> closeAll() async {
    final boxes = _openBoxes.values.toList();
    final lazy = _openLazy.values.toList();
    _openBoxes.clear();
    _openLazy.clear();
    await Future.wait([
      ...boxes.map((b) => b.close()),
      ...lazy.map((b) => b.close()),
    ]);
  }

  /// Flush pending writes whenever the app leaves the foreground, so a
  /// swipe-away right after a change cannot lose data.
  static void _ensureLifecycleFlush() {
    if (_observing) return;
    _observing = true;
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(_LifecycleFlusher());
  }
}

class _LifecycleFlusher with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      SmartLocalStorage.flushAll();
    }
  }
}
