import 'dart:convert';
import 'package:smart_local_cache/smart_local_cache.dart';

class DbHelper {
  static final DbHelper _singleton = DbHelper._internal();
  factory DbHelper() => _singleton;
  DbHelper._internal();

  static late SmartBox _box;

  static const String _userModel = "userModel";
  static const String _fcmToken = "fcmToken";
  static const String _userType = "userTypeValue";
  static const String _userId = "userId";
  static const String _userToken = "userToken";
  static const String _isLoggedIn = "isLoggedIn";
  static const String _isSocial = "isSocial";
  static const String _loginTime = "loginTime";
  static const String _connectTime = "connectTime";
  static const String _theme = "theme";
  static const String _keyShowcaseSeen = "role_showcase_seen";

  static const JsonDecoder _decoder = JsonDecoder();
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Names of list boxes used in this session (so clearAll() can wipe them).
  static final Set<String> _listBoxes = {};

  /// Call once in main() before runApp(), replaces GetStorage.init().
  static Future<void> init() async {
    _box = await SmartLocalStorage.box('app_prefs');
  }

  // ---------- core ----------

  /// Saves a single value. Passing null deletes the key.
  /// Use flush: true for critical data (it waits until written to disk).
  void _save(String key, Object? value, {bool flush = false}) {
    if (value == null) {
      _box.delete(key, flush: flush);
    } else {
      _box.put(key, {'v': value}, flush: flush);
    }
  }

  /// Reads a single value, or null if the key does not exist.
  T? _get<T>(String key) => _box.get(key)?['v'] as T?;

  /// Use on logout: clears prefs and every list box opened in this session.
  void clearAll() {
    _box.clear(flush: true);
    for (final name in _listBoxes) {
      SmartLocalStorage.box(name).then((b) => b.clear(flush: true));
    }
  }

  /// Clears everything except the theme setting.
  void clearWithTheme() {
    _box.deleteAll(_box.ids.where((k) => k != _theme));
  }

  // =====================================================================
  //                               LIST
  // =====================================================================

  // ---------- A) Big lists: one record per item (cart, rooms, chat...) ----------

  Future<SmartBox> _listBox(String name) {
    _listBoxes.add(name);
    return SmartLocalStorage.box(name);
  }

  /// Replaces the whole list and saves it (a single disk write).
  Future<void> saveList(String name, List<Map<String, dynamic>> items) async {
    final b = await _listBox(name);
    // Run together so the UI refreshes only once.
    await Future.wait([b.clear(), b.addAll(items)]);
  }

  /// Returns the whole list (every item includes an 'id').
  Future<List<Map<String, dynamic>>> getList(String name) async =>
      (await _listBox(name)).getAll();

  /// Live list: use with StreamBuilder, no setState needed.
  Stream<List<Map<String, dynamic>>> watchList(String name) async* {
    final b = await _listBox(name);
    yield* b.watchAll();
  }

  /// Adds one item and returns its generated id.
  Future<String> addToList(String name, Map<String, dynamic> item) async =>
      (await _listBox(name)).add(item);

  /// Updates only the given fields of one item (does not rewrite the list).
  Future<void> updateInList(
      String name, String id, Map<String, dynamic> changes) async =>
      (await _listBox(name)).update(id, changes);

  /// Removes one item.
  Future<void> removeFromList(String name, String id) async =>
      (await _listBox(name)).delete(id);

  /// Removes every item of the list.
  Future<void> clearList(String name) async =>
      (await _listBox(name)).clear(flush: true);

  // Example with a model list (replace RoomModel with your own model):
  Future<void> saveRooms(List<RoomModel> rooms) =>
      saveList("rooms", rooms.map((e) => e.toJson()).toList());

  Future<List<RoomModel>> getRoomsList() async =>
      (await getList("rooms")).map(RoomModel.fromJson).toList();

  Stream<List<RoomModel>> watchRooms() =>
      watchList("rooms").map((l) => l.map(RoomModel.fromJson).toList());

  // ---------- B) Small lists: stored under a single key (recent searches, filters) ----------

  void saveRecentSearches(List<String> v) => _save("recentSearches", v);
  List<String> getRecentSearches() =>
      (_get<List>("recentSearches") ?? []).cast<String>();

  void saveFacilityList(List<String> v) => _save("facilityList", v);
  List<String> getFacilityList() =>
      (_get<List>("facilityList") ?? []).cast<String>();

  // Small model list
  void saveSmallRooms(List<RoomModel> rooms) =>
      _save("smallRooms", rooms.map((e) => e.toJson()).toList());

