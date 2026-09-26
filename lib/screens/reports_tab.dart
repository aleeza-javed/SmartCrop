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

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> _current = {};

  Map<String, dynamic> _monitorConfig = {};
  Map<String, dynamic> _monitorResult = {};
  Map<String, dynamic> _fertilizerResult = {};

  List<Map<String, dynamic>> _monthlyHealth = [];

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

  Future<void> _loadReport({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final history = await _fetchHistory(widget.crop);

      if (history.isEmpty) {
        if (mounted) {
          setState(() {
            _history = [];
            _current = {};
            _monitorConfig = {};
            _monitorResult = {};
            _fertilizerResult = {};
            _monthlyHealth = [];
            _loading = false;
            _refreshing = false;
          });
        }
        return;
      }

      final current = history.last;

      final config = await _fetchMonitorConfig();

      Map<String, dynamic> monitor = {};
      Map<String, dynamic> fertilizer = {};

      try {
        monitor = await _fetchMonitoring(
          crop: widget.crop,
          current: current,
          history: history,
        );
      } catch (_) {
        monitor = {};
      }

      try {
        fertilizer = await _fetchFertilizer(
          crop: widget.crop,
          current: current,
        );
      } catch (_) {
        fertilizer = {};
      }

      final monthly = await _calculateMonthlyHealth(
        history,
      );

      if (!mounted) return;

      setState(() {
        _history = history;
        _current = current;
        _monitorConfig = config;
        _monitorResult = monitor;
        _fertilizerResult = fertilizer;
        _monthlyHealth = monthly;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHistory(String crop) async {
    final ref = FirebaseDatabase.instance
        .ref('sensor_history')
        .child(_normalizeCrop(crop));

    final snapshot = await ref.get();

    if (!snapshot.exists || snapshot.value == null) {
      return [];
    }

    final value = snapshot.value;

    if (value is! Map) {
      return [];
    }

    final readings = <Map<String, dynamic>>[];

    value.forEach((dateKey, dateValue) {
      if (dateValue is! Map) return;

      dateValue.forEach((readingId, readingValue) {
        if (readingValue is! Map) return;

        final map = <String, dynamic>{};

        readingValue.forEach((key, value) {
          map[key.toString()] = value;
        });

        map['dateKey'] = dateKey.toString();
        map['readingId'] = readingId.toString();

        final timestamp = map['timestamp'];

        DateTime? recordedAt;

        if (timestamp is String) {
          recordedAt = DateTime.tryParse(timestamp);
        }

        recordedAt ??= DateTime.tryParse(dateKey.toString());

        map['recordedAt'] =
            recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        readings.add(map);
      });
    });

    readings.sort(
      (a, b) => (a['recordedAt'] as DateTime)
          .compareTo(b['recordedAt'] as DateTime),
    );

    return readings;
  }

  Future<Map<String, dynamic>> _fetchMonitorConfig() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/monitor/config'),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to load monitoring configuration.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {};
  }

  Future<Map<String, dynamic>> _fetchMonitoring({
    required String crop,
    required Map<String, dynamic> current,
    required List<Map<String, dynamic>> history,
  }) async {
    final currentPayload = _monitorPayload(current);

    final historyPayload = history.map(_monitorPayload).toList();

    final response = await http.post(
      Uri.parse('$_baseUrl/monitor'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'crop': crop,
        'current': currentPayload,
        'history': historyPayload,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Monitoring service returned ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {};
  }

  Future<Map<String, dynamic>> _fetchFertilizer({
    required String crop,
    required Map<String, dynamic> current,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/fertilizer'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'crop': crop,
        'N': _number(current['N']),
        'P': _number(current['P']),
        'K': _number(current['K']),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Fertilizer service returned ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {};
  }

  Future<List<Map<String, dynamic>>> _calculateMonthlyHealth(
    List<Map<String, dynamic>> history,
  ) async {
    if (history.isEmpty) return [];

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final reading in history) {
      final date = reading['recordedAt'] as DateTime;

      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';

      grouped.putIfAbsent(key, () => []).add(reading);
    }

    final result = <Map<String, dynamic>>[];

    for (final entry in grouped.entries) {
      final readings = entry.value;

      // Use up to 5 representative readings for the month.
      final selected = _sampleReadings(readings, 5);

      final scores = <double>[];

      for (final reading in selected) {
        try {
          final monitor = await _fetchMonitoring(
            crop: widget.crop,
            current: reading,
            history: readings,
          );

          final score = _number(monitor['health_score']);

          if (score > 0 || monitor.containsKey('health_score')) {
            scores.add(score);
          }
        } catch (_) {
          // Keep going if one historical reading cannot be evaluated.
        }
      }

      if (scores.isEmpty) continue;

      final average =
          scores.reduce((a, b) => a + b) / scores.length;

      result.add({
        'month': entry.key,
        'score': average,
        'count': readings.length,
      });
    }

    result.sort(
      (a, b) =>
          (a['month'] as String).compareTo(b['month'] as String),
    );

    return result;
  }

  List<Map<String, dynamic>> _sampleReadings(
    List<Map<String, dynamic>> readings,
    int maximum,
  ) {
    if (readings.length <= maximum) {
      return readings;
    }

    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < maximum; i++) {
      final index =
          ((readings.length - 1) * i / (maximum - 1)).round();

      result.add(readings[index]);
    }

    return result;
  }

  Map<String, dynamic> _monitorPayload(
    Map<String, dynamic> reading,
  ) {
    return {
      'N': _number(reading['N']),
      'P': _number(reading['P']),
      'K': _number(reading['K']),
      'temperature': _number(
        reading['temperature'] ?? reading['airTemp'],
      ),
      'humidity': _number(
        reading['humidity'] ?? reading['airHumidity'],
      ),
      'ph': _number(
        reading['ph'] ?? reading['pH'],
      ),
      'soil_moisture': _number(
        reading['soil_moisture'] ??
            reading['soilMoisturePercent'] ??
            reading['soil_moisture_percent'],
      ),
    };
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }

  String _normalizeCrop(String crop) {
    final cleaned = crop
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');

    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  double get _healthScore {
    return _number(_monitorResult['health_score']);
  }

  List<dynamic> get _alerts {
    final value = _monitorResult['alerts'];

    if (value is List) return value;

    return [];
  }

  List<dynamic> get _recommendations {
    final value = _monitorResult['recommendations'];

    if (value is List) return value;

    return [];
  }

  Map<String, dynamic> get _fertilizerRecommendations {
    final value = _fertilizerResult['recommendations'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  double _value(String key) {
    return _number(
      _current[key] ??
          _current[_alternativeKey(key)],
    );
  }

  String _alternativeKey(String key) {
    switch (key) {
      case 'N':
        return 'nitrogen';
      case 'P':
        return 'phosphorus';
      case 'K':
        return 'potassium';
      case 'temperature':
        return 'airTemp';
      case 'humidity':
        return 'airHumidity';
      case 'ph':
        return 'pH';
      case 'soil_moisture':
        return 'soilMoisturePercent';
      default:
        return key;
    }
  }

  String _statusFor(String nutrient) {
    final recommendation =
        _fertilizerRecommendations[nutrient];

    if (recommendation is Map) {
      return recommendation['status']?.toString() ?? 'unknown';
    }

    return 'unknown';
  }

  List<double> _optimalRangeFor(String nutrient) {
    final recommendation =
        _fertilizerRecommendations[nutrient];

    if (recommendation is Map) {
      final value = recommendation['optimal_range'];

      if (value is List) {
        return value
            .map((e) => _number(e))
            .toList();
      }
    }

    return [];
  }

  String _adviceFor(String nutrient) {
    final recommendation =
        _fertilizerRecommendations[nutrient];

    if (recommendation is Map) {
      return recommendation['advice']?.toString() ?? '';
    }

    return '';
  }

  String _monthName(String key) {
    final parts = key.split('-');

    if (parts.length != 2) return key;

    final month = int.tryParse(parts[1]);

    const names = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (month == null || month < 1 || month > 12) {
      return key;
    }

    return '${names[month]} ${parts[0]}';
  }

  String _prettyStatus(String status) {
    if (status.isEmpty) return 'Unknown';

    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'sufficient':
      case 'normal':
      case 'healthy':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'deficient':
      case 'critical':
      case 'excess':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _exportSummary() async {
    if (_current.isEmpty) return;

    final buffer = StringBuffer();

    buffer.writeln('SMARTCROP REPORT');
    buffer.writeln('================');
    buffer.writeln();
    buffer.writeln('Crop: ${widget.crop}');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln();

    buffer.writeln('CURRENT SENSOR VALUES');
    buffer.writeln('---------------------');
    buffer.writeln('Nitrogen (N): ${_value('N')}');
    buffer.writeln('Phosphorus (P): ${_value('P')}');
    buffer.writeln('Potassium (K): ${_value('K')}');
    buffer.writeln('Temperature: ${_value('temperature')} °C');
    buffer.writeln('Humidity: ${_value('humidity')} %');
    buffer.writeln('pH: ${_value('ph')}');
    buffer.writeln(
      'Soil Moisture: ${_value('soil_moisture')} %',
    );
    buffer.writeln();

    buffer.writeln('MONITORING');
    buffer.writeln('----------');
    buffer.writeln(
      'Health Score: ${_healthScore.toStringAsFixed(1)}/100',
    );
    buffer.writeln(
      'Overall Status: ${_prettyStatus(
        _monitorResult['overall_status']?.toString() ?? '',
      )}',
    );
    buffer.writeln();

    if (_alerts.isNotEmpty) {
      buffer.writeln('ACTIVE ALERTS');
      buffer.writeln('-------------');

      for (final alert in _alerts) {
        if (alert is Map) {
          buffer.writeln(
            '- ${alert['severity']}: ${alert['message']}',
          );
        }
      }

      buffer.writeln();
    }

    if (_recommendations.isNotEmpty) {
      buffer.writeln('RECOMMENDATIONS');
      buffer.writeln('---------------');

      for (final recommendation in _recommendations) {
        buffer.writeln('- $recommendation');
      }

      buffer.writeln();
    }

    if (_fertilizerRecommendations.isNotEmpty) {
      buffer.writeln('FERTILIZER STATUS');
      buffer.writeln('-----------------');

      for (final entry in _fertilizerRecommendations.entries) {
        if (entry.value is Map) {
          final data =
              Map<String, dynamic>.from(entry.value as Map);

          buffer.writeln(
            '${entry.key}: ${data['status']}',
          );

          if (data['advice'] != null) {
            buffer.writeln(
              'Advice: ${data['advice']}',
            );
          }
        }
      }
    }

    final directory = await getTemporaryDirectory();

    final file = File(
      '${directory.path}/smartcrop_${_normalizeCrop(widget.crop)}_report.txt',
    );

    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'SmartCrop ${widget.crop} report',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_history.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadReport(refresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(),
          ),

          SliverToBoxAdapter(
            child: _buildCurrentOverview(),
          ),

          SliverToBoxAdapter(
            child: _buildSoilNutrients(),
          ),

          SliverToBoxAdapter(
            child: _buildEnvironmentalSummary(),
          ),

          SliverToBoxAdapter(
            child: _buildHealthScore(),
          ),

          SliverToBoxAdapter(
            child: _buildMonthlyHealth(),
          ),

          SliverToBoxAdapter(
            child: _buildAlerts(),
          ),

          SliverToBoxAdapter(
            child: _buildFertilizerRecommendations(),
          ),

          SliverToBoxAdapter(
            child: _buildWaterUsage(),
          ),

          SliverToBoxAdapter(
            child: _buildBackendRecommendations(),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytical Insights',
                  style: GoogleFonts.poppins(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Real-time report for ${_prettyCrop(widget.crop)}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _refreshing ? null : () => _loadReport(refresh: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _exportSummary,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOverview() {
    return _sectionCard(
      title: 'Current Field Overview',
      icon: Icons.eco_outlined,
      child: Row(
        children: [
          Expanded(
            child: _metric(
              'Temperature',
              '${_value('temperature').toStringAsFixed(1)} °C',
              Icons.thermostat_outlined,
            ),
          ),
          Expanded(
            child: _metric(
              'Humidity',
              '${_value('humidity').toStringAsFixed(1)} %',
              Icons.water_drop_outlined,
            ),
          ),
          Expanded(
            child: _metric(
              'Soil Moisture',
              '${_value('soil_moisture').toStringAsFixed(1)} %',
              Icons.grass_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoilNutrients() {
    return _sectionCard(
      title: 'Soil Nutrients Health',
      icon: Icons.science_outlined,
      child: Column(
        children: [
          _nutrientRow('Nitrogen (N)', 'N'),
          const Divider(height: 20),
          _nutrientRow('Phosphorus (P)', 'P'),
          const Divider(height: 20),
          _nutrientRow('Potassium (K)', 'K'),
        ],
      ),
    );
  }

  Widget _nutrientRow(
    String label,
    String nutrient,
  ) {
    final value = _value(nutrient);
    final status = _statusFor(nutrient);
    final range = _optimalRangeFor(nutrient);

    String rangeText = 'No range available';

    if (range.length >= 2) {
      rangeText =
          '${range[0].toStringAsFixed(1)} – ${range[1].toStringAsFixed(1)}';
    }

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _statusColor(status).withOpacity(.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.science_outlined,
            color: _statusColor(status),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Current: ${value.toStringAsFixed(1)}  •  Optimal: $rangeText',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        _statusBadge(status),
      ],
    );
  }

  Widget _buildEnvironmentalSummary() {
    final status =
        _monitorResult['overall_status']?.toString() ?? '';

    return _sectionCard(
      title: 'Environmental Summary',
      icon: Icons.public_outlined,
      child: Column(
        children: [
          _environmentRow(
            'Temperature',
            '${_value('temperature').toStringAsFixed(1)} °C',
            Icons.thermostat_outlined,
          ),
          _environmentRow(
            'Humidity',
            '${_value('humidity').toStringAsFixed(1)} %',
            Icons.water_drop_outlined,
          ),
          _environmentRow(
            'Soil pH',
            _value('ph').toStringAsFixed(2),
            Icons.science_outlined,
          ),
          _environmentRow(
            'Soil Moisture',
            '${_value('soil_moisture').toStringAsFixed(1)} %',
            Icons.grass_outlined,
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(status),
            ),
          ],
        ],
      ),
    );
  }

  Widget _environmentRow(
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            icon,
            size: 21,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthScore() {
    final score = _healthScore.clamp(0, 100);

    final status =
        _monitorResult['overall_status']?.toString() ?? '';

    return _sectionCard(
      title: 'Soil Health Index',
      icon: Icons.monitor_heart_outlined,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 9,
                  backgroundColor: Colors.grey.shade200,
                ),
                Text(
                  '${score.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monitoring Health Score',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  status.isEmpty
                      ? 'No overall status available.'
                      : 'Overall status: ${_prettyStatus(status)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Prototype decision-support metric generated by the SmartCrop monitoring backend.',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyHealth() {
    if (_monthlyHealth.isEmpty) {
      return _sectionCard(
        title: 'Crop Monthly Health',
        icon: Icons.show_chart,
        child: _emptyInline(
          'Monthly health data will appear after enough historical readings are available.',
        ),
      );
    }

    return _sectionCard(
      title: 'Crop Monthly Health',
      icon: Icons.show_chart,
      child: Column(
        children: [
          ..._monthlyHealth.map(
            (month) {
              final score = _number(month['score']);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 95,
                      child: Text(
                        _monthName(
                          month['month'].toString(),
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: (score / 100).clamp(0, 1),
                          minHeight: 9,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 45,
                      child: Text(
                        score.toStringAsFixed(0),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_monthlyHealth.length >= 2) ...[
            const Divider(height: 22),
            _buildMonthlyComparison(),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyComparison() {
    final previous =
        _number(_monthlyHealth[_monthlyHealth.length - 2]['score']);

    final current =
        _number(_monthlyHealth[_monthlyHealth.length - 1]['score']);

    final difference = current - previous;

    return Row(
      children: [
        Icon(
          difference >= 0
              ? Icons.trending_up
              : Icons.trending_down,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)} points compared with the previous available month.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlerts() {
    if (_alerts.isEmpty) {
      return _sectionCard(
        title: 'Active Alerts',
        icon: Icons.notifications_none,
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No active monitoring alerts for the current crop.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _sectionCard(
      title: 'Active Alerts',
      icon: Icons.notifications_active_outlined,
      child: Column(
        children: _alerts.map(
          (alert) {
            if (alert is! Map) {
              return const SizedBox.shrink();
            }

            final severity =
                alert['severity']?.toString() ?? 'warning';

            final message =
                alert['message']?.toString() ??
                    'Monitoring alert detected.';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    _statusColor(severity).withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: _statusColor(severity),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  Widget _buildFertilizerRecommendations() {
    if (_fertilizerRecommendations.isEmpty) {
      return _sectionCard(
        title: 'Fertilizer Recommendations',
        icon: Icons.local_florist_outlined,
        child: _emptyInline(
          'Fertilizer recommendations are unavailable for this crop.',
        ),
      );
    }

    return _sectionCard(
      title: 'Fertilizer Recommendations',
      icon: Icons.local_florist_outlined,
      child: Column(
        children: _fertilizerRecommendations.entries.map(
          (entry) {
            final nutrient = entry.key;

            final data = entry.value is Map
                ? Map<String, dynamic>.from(
                    entry.value as Map,
                  )
                : <String, dynamic>{};

            final status =
                data['status']?.toString() ?? 'unknown';

            final advice =
                data['advice']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade200,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nutrient,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _statusBadge(status),
                    ],
                  ),
                  if (advice.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      advice,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  Widget _buildWaterUsage() {
    return _sectionCard(
      title: 'Water Usage',
      icon: Icons.water_outlined,
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Water usage analytics are pending because the irrigation module is not yet connected to the reporting system.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendRecommendations() {
    if (_recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: 'SmartCrop Recommendations',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _recommendations.map(
          (recommendation) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recommendation.toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  Widget _metric(
    String title,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: AppColors.primary,
          size: 23,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 9,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _prettyStatus(status),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _emptyInline(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 60,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No report data yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sensor history for ${_prettyCrop(widget.crop)} has not been recorded yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _loadReport(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 58,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              'Unable to load report',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _loadReport(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  String _prettyCrop(String crop) {
    return crop
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}