import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sensor_data.dart';
import '../services/crop_api_service.dart';
import '../theme/app_colors.dart';

class SensorAlertDetailScreen extends StatefulWidget {
  final SensorData? sensorData;
  final String crop;
  const SensorAlertDetailScreen({super.key, this.sensorData, this.crop = 'wheat'});

  @override
  State<SensorAlertDetailScreen> createState() => _SensorAlertDetailScreenState();
}

class _SensorAlertDetailScreenState extends State<SensorAlertDetailScreen> {
  bool _loading = true;
  MonitoringResult? _monitorResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMonitoringData();
  }

  Future<void> _fetchMonitoringData() async {
    final data = widget.sensorData;
    if (data == null) {
      setState(() {
        _error = 'Sensor data unavailable';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _monitorResult = null;
      _error = null;
    });
    try {
      final current = {
        'N': data.n,
        'P': data.p,
        'K': data.k,
        'temperature': data.airTemp,
        'humidity': data.airHumidity,
        'ph': data.pH,
        'soil_moisture': data.soilMoisturePercent,
      };
      final result = await CropApiService.getMonitoringAlerts(
        crop: widget.crop,
        current: current,
      );
      setState(() {
        _monitorResult = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load monitoring data: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _ErrorWidget(message: _error!)
                  else if (_monitorResult == null)
                    const Center(child: Text('No monitoring data available'))
                  else
                    _buildContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final result = _monitorResult!;
    final alerts = result.alerts;
    final paramResults = result.parameterResults;
    final sensorData = widget.sensorData!;

    return Column(
      children: [
        _AlertHeroBanner(
          alerts: alerts,
          overallStatus: result.overallStatus,
          crop: widget.crop,
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _NPKCard(
            sensorData: sensorData,
            paramResults: paramResults,
          ),
        ),
        const SizedBox(height: 16),
        const _SectorMapCard(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SoilConditionsRow(sensorData: sensorData),
        ),
        const SizedBox(height: 16),
        _AIRecommendationCard(
          alerts: alerts,
          recommendations: result.recommendations,
          overallStatus: result.overallStatus,
        ),
        const SizedBox(height: 28),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _ActionButtons(),
        ),
      ],
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String message;
  const _ErrorWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFBA1A1A), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: const Color(0xFF4A3000),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topPad + 12, bottom: 24, left: 16, right: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Alert Details',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertHeroBanner extends StatelessWidget {
  final List<MonitoringAlert> alerts;
  final String overallStatus;
  final String crop;
  const _AlertHeroBanner({
    required this.alerts,
    required this.overallStatus,
    required this.crop,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = alerts.isNotEmpty;
    final isCritical = overallStatus == 'CRITICAL';
    final bannerColor = isCritical ? const Color(0xFF7F0000) : const Color(0xFF1B5E20);
    final bannerSecondary = isCritical ? const Color(0xFFB71C1C) : const Color(0xFF2E7D32);
    final alertLabel = hasAlert
        ? '${alerts.first.type.toUpperCase()} ALERT'
        : 'NORMAL';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bannerColor, bannerSecondary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bannerSecondary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_rounded, color: Colors.white, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            hasAlert ? 'CRITICAL ALERT' : 'NORMAL',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      alertLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  hasAlert
                      ? '${alerts.first.type == 'deficiency' ? 'Deficiency' : 'Excess'} Alert — ${alerts.first.parameter}'
                      : '$crop Monitoring Normal',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  crop.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.grass_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        crop,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
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

class _NPKCard extends StatelessWidget {
  final SensorData sensorData;
  final Map<String, dynamic> paramResults;
  const _NPKCard({required this.sensorData, required this.paramResults});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.science_rounded, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'NPK Nutrient Profile',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _NutrientBar(
              symbol: 'N',
              name: 'Nitrogen',
              value: sensorData.n,
              maxValue: 120,
              optimalMin: 107,
              optimalMax: 131,
              unit: 'ppm',
              status: _getStatusText('N'),
              isLow: sensorData.n < 107,
            ),
            const SizedBox(height: 18),
            _NutrientBar(
              symbol: 'P',
              name: 'Phosphorus',
              value: sensorData.p,
              maxValue: 60,
              optimalMin: 48,
              optimalMax: 74,
              unit: 'ppm',
              status: _getStatusText('P'),
              isLow: sensorData.p < 48,
            ),
            const SizedBox(height: 18),
            _NutrientBar(
              symbol: 'K',
              name: 'Potassium',
              value: sensorData.k,
              maxValue: 54,
              optimalMin: 35,
              optimalMax: 54,
              unit: 'ppm',
              status: _getStatusText('K'),
              isLow: sensorData.k < 35,
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(String param) {
    final result = paramResults[param];
    if (result == null) return 'Normal Level';
    final status = result['status'] as String? ?? '';
    if (status == 'CRITICAL') return 'Critical Level';
    if (status == 'WARNING') return 'Warning Level';
    return 'Normal Level';
  }
}

class _NutrientBar extends StatelessWidget {
  final String symbol;
  final String name;
  final double value;
  final double maxValue;
  final double optimalMin;
  final double optimalMax;
  final String unit;
  final String status;
  final bool isLow;

  const _NutrientBar({
    required this.symbol,
    required this.name,
    required this.value,
    required this.maxValue,
    required this.optimalMin,
    required this.optimalMax,
    required this.unit,
    required this.status,
    required this.isLow,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isLow ? const Color(0xFFE65100) : AppColors.primary;
    final statusBg = isLow ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9);
    final statusColor = isLow ? const Color(0xFFE65100) : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: fillColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  symbol,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fillColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  Text(
                    'Optimal: ${optimalMin.toInt()}–${optimalMax.toInt()} $unit',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: const Color(0xFF6B7A6B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${value.toStringAsFixed(0)} $unit',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: fillColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final fillWidth = (value / maxValue).clamp(0.0, 1.0) * totalWidth;
            final optMinX = (optimalMin / maxValue).clamp(0.0, 1.0) * totalWidth;
            final optMaxX = (optimalMax / maxValue).clamp(0.0, 1.0) * totalWidth;

            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF1ED),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Positioned(
                  left: optMinX,
                  child: Container(
                    width: (optMaxX - optMinX).clamp(0.0, totalWidth),
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Container(
                  height: 8,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: fillColor.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectorMapCard extends StatelessWidget {
  const _SectorMapCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            CustomPaint(
              painter: _MapGridPainter(),
              child: Container(),
            ),
            const Center(
              child: _PulsingMarker(),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded, size: 14, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      'Field Map View',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF3D6B47);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final sectorPaint = Paint()
      ..color = const Color(0xFFFFEB3B).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 100, height: 80),
      sectorPaint,
    );

    final fillPaint = Paint()
      ..color = const Color(0xFFFFEB3B).withValues(alpha: 0.08);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 100, height: 80),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulsingMarker extends StatefulWidget {
  const _PulsingMarker();

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - _ctrl.value).clamp(0.0, 0.5),
              child: Container(
                width: 40 + _ctrl.value * 24,
                height: 40 + _ctrl.value * 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB71C1C).withValues(alpha: 0.3),
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFB71C1C),
              ),
              child: const Icon(Icons.warning_rounded, color: Colors.white, size: 10),
            ),
          ],
        );
      },
    );
  }
}

class _SoilConditionsRow extends StatelessWidget {
  final SensorData sensorData;
  const _SoilConditionsRow({required this.sensorData});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ConditionTile(
            icon: Icons.water_drop_rounded,
            iconColor: const Color(0xFF1565C0),
            label: 'Soil Moisture',
            value: sensorData.soilMoisturePercent.toStringAsFixed(0),
            unit: '%',
            note: sensorData.soilMoisturePercent >= 40 ? 'Optimal' : sensorData.soilMoisturePercent >= 20 ? 'Low' : 'Dry',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ConditionTile(
            icon: Icons.science_rounded,
            iconColor: const Color(0xFF00796B),
            label: 'pH Level',
            value: sensorData.pH.toStringAsFixed(1),
            unit: '',
            note: sensorData.pH >= 6.0 && sensorData.pH <= 7.5 ? 'Neutral' : sensorData.pH < 6.0 ? 'Acidic' : 'Alkaline',
          ),
        ),
      ],
    );
  }
}

