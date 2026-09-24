import 'dart:convert';
import 'package:http/http.dart' as http;

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
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return MonitoringResult.fromJson(data as Map<String, dynamic>);
    } else {
      throw Exception('Failed to fetch monitoring alerts: ${response.statusCode}');
    }
  }
}