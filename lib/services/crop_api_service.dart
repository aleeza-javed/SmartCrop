import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Thrown when the SmartCrop backend answers with a non-200 status.
/// Carries the server-provided `error` message when there is one.
class CropApiException implements Exception {
  final String message;
  final int? statusCode;

  const CropApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class CropPrediction {
  final String name;
  final double confidence;

  const CropPrediction({required this.name, required this.confidence});

  factory CropPrediction.fromJson(Map<String, dynamic> json) {
    return CropPrediction(
      name: json['crop'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Severity vocabulary shared with the monitoring engine, so the Fertilizer
/// Advisor cannot disagree with the Sensors tab or a notification rule.
enum FertilizerStatus {
  normal,
  warning,
  critical,
  noReading,

  /// A status this client does not know about. Treated as "not actionable"
  /// rather than crashing or guessing, so a newer backend degrades quietly.
  unknown;

  static FertilizerStatus parse(String? raw) {
    switch (raw) {
      case 'NORMAL':
        return FertilizerStatus.normal;
      case 'WARNING':
        return FertilizerStatus.warning;
      case 'CRITICAL':
        return FertilizerStatus.critical;
      case 'NO_READING':
        return FertilizerStatus.noReading;
      default:
        return FertilizerStatus.unknown;
    }
  }
}

/// A fertilizer product class for a confirmed deficiency.
class FertilizerProduct {
  final String? fertilizer;
  final String? name;
  final String? role;
  final double? nutrientFraction;

  const FertilizerProduct({
    this.fertilizer,
    this.name,
    this.role,
    this.nutrientFraction,
  });

  factory FertilizerProduct.fromJson(Map<String, dynamic> json) {
    return FertilizerProduct(
      fertilizer: json['fertilizer'] as String?,
      name: json['name'] as String?,
      role: json['role'] as String?,
      nutrientFraction: (json['nutrient_fraction'] as num?)?.toDouble(),
    );
  }
}

/// Per-nutrient advice from `POST /fertilizer`.
///
/// Every field except [status] and [advice] is nullable by design: a nutrient
/// with no reading has no `current`, no `gap` and no `required` answer, and
/// that is different from `required: false`.
class FertilizerRecommendation {
  final String parameter;
  final String label;
  final String unit;
  final List<double> band;
  final double? buffer;
  final double? current;
  final FertilizerStatus status;

  /// null only when [status] is [FertilizerStatus.noReading] - "we do not know"
  /// is not the same answer as "not required".
  final bool? required;
  final String? direction;
  final double? gap;

  /// Estimated nutrient mass to close the gap, kg/ha. Rule of thumb only.
  final double? nutrientKgHa;

  /// Estimated product mass to close the gap, kg/ha. Rule of thumb only.
  final double? productKgHa;
  final FertilizerProduct? product;
  final String advice;

  /// `instant` or `persistent`.
  final String confidence;

  /// The monitoring engine's persistence level, or `unavailable` when the
  /// client could not supply enough history to judge it.
  final String persistence;

  const FertilizerRecommendation({
    required this.parameter,
    required this.label,
    required this.unit,
    required this.band,
    this.buffer,
    this.current,
    required this.status,
    this.required,
    this.direction,
    this.gap,
    this.nutrientKgHa,
    this.productKgHa,
    this.product,
    required this.advice,
    required this.confidence,
    required this.persistence,
  });

  factory FertilizerRecommendation.fromJson(
    String parameter,
    Map<String, dynamic> json,
  ) {
    final rawProduct = json['product'];
    return FertilizerRecommendation(
      parameter: json['parameter'] as String? ?? parameter,
      label: json['label'] as String? ?? parameter,
      unit: json['unit'] as String? ?? '',
      band: (json['band'] as List<dynamic>?)
              ?.map((e) => (e as num?)?.toDouble() ?? 0)
              .toList() ??
          const [],
      buffer: (json['buffer'] as num?)?.toDouble(),
      current: (json['current'] as num?)?.toDouble(),
      status: FertilizerStatus.parse(json['status'] as String?),
      required: json['required'] as bool?,
      direction: json['direction'] as String?,
      gap: (json['gap'] as num?)?.toDouble(),
      nutrientKgHa: (json['nutrient_kg_ha'] as num?)?.toDouble(),
      productKgHa: (json['product_kg_ha'] as num?)?.toDouble(),
      product: rawProduct is Map
          ? FertilizerProduct.fromJson(Map<String, dynamic>.from(rawProduct))
          : null,
      advice: json['advice'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'instant',
      persistence: json['persistence'] as String? ?? 'unavailable',
    );
  }

  bool get isNoReading => status == FertilizerStatus.noReading;
  bool get isDeficient => direction == 'deficient';
  bool get isExcess => direction == 'excess';
  bool get isWithinRange => status == FertilizerStatus.normal;
  bool get needsAction => required ?? false;

  /// True when the backend had enough history to judge persistence. When false
  /// the UI must not present confidence as anything but an instantaneous read.
  bool get confidenceKnown => persistence != 'unavailable';

  /// An amount is only ever offered for a confirmed deficiency.
  bool get hasEstimate => isDeficient && productKgHa != null && product != null;
}

class FertilizerHealth {
  final int score;
  final int scoreOutOf;
  final String status;

  /// True when some nutrient had no reading, so the score covers fewer than
  /// all three nutrients and is not comparable to a full evaluation.
  final bool partial;
  final List<String> evaluated;
  final String label;
  final String note;

  const FertilizerHealth({
    required this.score,
    required this.scoreOutOf,
    required this.status,
    required this.partial,
    required this.evaluated,
    required this.label,
    required this.note,
  });

  factory FertilizerHealth.fromJson(Map<String, dynamic> json) {
    return FertilizerHealth(
      score: (json['score'] as num?)?.toInt() ?? 0,
      scoreOutOf: (json['score_out_of'] as num?)?.toInt() ?? 100,
      status: json['status'] as String? ?? 'NO_READING',
      partial: json['partial'] as bool? ?? false,
      evaluated: (json['evaluated'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      label: json['label'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  /// 0..1 for a progress bar, clamped so a malformed score cannot overflow.
  double get fraction {
    if (scoreOutOf <= 0) return 0;
    final raw = score / scoreOutOf;
    if (raw.isNaN) return 0;
    return raw.clamp(0.0, 1.0);
  }
}

class FertilizerSummary {
  final int requiredCount;
  final List<String> withinRange;

  /// Nutrients with no usable reading. These are never counted as required.
  final List<String> noReading;

  const FertilizerSummary({
    required this.requiredCount,
    required this.withinRange,
    required this.noReading,
  });

  factory FertilizerSummary.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>?)?.map((e) => e as String).toList() ??
        const [];
    return FertilizerSummary(
      requiredCount: (json['required_count'] as num?)?.toInt() ?? 0,
      withinRange: strings('within_range'),
      noReading: strings('no_reading'),
    );
  }
}

/// The whole `POST /fertilizer` response.
class FertilizerReport {
  final String crop;
  final bool stale;
  final double? readingAgeSeconds;
  final int staleAfterSeconds;
  final FertilizerHealth health;
  final FertilizerSummary summary;

  /// Keyed by nutrient symbol.
  final Map<String, FertilizerRecommendation> nutrients;

  /// N, P, K in server order, so the UI renders them consistently.
  final List<String> order;

  const FertilizerReport({
    required this.crop,
    required this.stale,
    required this.readingAgeSeconds,
    required this.staleAfterSeconds,
    required this.health,
    required this.summary,
    required this.nutrients,
    required this.order,
  });

  factory FertilizerReport.fromJson(Map<String, dynamic> json) {
    final rawNutrients = json['nutrients'];
    final nutrients = <String, FertilizerRecommendation>{};
    if (rawNutrients is Map) {
      rawNutrients.forEach((key, value) {
        if (value is! Map) return;
        nutrients['$key'] = FertilizerRecommendation.fromJson(
          '$key',
          Map<String, dynamic>.from(value),
        );
      });
    }

    // Prefer the server's order, then top up with any remaining keys.
    const preferred = ['N', 'P', 'K'];
    final order = <String>[
      for (final key in preferred)
        if (nutrients.containsKey(key)) key,
      ...nutrients.keys.where((k) => !preferred.contains(k)),
    ];

    return FertilizerReport(
      crop: json['crop'] as String? ?? '',
      stale: json['stale'] as bool? ?? false,
      readingAgeSeconds: (json['reading_age_seconds'] as num?)?.toDouble(),
      staleAfterSeconds: (json['stale_after_seconds'] as num?)?.toInt() ?? 0,
      health: json['health'] is Map
          ? FertilizerHealth.fromJson(
              Map<String, dynamic>.from(json['health'] as Map))
          : const FertilizerHealth(
              score: 0,
              scoreOutOf: 100,
              status: 'NO_READING',
              partial: true,
              evaluated: [],
              label: '',
              note: '',
            ),
      summary: json['summary'] is Map
          ? FertilizerSummary.fromJson(
              Map<String, dynamic>.from(json['summary'] as Map))
          : const FertilizerSummary(
              requiredCount: 0,
              withinRange: [],
              noReading: [],
            ),
      nutrients: nutrients,
      order: order,
    );
  }
}

class MonitoringAlert {
  final String severity;
  final String parameter;
  final String type;
  final String message;

  const MonitoringAlert({
    required this.severity,
    required this.parameter,
    required this.type,
    required this.message,
  });

  factory MonitoringAlert.fromJson(Map<String, dynamic> json) {
    return MonitoringAlert(
      severity: json['severity'] as String? ?? '',
      parameter: json['parameter'] as String? ?? '',
      type: json['type'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

class MonitoringResult {
  final String overallStatus;
  final int healthScore;
  final List<String> persistentIssues;
  final List<MonitoringAlert> alerts;
  final List<String> recommendations;
  final Map<String, dynamic> parameterResults;

  const MonitoringResult({
    required this.overallStatus,
    required this.healthScore,
    required this.persistentIssues,
    required this.alerts,
    required this.recommendations,
    required this.parameterResults,
  });

  factory MonitoringResult.fromJson(Map<String, dynamic> json) {
    return MonitoringResult(
      overallStatus: json['overall_status'] as String? ?? '',
      healthScore: (json['health_score'] as num?)?.toInt() ?? 0,
      persistentIssues: (json['persistent_issues'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      alerts: (json['alerts'] as List<dynamic>?)
              ?.map((e) => MonitoringAlert.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      parameterResults: json['parameter_results'] as Map<String, dynamic>? ?? {},
    );
  }
}

class CropApiService {
  // Android emulator: http://10.0.2.2:5000
  // iOS simulator / real device: use your Mac's IP
  static const baseUrl = 'http://192.168.18.84:5000';

  static Future<List<CropPrediction>> predictCrops({
    required double nitrogen,
    required double phosphorus,
    required double potassium,
    required double temperature,
    required double humidity,
    required double ph,
    required double rainfall,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/predict'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'N': nitrogen,
        'P': phosphorus,
        'K': potassium,
        'temperature': temperature,
        'humidity': humidity,
        'ph': ph,
        'rainfall': rainfall,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final crops = data['recommended_crops'] as List<dynamic>? ?? [];
      return crops
          .map((e) => CropPrediction.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to predict crops: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> features() async {
    final response = await http.get(
      Uri.parse('$baseUrl/features'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch features: ${response.statusCode}');
    }
  }

  /// Rule-based fertilizer advice for the current N/P/K readings.
  ///
  /// [current] carries the full monitored parameter set so the backend can judge
  /// whether an off-range reading has *persisted*; without it the backend
  /// answers `persistence: "unavailable"` and the advice is instantaneous only.
  /// [history] is the archived readings, oldest first, in the backend's
  /// `toMonitorPayload()` shape. [readingAt] is when the client observed the
  /// reading, used only to compute the staleness flag.
  static Future<FertilizerReport> getFertilizerReport({
    required String crop,
    required Map<String, double> npk,
    Map<String, double>? current,
    List<Map<String, dynamic>>? history,
    DateTime? readingAt,
  }) async {
    final body = <String, dynamic>{
      'crop': crop,
      ...npk,
      if (current != null && current.isNotEmpty) 'current': current,
      if (history != null && history.isNotEmpty) 'history': history,
      if (readingAt != null) 'timestamp': readingAt.toUtc().toIso8601String(),
    };

    final response = await http.post(
      Uri.parse('$baseUrl/fertilizer'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        throw const CropApiException('Malformed fertilizer response.');
      }
      return FertilizerReport.fromJson(Map<String, dynamic>.from(decoded));
    }

    String message = 'Fertilizer advice unavailable (server ${response.statusCode}).';
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {
      // Keep the generic message; the body was not JSON.
    }
    throw CropApiException(message, statusCode: response.statusCode);
  }

  static Future<MonitoringResult> getMonitoringAlerts({
    required String crop,
    required Map<String, double> current,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/monitor'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'crop': crop,
        'current': current,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return MonitoringResult.fromJson(data as Map<String, dynamic>);
    } else {
      throw Exception('Monitoring alerts unavailable (server ${response.statusCode}).');
    }
  }

  static Future<WaterReport> getWaterReport({
    required String crop,
    required List<Map<String, dynamic>> history,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports/water'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'crop': crop, 'history': history}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return WaterReport.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Water report unavailable (server ${response.statusCode}).');
  }

  static Future<NutrientReport> getNutrientReport({
    required String crop,
    required List<Map<String, dynamic>> history,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports/nutrients'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'crop': crop, 'history': history}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return NutrientReport.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Nutrient report unavailable (server ${response.statusCode}).');
  }

  static Future<MonthlyHealthReport> getMonthlyHealthReport({
    required String crop,
    required List<Map<String, dynamic>> history,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports/monthly-health'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'crop': crop, 'history': history}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return MonthlyHealthReport.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Monthly health unavailable (server ${response.statusCode}).');
  }

  static Future<SoilHealthReport> getSoilHealthReport({
    required String crop,
    required List<Map<String, dynamic>> history,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports/soil-health'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'crop': crop, 'history': history}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return SoilHealthReport.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Soil health unavailable (server ${response.statusCode}).');
  }
}

// ── Report Models ──────────────────────────────────────────────────────

class WaterReport {
  final String crop;
  final String parameter;
  final String status;
  final double currentValue;
  final List<double> recommendedRange;
  final String unit;
  final Map<String, dynamic> statistics;
  final Map<String, int> statusBreakdown;
  final String trend;
  final List<Map<String, dynamic>> warnings;
  final String note;

  const WaterReport({
    required this.crop,
    required this.parameter,
    required this.status,
    required this.currentValue,
    required this.recommendedRange,
    required this.unit,
    required this.statistics,
    required this.statusBreakdown,
    required this.trend,
    required this.warnings,
    required this.note,
  });

  factory WaterReport.fromJson(Map<String, dynamic> json) {
    return WaterReport(
      crop: json['crop'] as String? ?? '',
      parameter: json['parameter'] as String? ?? '',
      status: json['status'] as String? ?? '',
      currentValue: (json['current_value'] as num?)?.toDouble() ?? 0,
      recommendedRange:
          (json['recommended_range'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      unit: json['unit'] as String? ?? '',
      statistics: json['statistics'] as Map<String, dynamic>? ?? {},
      statusBreakdown: json['status_breakdown'] as Map<String, int>? ?? {},
      trend: json['trend'] as String? ?? '',
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      note: json['note'] as String? ?? '',
    );
  }
}

class NutrientReport {
  final String crop;
  final String status;
  final int healthScore;
  final Map<String, dynamic> nutrients;
  final String? latestReadingTimestamp;

  const NutrientReport({
    required this.crop,
    required this.status,
    required this.healthScore,
    required this.nutrients,
    required this.latestReadingTimestamp,
  });

  factory NutrientReport.fromJson(Map<String, dynamic> json) {
    return NutrientReport(
      crop: json['crop'] as String? ?? '',
      status: json['status'] as String? ?? '',
      healthScore: (json['health_score'] as num?)?.toInt() ?? 0,
      nutrients: json['nutrients'] as Map<String, dynamic>? ?? {},
      latestReadingTimestamp: json['latest_reading_timestamp'] as String?,
    );
  }
}

class MonthlyHealthReport {
  final String crop;
  final List<Map<String, dynamic>> months;
  final int totalReadings;

  const MonthlyHealthReport({
    required this.crop,
    required this.months,
    required this.totalReadings,
  });

  factory MonthlyHealthReport.fromJson(Map<String, dynamic> json) {
    return MonthlyHealthReport(
      crop: json['crop'] as String? ?? '',
      months: (json['months'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      totalReadings: (json['total_readings'] as num?)?.toInt() ?? 0,
    );
  }
}

class SoilHealthReport {
  final String crop;
  final double soilHealthIndex;
  final String overallStatus;
  final int scoreOutOf;
  final Map<String, dynamic> components;
  final List<Map<String, dynamic>> warnings;
  final String? latestReadingTimestamp;

  const SoilHealthReport({
    required this.crop,
    required this.soilHealthIndex,
    required this.overallStatus,
    required this.scoreOutOf,
    required this.components,
    required this.warnings,
    required this.latestReadingTimestamp,
  });

  factory SoilHealthReport.fromJson(Map<String, dynamic> json) {
    return SoilHealthReport(
      crop: json['crop'] as String? ?? '',
      soilHealthIndex: (json['soil_health_index'] as num?)?.toDouble() ?? 0,
      overallStatus: json['overall_status'] as String? ?? '',
      scoreOutOf: (json['score_out_of'] as num?)?.toInt() ?? 0,
      components: json['components'] as Map<String, dynamic>? ?? {},
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      latestReadingTimestamp: json['latest_reading_timestamp'] as String?,
    );
  }
}