class _ConditionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final String note;

  const _ConditionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7A6B),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7A6B),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6B7A6B),
            ),
          ),
        ],
      ),
    );
  }
}

class _AIRecommendationCard extends StatelessWidget {
  final List<MonitoringAlert> alerts;
  final List<String> recommendations;
  final String overallStatus;
  const _AIRecommendationCard({
    required this.alerts,
    required this.recommendations,
    required this.overallStatus,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlerts = alerts.isNotEmpty;
    final isDeficiency = hasAlerts && alerts.any((a) => a.type == 'deficiency');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Recommendation',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        'Powered by SmartCrop AI',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF6B7A6B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: hasAlerts ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hasAlerts
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasAlerts ? const Color(0xFFBA1A1A) : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasAlerts ? 'ALERT' : 'NORMAL',
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: hasAlerts ? const Color(0xFFBA1A1A) : AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (hasAlerts && recommendations.isNotEmpty)
              ...List.generate(recommendations.length, (i) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isDeficiency ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDeficiency ? const Color(0xFFFFE082) : AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isDeficiency ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: isDeficiency ? const Color(0xFFE65100) : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          recommendations[i],
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDeficiency ? const Color(0xFF4A3000) : const Color(0xFF1A3A1A),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (!hasAlerts)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.agriculture_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended Action',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All nutrient levels are within the optimal range. No action needed at this time.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A3A1A),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Schedule Fertilization',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    'Dismiss',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB71C1C),
                    side: const BorderSide(color: Color(0xFFB71C1C), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    'Share',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4A5568),
                    side: const BorderSide(color: Color(0xFFBFCABA), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}