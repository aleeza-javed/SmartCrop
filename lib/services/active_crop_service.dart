import 'package:shared_preferences/shared_preferences.dart';

class ActiveCropService {
  static const _key = 'active_crop';
  static const _defaultCrop = 'wheat';

  static Future<String> getActiveCrop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? _defaultCrop;
  }

  static Future<void> setActiveCrop(String crop) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, crop.toLowerCase().trim());
  }

  static Future<void> clearActiveCrop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