  List<RoomModel> getSmallRooms() => (_get<List>("smallRooms") ?? [])
      .map((e) => RoomModel.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  // ---------- notification ----------
  String convertNotificationEntityToString(NotificationEntity? e) =>
      _encoder.convert(e);

  NotificationEntity? convertStringToNotificationEntity(String? value) {
    if (value == null) return null;
    return NotificationEntity.fromJson(_decoder.convert(value));
  }

  // ---------- int ----------

  /// UserType: 0 - Personal, 1 - Church, 2 - Business, 3 - Non-Profit
  void saveUserType(int id) => _save(_userType, id);
  int? getUserType() => _get<int>(_userType);

  void saveProfileComplete(int count) => _save("count", count);
  int? getUserProfileComplete() => _get<int>("count");

  void saveBookingTutorialDone(int v) => _save("tutorialDone", v);
  int? getBookingTutorialDone() => _get<int>("tutorialDone");

  void saveMessageCount(int count) => _save("messCount", count);
  int? getUserMessCount() => _get<int>("messCount");

  void saveAddRoom(int v) => _save("addRoom", v);
  int? getAddRoom() => _get<int>("addRoom");

  void saveNotificationCount(int count) => _save("notificationCount", count);
  int? getNotificationCount() => _get<int>("notificationCount");

  // ---------- String ----------
  void saveFindRoomAdd(dynamic screenType) => _save("screenType", screenType);
  String? getFindScreenType() => _get<String>("screenType");

  void savePhoneNumber(String v) => _save("phoneNo", v);
  String? getPhoneNo() => _get<String>("phoneNo");

  void saveEmail(String v) => _save("email", v);
  String? getEmail() => _get<String>("email");

  void saveMinAmount(String v) => _save("minAmount", v);
  String? getMinAmount() => _get<String>("minAmount");

  void saveMaxAmount(String v) => _save("maxAmount", v);
  String? getMaxAmount() => _get<String>("maxAmount");

  void saveRoomType(String v) => _save("roomType", v);
  String? getRoomType() => _get<String>("roomType");

  void savePropertyType(String v) => _save("propertyType", v);
  String? getPropertyType() => _get<String>("propertyType");

  void saveAvailable(String v) => _save("available", v);
  String? getAvailable() => _get<String>("available");

  void saveFacilities(String v) => _save("facilities", v);
  String? getFacilities() => _get<String>("facilities");

  void saveSortBy(String v) => _save("sortBy", v);
  String? getSortBy() => _get<String>("sortBy");

  void saveAccommodation(String v) => _save("accommodation", v);
  String? getAccommodation() => _get<String>("accommodation");

  void saveRoomAccommodation(String v) => _save("accommodationRoom", v);
  String? getRoomAccommodation() => _get<String>("accommodationRoom");

  void saveRoomTypeInProvider(String v) => _save("roomTypeInProvider", v);
  String? getRoomTypeInProvider() => _get<String>("roomTypeInProvider");

  void saveAvailableInProvider(String v) => _save("availableInProvider", v);
  String? getAvailableInProvider() => _get<String>("availableInProvider");

  void saveSortInProvider(String v) => _save("sortInProvider", v);
  String? getSortAvailableInProvider() => _get<String>("sortInProvider");

  void saveMinInProvider(String v) => _save("minInProvider", v);
  String? getMinAvailableInProvider() => _get<String>("minInProvider");

  void saveMaxInProvider(String v) => _save("maxInProvider", v);
  String? getMaxAvailableInProvider() => _get<String>("maxInProvider");

  void saveFurnished(String v) => _save("isFurnished", v);
  String? getFurnished() => _get<String>("isFurnished");

  void saveCountryCode(String v) => _save("countryCode", v);
  String? getCountryCode() => _get<String>("countryCode");

  void saveRadius(String v) => _save("radius", v);
  String? getRadius() => _get<String>("radius");

  void saveLat(String v) => _save("lat", v);
  String? getLat() => _get<String>("lat");

  void saveLong(String v) => _save("lng", v);
  String? getLng() => _get<String>("lng");

  void saveAddress(String v) => _save("address", v);
  String? getAddress() => _get<String>("address");

  void saveUserOpenTime(String v) => _save("saveTime", v);
  String? getUserOpenTime() => _get<String>("saveTime");

  void savePrivateBathRoomInProviderSide(String v) => _save("bathroom", v);
  String? getPrivateBathRoomInProviderSide() => _get<String>("bathroom");

  void savePrivateBathRoomInSeeker(String v) => _save("bathroomSeeker", v);
  String? getPrivateBathRoomInSeeker() => _get<String>("bathroomSeeker");

  // ---------- provider search ----------
  void saveProviderLat(String v) => _save("providerLat", v);
  String? getProviderLat() => _get<String>("providerLat");

  void saveProviderLong(String v) => _save("providerLong", v);
  String? getProviderLong() => _get<String>("providerLong");

  void saveProviderAddress(String v) => _save("providerAddress", v);
  String? getProviderAddress() => _get<String>("providerAddress");

  void clearProviderSearch() =>
      _box.deleteAll(["providerLat", "providerLong", "providerAddress"]);

  // ---------- models ----------

  /// Models are stored as plain Maps (no jsonEncode needed).
  /// toJson() must return only String, num, bool, null, List or Map values.
  UserModel? getUserModel() {
    final m = _get<Map>(_userModel);
    return m == null ? null : UserModel.fromJson(Map<String, dynamic>.from(m));
  }

  /// flush: true so the user data survives even if the app is killed right away.
  void saveUserModel(UserModel? model) =>
      _save(_userModel, model?.toJson(), flush: true);

  BookingRequestResponseModel? getBookingData() {
    final m = _get<Map>("bookingData");
    return m == null
        ? null
        : BookingRequestResponseModel.fromJson(Map<String, dynamic>.from(m));
  }

  void saveBooking(BookingRequestResponseModel? data) =>
      _save("bookingData", data?.toJson());

  // ---------- bool ----------

  /// flush: true so the login state is never lost.
  bool getIsLoggedIn() => _get<bool>(_isLoggedIn) ?? false;
  void saveIsLoggedIn(bool v) => _save(_isLoggedIn, v, flush: true);

  bool? getLoggedFirst() => _get<bool>(_loginTime) ?? false;
  void saveLoggedFirst(bool v) => _save(_loginTime, v);

  bool? getConnectionFirst() => _get<bool>(_connectTime) ?? false;
  void saveConnectionFirst(bool v) => _save(_connectTime, v);

  bool getIsSocial() => _get<bool>(_isSocial) ?? false;
  void saveIsSocial(bool v) => _save(_isSocial, v);

  void setRoleShowcaseSeen(bool v) => _save(_keyShowcaseSeen, v);
  bool getRoleShowcaseSeen() => _get<bool>(_keyShowcaseSeen) ?? false;
}