import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_rule.dart';
import 'crop_api_service.dart';

/// Loads the per-crop threshold table from the backend.
///
/// The authority for "what counts as too low" is
/// `Smart Crop Ml Model/fertillizer Alerts/crop_thresholds.py`, which the
/// Flask API serves from `GET /monitor/config`. Using it here means a
/// notification and the Sensors tab agree, and the `fertilizer` descriptors
/// that drive the advisory wording come from the same place.
///
/// Cached in SharedPreferences because the thresholds do not change between
/// releases but the backend is reachable only over the developer's LAN. Once
/// fetched, alerts keep working offline.
class CropThresholdService {
  static const _cacheKey = 'crop_thresholds_cache_v1';
  static const _timeout = Duration(seconds: 8);

  Map<String, dynamic>? _thresholds;
  bool _loaded = false;

  /// True once [load] has completed, whether from network or cache.
  bool get isLoaded => _loaded;

  /// The raw `CROP_THRESHOLDS` map, keyed by crop name.
  Map<String, dynamic>? get thresholds => _thresholds;

  /// Fetches the threshold table, falling back to the last successful
  /// response and finally to `null`. Never throws.
  Future<Map<String, dynamic>?> load({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh && _thresholds != null) return _thresholds;

    try {
      final res = await http
          .get(
            Uri.parse('${CropApiService.baseUrl}/monitor/config'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(_timeout);

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body is Map && body['thresholds'] is Map) {
          final fresh = Map<String, dynamic>.from(body['thresholds'] as Map);
          _thresholds = fresh;
          _loaded = true;
          unawaited(_cache(fresh));
          return fresh;
        }
      }
    } catch (_) {
      // Backend unreachable - fall through to the cache.
    }

    _thresholds ??= await _readCache();
    _loaded = true;
    return _thresholds;
  }

  /// Rules for [crop] built from the backend table.
  ///
  /// Returns an empty list when the crop is unconfigured, which makes the
  /// monitor inert rather than silently alerting against the wrong bands.
  List<AlertRule> rulesFor(String crop) {
    final table = _thresholds;
    if (table == null) return const [];

    final entry = table[crop.toLowerCase().trim()];
    if (entry is! Map) return const [];

    final rules = <AlertRule>[];
    entry.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final cfg = Map<String, dynamic>.from(value);
      if (cfg['min'] is! num || cfg['max'] is! num) return;
      rules.add(AlertRule.fromThreshold(key, cfg));
    });
    return rules;
  }

  /// Backend rules for [crop] when available, otherwise the generic
  /// [defaultAlertRules] so alerts still work on a first run with no
  /// reachable backend.
  List<AlertRule> rulesForOrFallback(String crop) {
    final rules = rulesFor(crop);
    return rules.isEmpty ? defaultAlertRules : rules;
  }

  Future<void> _cache(Map<String, dynamic> table) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(table));
    } catch (_) {
      // Cache is an optimisation; failing to write it is not fatal.
    }
  }

  Future<Map<String, dynamic>?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Corrupt or unreadable cache - treat as absent.
    }
    return null;
  }
}
