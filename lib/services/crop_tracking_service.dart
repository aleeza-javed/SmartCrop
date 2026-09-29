import 'package:shared_preferences/shared_preferences.dart';

import '../models/crop_stage.dart';

/// Stores per-crop tracking settings in SharedPreferences: the sowing or
/// transplanting date, the selected season for two-season crops, and the
/// farmer's province.
///
/// Follows the shape of the existing services in this project: a static
/// instance, plain async methods, SharedPreferences underneath, no new
/// packages.
///
/// Keys:
///  * `sowing_date_{crop}`     - `yyyy-MM-dd`, the anchor date
///  * `season_variant_{crop}`  - e.g. `Spring` / `Autumn`
///  * `province`               - e.g. `punjab`
///
/// The province is app-wide rather than per crop: a farm sits in one place.
/// The date is stored without a time component because sowing is a day-level
/// event and a stray time would break the day arithmetic.
///
/// Read and parse errors are swallowed and treated as "not set", so a corrupt
/// value can never stop the Insights tab or the stage screen from building.
class CropTrackingService {
  static final CropTrackingService instance = CropTrackingService._();

  CropTrackingService._();

  static const String _prefix = 'sowing_date_';
  static const String _variantPrefix = 'season_variant_';
  static const String provinceKey = 'province';

  /// Public so tests and the UI can reason about the key.
  static String keyFor(String crop) =>
      '$_prefix${crop.trim().toLowerCase()}';

  static String variantKeyFor(String crop) =>
      '$_variantPrefix${crop.trim().toLowerCase()}';

  /// How far back the date picker reaches, as a margin over the crop's cycle.
  /// Shared with [sowingPickerRange] so the read check and the picker agree on
  /// what is still a reachable date.
  static const int _staleMarginDays = 60;

  /// True when [date] is too old to be a plausible anchor for [crop].
  ///
  /// A date is stale once the crop's cycle has fully elapsed, allowing the same
  /// margin the picker uses. Month-based perennials need no date at all, and a
  /// crop with no profile cannot be judged, so neither is ever stale. Dates in
  /// the future are never stale: a planned sowing is legitimate.
  static bool isStaleAnchor(String crop, DateTime date) {
    final profile = profileFor(crop);
    if (profile == null || profile.isMonthBased) return false;
    final limit = profile.maxDurationAcrossVariants + _staleMarginDays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final age = today.difference(DateTime(date.year, date.month, date.day)).inDays;
    return age > limit;
  }

  /// The saved anchor date for [crop], or null when none is stored.
  ///
  /// A stored date older than the crop's own cycle is discarded and reported
  /// as not set. The picker clamps when it opens, but a value already on disk
  /// is not re-checked, so a date entered for the wrong year - say the
  /// twenty-first of October a year back - would otherwise read as a finished
  /// crop for the life of the install. The margin matches the picker's own
  /// reach-back, so anything still reachable by hand is kept.
  Future<DateTime?> getSowingDate(String crop) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(crop));
      if (raw == null || raw.isEmpty) return null;
      final date = DateTime.tryParse(raw);
      if (date == null) return null;
      if (isStaleAnchor(crop, date)) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSowingDate(String crop, DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          keyFor(crop), _dateOnly(date).toIso8601String().substring(0, 10));
    } catch (_) {
      // A failed write only means the date has to be entered again.
    }
  }

  Future<void> clearSowingDate(String crop) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyFor(crop));
    } catch (_) {}
  }

  // ── Season variant ──────────────────────────────────────────────────────

  /// The season the user picked for [crop], or null when they have not chosen.
  Future<String?> getSeasonVariant(String crop) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(variantKeyFor(crop));
    } catch (_) {
      return null;
    }
  }

  Future<void> setSeasonVariant(String crop, String? variant) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (variant == null || variant.isEmpty) {
        await prefs.remove(variantKeyFor(crop));
      } else {
        await prefs.setString(variantKeyFor(crop), variant);
      }
    } catch (_) {}
  }

  // ── Province ────────────────────────────────────────────────────────────

  /// The farmer's province, or null until they pick one.
  Future<Province?> getProvince() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return Province.fromName(prefs.getString(provinceKey));
    } catch (_) {
      return null;
    }
  }

  Future<void> setProvince(Province province) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(provinceKey, province.name);
    } catch (_) {}
  }

  /// Every saved anchor date, keyed by the lowercased crop name.
  Future<Map<String, DateTime>> allSowingDates() async {
    final out = <String, DateTime>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) out[key.substring(_prefix.length)] = parsed;
      }
    } catch (_) {}
    return out;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
