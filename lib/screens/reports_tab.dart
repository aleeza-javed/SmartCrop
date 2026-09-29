import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/crop_api_service.dart';
import '../services/sensor_service.dart';
import '../services/active_crop_service.dart';
import '../theme/app_colors.dart';

class ReportsTab extends StatefulWidget {
  final String crop;

  const ReportsTab({super.key, this.crop = 'wheat'});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  String _activeCrop = 'wheat';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final crop = await ActiveCropService.getActiveCrop();
    if (mounted) {
      setState(() {
        _activeCrop = crop;
      });
    }
  }

  Future<void> _refresh() async {
    await _init();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _HeaderBar(crop: _activeCrop, onRefresh: _refresh),
              const SizedBox(height: 20),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _LoadingView();
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(message: '${snapshot.error}', onRetry: _refresh);
                  }
                  final history = snapshot.data ?? [];
                  if (history.isEmpty) {
                    return _EmptyStateView();
                  }
                  return _ReportContent(
                    crop: _activeCrop,
                    history: history,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    final service = SensorService();
    final readings = await service.fetchHistory(_activeCrop);
    return readings.map((r) => r.toMonitorPayload()).toList();
  }
}

class _HeaderBar extends StatelessWidget {
  final String crop;
  final VoidCallback onRefresh;

  const _HeaderBar({required this.crop, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reports',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Crop: ${crop[0].toUpperCase()}${crop.substring(1)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onRefresh,
                child: const Icon(Icons.refresh, size: 18, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Failed to load reports: $message',
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.red.shade700)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.sensor_door_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No sensor history yet',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recordings will appear here once the sensor system\nhas collected data for the active crop.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportContent extends StatefulWidget {
  final String crop;
  final List<Map<String, dynamic>> history;

  const _ReportContent({required this.crop, required this.history});

  @override
  State<_ReportContent> createState() => _ReportContentState();
}

class _ReportContentState extends State<_ReportContent> {
  late final Future<WaterReport> _waterFuture;
  late final Future<NutrientReport> _nutrientFuture;
  late final Future<MonthlyHealthReport> _monthlyFuture;
  late final Future<SoilHealthReport> _soilHealthFuture;

  @override
  void initState() {
    super.initState();
    _waterFuture = CropApiService.getWaterReport(
      crop: widget.crop,
      history: widget.history,
    );
    _nutrientFuture = CropApiService.getNutrientReport(
      crop: widget.crop,
      history: widget.history,
    );
    _monthlyFuture = CropApiService.getMonthlyHealthReport(
      crop: widget.crop,
      history: widget.history,
    );
    _soilHealthFuture = CropApiService.getSoilHealthReport(
      crop: widget.crop,
      history: widget.history,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _SectionTitle('Water Usage'),
          const SizedBox(height: 10),
          FutureBuilder<WaterReport>(
            future: _waterFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _WaterUsageCard(report: snapshot.data!);
              }
              if (snapshot.hasError) {
                return _ErrorCard(message: '${snapshot.error}');
              }
              return _LoadingCard();
            },
          ),
          const SizedBox(height: 16),
          _SectionTitle('Soil Nutrient Health'),
          const SizedBox(height: 10),
          FutureBuilder<NutrientReport>(
            future: _nutrientFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _NutrientHealthCard(report: snapshot.data!);
              }
              if (snapshot.hasError) {
                return _ErrorCard(message: '${snapshot.error}');
              }
              return _LoadingCard();
            },
          ),
          const SizedBox(height: 16),
          _SectionTitle('Crop Monthly Health'),
          const SizedBox(height: 10),
          FutureBuilder<MonthlyHealthReport>(
            future: _monthlyFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _MonthlyHealthCard(report: snapshot.data!);
              }
              if (snapshot.hasError) {
                return _ErrorCard(message: '${snapshot.error}');
              }
              return _LoadingCard();
            },
          ),
          const SizedBox(height: 16),
          _SectionTitle('Soil Health Index'),
          const SizedBox(height: 10),
          FutureBuilder<SoilHealthReport>(
            future: _soilHealthFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _SoilHealthCard(report: snapshot.data!);
              }
              if (snapshot.hasError) {
                return _ErrorCard(message: '${snapshot.error}');
              }
              return _LoadingCard();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackground,
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final isConnectionError = message.contains('SocketException') || message.contains('Connection') || message.contains('timeout');
    final displayMessage = isConnectionError
        ? 'Server unavailable. Make sure the SmartCrop backend is running.'
        : message;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.orange.shade400, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayMessage,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.orange.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Water Usage Card ──────────────────────────────────────────────

class _WaterUsageCard extends StatelessWidget {
  final WaterReport report;

