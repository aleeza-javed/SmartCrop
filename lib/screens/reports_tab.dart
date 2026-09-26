import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';

class ReportsTab extends StatefulWidget {
  final String crop;

  const ReportsTab({
    super.key,
    this.crop = 'wheat',
  });

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  static const String _baseUrl = 'http://192.168.111.186:5000';

  bool _isExporting = false;
  bool _loading = true;

  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _current;

  int _healthScore = 0;
  String _overallStatus = 'No data';
  List<String> _alerts = [];
  List<String> _recommendations = [];

  Map<String, dynamic> _fertilizer = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void didUpdateWidget(covariant ReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.crop != widget.crop) {
      _loadReport();
    }
  }

  Future<void> _loadReport() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      await _fetchHistory();

      if (_history.isNotEmpty) {
        _current = _history.last;

        await _fetchMonitoring();
        await _fetchFertilizer();
      } else {
        _current = null;
        _healthScore = 0;
        _overallStatus = 'No data';
        _alerts = [];
        _recommendations = [];
        _fertilizer = {};
      }
    } catch (e) {
      debugPrint('Reports load error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _normalizeCrop(String crop) {
    final cleaned = crop
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');

    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  Future<void> _fetchHistory() async {
    final cropKey = _normalizeCrop(widget.crop);

    final snapshot = await FirebaseDatabase.instance
        .ref('sensor_history/$cropKey')
        .get();

    final value = snapshot.value;

    if (value is! Map) {
      _history = [];
      return;
    }

    final readings = <Map<String, dynamic>>[];

    value.forEach((dateKey, dateValue) {
      if (dateValue is! Map) return;

      dateValue.forEach((readingId, readingValue) {
        if (readingValue is! Map) return;

        final raw = Map<String, dynamic>.from(
          (readingValue as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );

        raw['timestamp'] ??= '$dateKey';
        raw['_id'] = readingId.toString();

        readings.add(raw);
      });
    });

    readings.sort((a, b) {
      final aTime = DateTime.tryParse('${a['timestamp']}');
      final bTime = DateTime.tryParse('${b['timestamp']}');

      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return -1;
      if (bTime == null) return 1;

      return aTime.compareTo(bTime);
    });

    _history = readings;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse('$value') ?? 0;
  }

  Map<String, double> _monitorPayload(Map<String, dynamic> data) {
    return {
      'N': _number(data['n'] ?? data['N']),
      'P': _number(data['p'] ?? data['P']),
      'K': _number(data['k'] ?? data['K']),
      'temperature': _number(
        data['airTemp'] ?? data['temperature'],
      ),
      'humidity': _number(
        data['airHumidity'] ?? data['humidity'],
      ),
      'ph': _number(
        data['pH'] ?? data['ph'],
      ),
      'soil_moisture': _number(
        data['soilMoisturePercent'] ??
            data['soil_moisture'] ??
            data['soilMoisture'],
      ),
    };
  }

  Future<void> _fetchMonitoring() async {
    if (_current == null) return;

    final current = _monitorPayload(_current!);

    final history = _history
        .map(_monitorPayload)
        .toList();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/monitor'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'crop': widget.crop,
          'current': current,
          'history': history,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Monitor API error: ${response.statusCode} ${response.body}',
        );
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);

      _overallStatus =
          '${data['overall_status'] ?? data['status'] ?? 'No data'}';

      _healthScore =
          (data['health_score'] as num?)?.toInt() ??
              (data['healthScore'] as num?)?.toInt() ??
              0;

      final rawAlerts = data['alerts'];

      if (rawAlerts is List) {
        _alerts = rawAlerts.map((alert) {
          if (alert is Map) {
            return '${alert['message'] ?? alert['parameter'] ?? 'Alert'}';
          }

          return '$alert';
        }).toList();
      }

      final rawPersistent = data['persistent_issues'];

      if (rawPersistent is List) {
        for (final issue in rawPersistent) {
          final text = '$issue';

          if (!_alerts.contains(text)) {
            _alerts.add(text);
          }
        }
      }

      final rawRecommendations = data['recommendations'];

      if (rawRecommendations is List) {
        _recommendations =
            rawRecommendations.map((item) => '$item').toList();
      }
    } catch (e) {
      debugPrint('Monitoring request failed: $e');
    }
  }

  Future<void> _fetchFertilizer() async {
    if (_current == null) return;

    final current = _monitorPayload(_current!);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fertilizer'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'crop': widget.crop,
          'N': current['N'],
          'P': current['P'],
          'K': current['K'],
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Fertilizer API error: ${response.statusCode} ${response.body}',
        );
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        final result = decoded['recommendations'];

        if (result is Map) {
          _fertilizer = Map<String, dynamic>.from(
            result.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        } else {
          _fertilizer = Map<String, dynamic>.from(
            decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Fertilizer request failed: $e');
    }
  }

  String _healthText() {
    if (_current == null) {
      return 'No sensor history available yet.';
    }

    final score = _healthScore.clamp(0, 100);

    if (score >= 80) {
      return 'Monitoring indicates healthy conditions for ${widget.crop}.';
    }

    if (score >= 60) {
      return 'Some soil or environmental conditions require attention.';
    }

    return 'Several monitored conditions require attention.';
  }

  double _healthProgress() {
    if (_healthScore <= 0) return 0;
    return (_healthScore.clamp(0, 100)) / 100;
  }

  String _statusText(dynamic value) {
    if (value is Map) {
      return '${value['status'] ?? 'Unknown'}';
    }

    return '$value';
  }

  String _fertilizerSummary() {
    if (_fertilizer.isEmpty) {
      return 'Fertilizer recommendations will appear when sensor data is available.';
    }

    final parts = <String>[];

    for (final entry in _fertilizer.entries) {
      if (entry.value is Map) {
        final data = Map<String, dynamic>.from(
          (entry.value as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );

        final status = data['status'];

        if (status != null) {
          parts.add('${entry.key.toUpperCase()}: $status');
        }
      }
    }

    if (parts.isEmpty) {
      return 'Fertilizer analysis available for ${widget.crop}.';
    }

    return parts.join('  •  ');
  }

  List<double> _growthValues() {
    if (_history.isEmpty) {
      return [0.45, 0.55, 0.35, 0.65, 0.8, 0.4, 0.5];
    }

    final recent = _history.length > 7
        ? _history.sublist(_history.length - 7)
        : _history;

    final values = recent.map((reading) {
      final moisture = _number(
        reading['soilMoisturePercent'] ??
            reading['soil_moisture'] ??
            reading['soilMoisture'],
      );

      if (moisture <= 0) return 0.1;

      return (moisture / 100).clamp(0.1, 1.0);
    }).toList();

    while (values.length < 7) {
      values.insert(0, 0.1);
    }

    return values.take(7).toList();
  }

  Future<void> _downloadReport(String reportName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading $reportName...'),
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$reportName.pdf';
      final file = File(filePath);

      await file.writeAsString(
        _reportText(reportName),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reportName downloaded successfully'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => _shareFile(filePath, reportName),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download: $e')),
        );
      }
    }
  }

  String _reportText(String reportName) {
    final current = _current;

    return '''
SMARTCROP REPORT

$reportName

Crop: ${widget.crop}
Generated: ${DateTime.now()}

Monitoring Status: $_overallStatus
Health Score: $_healthScore/100

Current Sensor Data:
N: ${current?['n'] ?? current?['N'] ?? 'N/A'}
P: ${current?['p'] ?? current?['P'] ?? 'N/A'}
K: ${current?['k'] ?? current?['K'] ?? 'N/A'}
Temperature: ${current?['airTemp'] ?? current?['temperature'] ?? 'N/A'}
Humidity: ${current?['airHumidity'] ?? current?['humidity'] ?? 'N/A'}
pH: ${current?['pH'] ?? current?['ph'] ?? 'N/A'}
Soil Moisture: ${current?['soilMoisturePercent'] ?? current?['soil_moisture'] ?? 'N/A'}

Alerts:
${_alerts.isEmpty ? 'No active alerts.' : _alerts.join('\n')}

Recommendations:
${_recommendations.isEmpty ? 'No recommendations available.' : _recommendations.join('\n')}
''';
  }

  Future<void> _shareFile(String filePath, String reportName) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          subject: 'SmartCrop Report: $reportName',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    }
  }

  Future<void> _exportAllReports() async {
    setState(() => _isExporting = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exporting all reports...'),
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));

      final dir = await getApplicationDocumentsDirectory();

      final timestamp = DateTime.now()
          .toString()
          .split('.')[0]
          .replaceAll(':', '-');

      final fileName = 'SmartCrop_Reports_$timestamp.zip';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      await file.writeAsString(
        '''
SMARTCROP EXPORT PACKAGE

Crop: ${widget.crop}

Health Score: $_healthScore/100
Monitoring Status: $_overallStatus

Reports:
- Field Health Report
- Irrigation Efficiency Report
- Soil Composition Analysis

Exported: ${DateTime.now()}
''',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All reports exported as $fileName'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () =>
                  _shareFile(filePath, 'SmartCrop_Reports'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    final soilMoisture = current == null
        ? 0.0
        : _number(
            current['soilMoisturePercent'] ??
                current['soil_moisture'] ??
                current['soilMoisture'],
          );

    final waterProgress =
        soilMoisture > 0 ? (soilMoisture / 100).clamp(0.0, 1.0) : 0.72;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytical Insights',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Comprehensive field reporting for Central Valley Sector 4.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Filter Buttons ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB9F474),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.onBackground,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Last 30 Days',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onBackground,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _isExporting ? null : _exportAllReports,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        _isExporting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                    Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.share,
                                size: 16,
                                color: Colors.white,
                              ),
                        const SizedBox(width: 8),
                        Text(
                          _isExporting ? 'Exporting...' : 'Export All',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Summary Cards Grid ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _YieldCard(
                        hasData: _history.isNotEmpty,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 1,
                      child: _WaterUsageCard(
                        progress: waterProgress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SoilHealthCard(
                  score: _healthScore,
                  description: _healthText(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── AI Insight Card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AiInsightCard(
              recommendation: _recommendations.isNotEmpty
                  ? _recommendations.first
                  : _fertilizerSummary(),
            ),
          ),

          const SizedBox(height: 28),

          // ── Growth Trends Section ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Growth Trends',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onBackground,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4EF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          _TrendButton('Daily', true),
                          _TrendButton('Weekly', false),
                          _TrendButton('Monthly', false),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GrowthChart(
                  values: _growthValues(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Recent Reports ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Reports',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 12),

                _ReportItem(
                  icon: Icons.description_rounded,
                  title: 'May Field Health',
                  subtitle: _history.isEmpty
                      ? 'No sensor history yet'
                      : 'Generated from sensor data',
                  iconColor: AppColors.primary,
                  onDownload: () =>
                      _downloadReport('May Field Health'),
                ),

                const SizedBox(height: 10),

                _ReportItem(
                  icon: Icons.water_drop_rounded,
                  title: 'Irrigation Efficiency',
                  subtitle: _history.isEmpty
                      ? 'Waiting for sensor data'
                      : 'Based on soil moisture',
                  iconColor: const Color(0xFF00796B),
                  onDownload: () =>
                      _downloadReport('Irrigation Efficiency'),
                ),

                const SizedBox(height: 10),

                _ReportItem(
                  icon: Icons.science_rounded,
                  title: 'Soil Composition Anal...',
                  subtitle: _history.isEmpty
                      ? 'Waiting for sensor data'
                      : 'NPK monitoring available',
                  iconColor: const Color(0xFF6A1B9A),
                  onDownload: () =>
                      _downloadReport('Soil Composition Analysis'),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(
                        color: Color(0xFFBFCABA),
                        style: BorderStyle.solid,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'View Archive',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Field Image ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuCTbSOoHDInHddXxC9ALdpAfey4AurggqzMWNi8uP7Zf00MtG3ewour08AGh9GAwTytm81yEacK8pSR3bHcIxWMC9vwMuUwzPhmWISzuM30XDsjjPGICn83_b0WeT5AzIDQ1qYlDrCYrcuvAJQ7cKVOdC7DHRKA_W7sJTSUA6Mm5bDAhFu06QMgngSbUNXj4r5qE9Fv_aCMOcE5HPpwXh4ZuuamLiDVRIvmOob25NmaogoxrvoXcJlvsz5KWeu8NF4LRqPNALY054UF',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[400],
                          child: const Center(
                            child: Icon(Icons.image_not_supported),
                          ),
                        );
                      },
                    ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SATELLITE VERIFICATION',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.7),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sector 4 Health Overview',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Yield Card ──────────────────────────────────────────────────────────────

class _YieldCard extends StatelessWidget {
  final bool hasData;

  const _YieldCard({
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ESTIMATED YIELD',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasData ? 'Data Available' : 'N/A',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onBackground,
                    ),
                  ),
                ],
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                6,
                (i) {
                  final heights = [0.4, 0.6, 0.55, 0.8, 0.7, 0.95];
                  final isLast = i == 5;

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: heights[i] * 56,
                      decoration: BoxDecoration(
                        color: isLast
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasData
                ? 'Based on available field data'
                : 'Yield prediction data not available',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Water Usage Card ────────────────────────────────────────────────────────

class _WaterUsageCard extends StatelessWidget {
  final double progress;

  const _WaterUsageCard({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WATER USAGE',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(
                    painter: CircularProgressPainter(
                      progress: progress,
                      backgroundColor: const Color(0xFFE7E9E4),
                      progressColor: const Color(0xFF00796B),
                    ),
                  ),
                ),
                Text(
                  progress == 0
                      ? '--'
                      : '${(progress * 100).round()}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Efficiency',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Monitoring',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF00796B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Soil Health Card ────────────────────────────────────────────────────────

class _SoilHealthCard extends StatelessWidget {
  final int score;
  final String description;

  const _SoilHealthCard({
    required this.score,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final displayScore = score > 0
        ? '${(score / 10).toStringAsFixed(1)}/10'
        : '--/10';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOIL HEALTH INDEX',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayScore,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: score > 0 ? (score / 100).clamp(0.0, 1.0) : 0,
              minHeight: 8,
              backgroundColor: const Color(0xFFE7E9E4),
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.secondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI Insight Card ────────────────────────────────────────────────────────

class _AiInsightCard extends StatelessWidget {
  final String recommendation;

  const _AiInsightCard({
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer,
            AppColors.secondary.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Harvest Insight',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recommendation.isEmpty
                      ? 'Monitoring insights will appear when sensor history is available.'
                      : recommendation,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Growth Chart ───────────────────────────────────────────────────────────

class _GrowthChart extends StatelessWidget {
  final List<double> values;

  const _GrowthChart({
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                7,
                (i) {
                  final height = i < values.length
                      ? values[i].clamp(0.1, 1.0)
                      : 0.1;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        height: height * 160,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][i],
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF707A6C),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Report Item ─────────────────────────────────────────────────────────────

class _ReportItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onDownload;

  const _ReportItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFBFCABA),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: const Color(0xFF707A6C),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDownload,
            child: const Icon(
              Icons.download_rounded,
              color: Color(0xFF707A6C),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trend Button ───────────────────────────────────────────────────────────

class _TrendButton extends StatelessWidget {
  final String label;
  final bool isActive;

  const _TrendButton(
    this.label,
    this.isActive,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive
              ? AppColors.primary
              : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─── Circular Progress Painter ──────────────────────────────────────────────

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius = size.width / 2;
    const strokeWidth = 8.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = backgroundColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      -90 * 3.14159 / 180,
      progress * 360 * 3.14159 / 180,
      false,
      Paint()
        ..color = progressColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(
    CircularProgressPainter oldDelegate,
  ) =>
      oldDelegate.progress != progress;
}