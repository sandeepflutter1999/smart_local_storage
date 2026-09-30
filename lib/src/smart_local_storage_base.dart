import 'smart_box.dart';

/// Entry point: open named boxes to store lists of records (with ids)
/// on disk — plain Maps in, plain Maps out, no model classes needed.
class SmartLocalStorage {
  SmartLocalStorage._();

  static final Map<String, SmartBox> _openBoxes = {};

  /// Opens the box called [name] (creating it on first use) and caches it,
  /// so calling this again with the same name returns the same instance.
  static Future<SmartBox> box(String name) async {
    final existing = _openBoxes[name];
    if (existing != null) return existing;
    final box = await SmartBox.open(name);
    _openBoxes[name] = box;
    return box;
  }
}