  const _WaterUsageCard({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.status == 'insufficient_data') {
      return _EmptyCard(
        title: 'Water Usage',
        message: 'No soil moisture data available yet.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WATER / MOISTURE',
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.5),
              ),
              _StatusBadge(status: report.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${report.currentValue.toStringAsFixed(1)}%',
            style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.onBackground),
          ),
          const SizedBox(height: 4),
          Text(
            'Soil moisture (not water volume)',
            style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Text(
            'Recommended: ${report.recommendedRange[0].toStringAsFixed(0)}% – ${report.recommendedRange[1].toStringAsFixed(0)}%',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (report.statistics['average'] != null)
            Text(
              'Average: ${report.statistics['average'].toStringAsFixed(1)}% (${report.statistics['total_readings'] ?? 0} readings)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade600),
            ),
          if (report.trend != 'insufficient_data' && report.trend.isNotEmpty)
            Text(
              'Trend: ${report.trend == 'increasing' ? '↑ Up' : report.trend == 'decreasing' ? '↓ Down' : '→ Stable'}',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade600),
            ),
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...report.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: w['severity'] == 'CRITICAL' ? Colors.red : Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      w['message']?.toString() ?? '',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: 4),
          Text(
            report.note,
            style: GoogleFonts.plusJakartaSans(fontSize: 9, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(message, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.grey.shade600)),
      ),
    );
  }
}

// ── Nutrient Health Card ──────────────────────────────────────────

class _NutrientHealthCard extends StatelessWidget {
  final NutrientReport report;

  const _NutrientHealthCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final nutrients = report.nutrients;
    final nutrientKeys = ['N', 'P', 'K', 'pH', 'EC'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: _statusColor(report.status), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SOIL NUTRIENTS',
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.5),
              ),
              _StatusBadge(status: report.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Health Score: ${report.healthScore}/100',
            style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onBackground),
          ),
          const SizedBox(height: 12),
          ...nutrientKeys.map((key) {
            final data = nutrients[key];
            if (data is! Map) return const SizedBox.shrink();
            final value = data['current']?.toDouble() ?? 0;
            final unit = data['unit']?.toString() ?? '';
            final label = data['label']?.toString() ?? key;
            final status = data['status']?.toString() ?? 'unknown';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.onBackground)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${value.toStringAsFixed(value == value.round() ? 0 : 1)} $unit',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: _statusColor(status))),
                      const SizedBox(width: 6),
                      _StatusDot(status: status),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Monthly Health Card ───────────────────────────────────────────

class _MonthlyHealthCard extends StatelessWidget {
  final MonthlyHealthReport report;

  const _MonthlyHealthCard({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.months.isEmpty) {
      return _EmptyCard(title: 'Monthly Health', message: 'No monthly data available yet.');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: AppColors.secondary, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MONTHLY HEALTH',
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.5),
              ),
              Text(
                '${report.totalReadings} readings',
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...report.months.map((month) {
            final monthKey = month['month']?.toString() ?? '';
            final avgSoilMoisture = month['averages']?['soilMoisturePercent']?.toDouble() ?? 0;
            final avgTemp = month['averages']?['temperature']?.toDouble() ?? 0;
            final healthScore = month['health_score']?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(monthKey, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onBackground)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Score: $healthScore', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: _scoreColor(healthScore))),
                      Text('$avgSoilMoisture% / ${avgTemp.toStringAsFixed(0)}°C', style: GoogleFonts.manrope(fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (report.months.isNotEmpty && report.months.last['alert_count'] != null && (report.months.last['alert_count'] as int) > 0) ...[
            const SizedBox(height: 8),
            Text('Alerts in latest month: ${report.months.last['alert_count']}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.orange.shade700)),
          ],
        ],
      ),
    );
  }
}

// ── Soil Health Card ──────────────────────────────────────────────

class _SoilHealthCard extends StatelessWidget {
  final SoilHealthReport report;

  const _SoilHealthCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: _statusColor(report.overallStatus), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SOIL HEALTH INDEX',
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.5),
              ),
              _StatusBadge(status: report.overallStatus),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${report.soilHealthIndex.toStringAsFixed(2)} / 1.0',
            style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onBackground),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: report.soilHealthIndex.clamp(0, 1),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_statusColor(report.overallStatus)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Based on: ${report.components.keys.map((k) {
              final c = report.components[k];
              final v = c is Map ? c['value']?.toDouble() : null;
              return v != null ? '$k: ${v.toStringAsFixed(1)}' : k;
            }).join(', ')}',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...report.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${w['label'] ?? w['parameter']}: ${w['message'] ?? ''}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status)),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _statusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'NORMAL':
    case 'SUFFICIENT':
    case 'OPTIMAL':
      return Colors.green.shade700;
    case 'WARNING':
      return Colors.orange.shade700;
    case 'CRITICAL':
    case 'DEFICIENT':
    case 'EXCESS':
      return Colors.red.shade700;
    case 'INSUFFICIENT_DATA':
    case 'missing':
      return Colors.grey.shade600;
    default:
      return Colors.grey.shade600;
  }
}

Color _scoreColor(int score) {
  if (score >= 80) return Colors.green.shade700;
  if (score >= 50) return Colors.orange.shade700;
  return Colors.red.shade700;
}
