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
