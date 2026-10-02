## 2.2.0

### Added
- `SmartLocalStorage.lazyBox(...)` / `SmartLazyBox`: disk-backed box for big data. Only ids stay in memory, records are read from disk on demand (append-only log with automatic compaction, crash-safe). Reads are async.
- Secondary indexes for lazy boxes: `indexes: [...]`, `findBy`, `findRange`.
- `encrypted: true` on `box(...)` and `lazyBox(...)`: AES-256-GCM, key stored in Android Keystore / iOS Keychain (native code, no pub.dev package).
- Unit tests, `analysis_options.yaml` and a GitHub Actions workflow (analyze + test on stable and beta, weekly).
- Example app: new "Big data" screen.

### Changed
- Android: encryption needs API 23+ (plain storage still works from API 21).
- iOS: minimum raised to 13.0 (CryptoKit).
- Box files are written as bytes (same content as before for plain boxes).

## 2.1.0

### Added
- In-memory cache with debounced, batched disk writes (`writeDelay`).
- Atomic saves (temp file + rename) with `.bak` backup; corrupt files are kept as `.corrupt` and the box recovers from the backup.
- Background isolate for encoding/decoding big boxes (`isolateThreshold`).
- Reactive streams: `watchAll()`, `watch(id)`, `events` (also on `SmartModelBox`).
- `query(where, sort, offset, limit)`, `firstWhere`, `count`, `getMany`, `ids`.
- Batch ops: `addAll`, `putAll`, `deleteAll`, `deleteWhere`.
- Schema versioning with `version` + `onMigrate`.
- `flush()`, `flushAll()`, `close()`, `closeAll()`; automatic flush when the app leaves the foreground.
- `flush: true` option on every write method.
- New entry file `package:smart_local_cache/smart_local_cache.dart` (the old `smart_local_storage.dart` still works).

### Fixed
- Two simultaneous `SmartLocalStorage.box(name)` calls no longer open two instances of the same file.
- Auto-id counter is saved, so ids are not reused after deleting the newest record and restarting.
- Stored data is copied and validated: later changes to your map no longer leak into the box, and unsupported types (e.g. `DateTime`) throw immediately.
- Box names are validated (letters, digits, `_`, `-`).

### Behavior changes
- `add/put/update/delete` return once memory is updated; the disk write follows ~300 ms later (use `flush: true` or `writeDelay: Duration.zero` for the old write-through behavior).
- `'id'` is reserved: the box id always wins over an `'id'` key inside your data.
- Files written by older versions are read as before and upgraded on the next save.

## 2.0.1

### Fixed
- Fixed edge cases where reading a missing key could return an unexpected value instead of `null`.
- Fixed data type mismatch issues when reading values saved as a different type.
- Improved error handling so storage failures no longer crash the app.

### Improved
- Better performance when reading and writing large data.
- Cleaner internal code and reduced package size.

### Docs
- Updated README with clearer setup and usage steps.
- Added more usage examples in the example app.

## 2.0.0

### Breaking Changes
- Updated the public API for a simpler and more consistent usage.
- Minimum Dart/Flutter SDK constraints were raised. Check `pubspec.yaml` before upgrading.
- Some method names and parameters were changed. See the migration guide below.

### Added
- Support for storing more data types (String, int, double, bool, List, Map).
- Method to check if a key exists.
- Method to clear all stored data.
- Null safety improvements across the package.

### Changed
- Updated all dependencies to their latest versions.
- Rewrote the example app to show the new API.

### Migration Guide
- Update the package version to `^2.0.0` in `pubspec.yaml`.
- Run `flutter pub get`.
- Replace old method calls with the new API names.

## 1.0.0

### Added
- First stable release.
- Simple API to save, read, and remove data locally.
- Support for common data types.
- Example app and README.

## 0.0.1

### Added
- Initial pre-release.
