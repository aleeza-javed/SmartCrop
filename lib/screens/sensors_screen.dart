import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sensor_data.dart';
import '../services/sensor_service.dart';
import '../theme/app_colors.dart';
import 'device_pairing_screen.dart';
import 'sensor_alert_detail_screen.dart';

class SensorsTab extends StatefulWidget {
  const SensorsTab({super.key});

  @override
  State<SensorsTab> createState() => _SensorsTabState();
}

class _SensorsTabState extends State<SensorsTab> {
  final SensorService _sensorService = SensorService();
  SensorData? _sensorData;
  StreamSubscription<SensorData>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _sensorService.sensorDataStream().listen((data) {
      if (mounted) setState(() => _sensorData = data);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _sensorData;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          // ── Location Card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LocationCard(
              lastUpdated: _formatTime(DateTime.now()),
            ),
          ),
          const SizedBox(height: 24),

          // ── Real-time Readings ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Real-time Readings',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _SoilMoistureCard(
                  moisturePercent: data.soilMoisturePercent,
                ),
                _SimpleMetricCard(
                  label: 'Temperature',
                  value: data.airTemp.toStringAsFixed(1),
                  unit: '°C',
                  status: _tempStatus(data.airTemp),
                  statusColor: _StatusColor.green,
                ),
                _SimpleMetricCard(
                  label: 'pH Level',
                  value: data.pH.toStringAsFixed(1),
                  unit: '',
                  status: _pHStatus(data.pH),
                  statusColor: _StatusColor.teal,
                ),
                _SimpleMetricCard(
                  label: 'Humidity',
                  value: data.airHumidity.toStringAsFixed(0),
                  unit: '%',
                  status: 'Good',
                  statusColor: _StatusColor.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Soil Nutrients ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Soil Nutrients',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _NutrientCard(
                      symbol: 'N',
                      value: data.n.toStringAsFixed(0),
                      unit: 'ppm',
                      status: data.n.toNutrientStatus().label),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NutrientCard(
                      symbol: 'P',
                      value: data.p.toStringAsFixed(0),
                      unit: 'ppm',
                      status: data.p.toNutrientStatus().label),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NutrientCard(
                      symbol: 'K',
                      value: data.k.toStringAsFixed(0),
                      unit: 'ppm',
                      status: data.k.toNutrientStatus().label),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Historical Trends ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Historical Trends',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _TrendChartCard(),
          ),
          const SizedBox(height: 28),

          // ── Recent Alerts ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Recent Alerts',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AlertRow(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SensorAlertDetailScreen()),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Device Status ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Device Status',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DevicePairingScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'Pair Device',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _DeviceCard(
              name: 'Smart Sensor Node',
              serial: data.n == 0 ? 'N/A' : 'Online',
              battery: 0.75,
              batteryLabel: '75%',
              icon: Icons.sensors_rounded,
              iconColor: const Color(0xFF1565C0),
              online: true,
            ),
          ),
        ],
      ),
    );
  }

  String _tempStatus(double temp) {
    if (temp >= 25 && temp <= 35) return 'Normal';
    if (temp > 35) return 'Hot';
    return 'Cool';
  }

  String _pHStatus(double pH) {
    if (pH >= 6.0 && pH <= 7.5) return 'Neutral';
    if (pH < 6.0) return 'Acidic';
    return 'Alkaline';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

extension on NutrientStatus {
  String get label {
    switch (this) {
      case NutrientStatus.adequate:
        return 'Adequate';
      case NutrientStatus.low:
        return 'Low';
      case NutrientStatus.high:
        return 'High';
    }
  }
}

// ─── Location Card ────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  final String lastUpdated;
  const _LocationCard({required this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Colors.white70, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      'Main Field',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Vehari, Punjab',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'LAST UPDATED',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                lastUpdated,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Soil Moisture Card (with arc gauge) ─────────────────────────────────────

class _SoilMoistureCard extends StatelessWidget {
  final double moisturePercent;
  const _SoilMoistureCard({required this.moisturePercent});

  @override
  Widget build(BuildContext context) {
    final fraction = (moisturePercent / 100).clamp(0.0, 1.0);
    final status = fraction.toMoistureStatus();
    final (label, color) = switch (status) {
      MoistureStatus.optimal => ('Optimal', _StatusColor.green),
      MoistureStatus.low => ('Low', _StatusColor.amber),
      MoistureStatus.dry => ('Dry', _StatusColor.amber),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Soil Moisture',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onBackground,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: _ArcGaugePainter(value: fraction),
              child: Center(
                child: Text(
                  '${moisturePercent.toStringAsFixed(0)}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
              ),
            ),
          ),
          _StatusChip(label: label, color: color),
        ],
      ),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double value; // 0.0 to 1.0

  const _ArcGaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    const startAngle = 135 * pi / 180;
    const totalSweep = 270 * pi / 180;

    final bgPaint = Paint()
      ..color = const Color(0xFFE0E4D9)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      bgPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep * value,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) => old.value != value;
}

// ─── Simple Metric Card ───────────────────────────────────────────────────────

enum _StatusColor { green, teal, amber }

class _SimpleMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final _StatusColor statusColor;

  const _SimpleMetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onBackground,
            ),
          ),
          Center(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onBackground,
                      height: 1,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurfaceVariant,
                        height: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(label: status, color: statusColor),
          ),
        ],
      ),
    );
  }
}

