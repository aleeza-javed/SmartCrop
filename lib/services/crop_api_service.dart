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

class FertilizerRecommendation {
  final String status;
  final double current;
  final List<double> optimalRange;
  final String advice;
  final double? deficit;
  final double? surplus;

  const FertilizerRecommendation({
    required this.status,
    required this.current,
    required this.optimalRange,
    required this.advice,
    this.deficit,
    this.surplus,
  });

  factory FertilizerRecommendation.fromJson(Map<String, dynamic> json) {
    return FertilizerRecommendation(
      status: json['status'] as String? ?? '',
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      optimalRange: (json['optimal_range'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      advice: json['advice'] as String? ?? '',
      deficit: (json['deficit'] as num?)?.toDouble(),
      surplus: (json['surplus'] as num?)?.toDouble(),
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

  static Future<Map<String, FertilizerRecommendation>> getFertilizerRecommendations({
    required String crop,
    required double n,
    required double p,
    required double k,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fertilizer'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'crop': crop,
        'N': n,
        'P': p,
        'K': k,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final recs = data['recommendations'] as Map<String, dynamic>? ?? {};
      return {
        for (final entry in recs.entries)
          entry.key: FertilizerRecommendation.fromJson(entry.value as Map<String, dynamic>)
      };
    } else {
      throw Exception('Failed to fetch fertilizer recommendations: ${response.statusCode}');
    }
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