// ─── Status Chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final _StatusColor color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (color) {
      case _StatusColor.green:
        bg = const Color(0xFFD6F5D6);
        fg = const Color(0xFF1B6B1B);
      case _StatusColor.teal:
        bg = const Color(0xFFCCF2EE);
        fg = const Color(0xFF006156);
      case _StatusColor.amber:
        bg = const Color(0xFFFFF3CD);
        fg = const Color(0xFF856404);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ─── Nutrient Card ────────────────────────────────────────────────────────────

class _NutrientCard extends StatelessWidget {
  final String symbol;
  final String value;
  final String unit;
  final String status;

  const _NutrientCard({
    required this.symbol,
    required this.value,
    required this.unit,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            symbol,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value $unit',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          _StatusChip(label: status, color: _StatusColor.green),
        ],
      ),
    );
  }
}

// ─── Trend Chart Card ─────────────────────────────────────────────────────────

class _TrendChartCard extends StatefulWidget {
  const _TrendChartCard();

  @override
  State<_TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<_TrendChartCard> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Soil Moisture Trend',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              _TrendToggle(
                selected: _range,
                onChanged: (v) => setState(() => _range = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                '+2.4% vs yesterday',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: CustomPaint(
              painter: _LinePainter(range: _range),
              size: const Size(double.infinity, 110),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: (_range == 0
                    ? ['06:00', '12:00', '18:00', 'Now']
                    : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                .map((t) => Text(
                      t,
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _TrendToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _TrendToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Chip(label: '24h', selected: selected == 0, onTap: () => onChanged(0)),
          const SizedBox(width: 2),
          _Chip(label: '7d', selected: selected == 1, onTap: () => onChanged(1)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final int range;
  _LinePainter({required this.range});

  @override
  void paint(Canvas canvas, Size size) {
    final pts24h = [0.38, 0.42, 0.55, 0.48, 0.60, 0.52, 0.45, 0.50, 0.42];
    final pts7d = [0.35, 0.50, 0.45, 0.60, 0.40, 0.55, 0.42];
    final data = range == 0 ? pts24h : pts7d;
    final n = data.length;

    List<Offset> pts = List.generate(n, (i) {
      final x = (i / (n - 1)) * size.width;
      final y = size.height - data[i] * size.height;
      return Offset(x, y);
    });

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cpX = (pts[i].dx + pts[i + 1].dx) / 2;
      path.cubicTo(cpX, pts[i].dy, cpX, pts[i + 1].dy,
          pts[i + 1].dx, pts[i + 1].dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    for (final p in pts) {
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.range != range;
}

// ─── Device Card ──────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final String name;
  final String serial;
  final double battery;
  final String batteryLabel;
  final IconData icon;
  final Color iconColor;
  final bool online;

  const _DeviceCard({
    required this.name,
    required this.serial,
    required this.battery,
    required this.batteryLabel,
    required this.icon,
    required this.iconColor,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final batteryColor = battery > 0.5
        ? AppColors.primary
        : battery > 0.25
            ? const Color(0xFFE65100)
            : const Color(0xFFBA1A1A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBackground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: online ? AppColors.primary : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      online ? 'Online' : 'Offline',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: online ? AppColors.primary : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'SN: $serial',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(
                    battery > 0.5
                        ? Icons.battery_full_rounded
                        : battery > 0.25
                            ? Icons.battery_4_bar_rounded
                            : Icons.battery_2_bar_rounded,
                    color: batteryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    batteryLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: batteryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: battery,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Alert Row ────────────────────────────────────────────────────────────────

class _AlertRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AlertRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFCDD2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Color(0xFFB71C1C),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Low Nitrogen Alert — Sector A-12',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'May 24, 2024 • 08:14 AM · Winter Wheat',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7A6B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'CRITICAL',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB71C1C),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6B7A6B),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
