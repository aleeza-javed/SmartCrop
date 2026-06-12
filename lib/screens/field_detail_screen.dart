import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class FieldDetailScreen extends StatelessWidget {
  final String fieldName;
  final String crop;
  final String area;
  final String location;
  final int healthScore;
  final int moisture;

  const FieldDetailScreen({
    super.key,
    required this.fieldName,
    required this.crop,
    required this.area,
    required this.location,
    required this.healthScore,
    required this.moisture,
  });

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
          _Header(fieldName: fieldName, location: location, onBack: () => Navigator.pop(context)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  _StatusBanner(crop: crop, area: area),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _HealthCard(score: healthScore),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _WeatherCard(),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SensorReadingsCard(moisture: moisture),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _FieldMapCard(),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _ActivityTimeline(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String fieldName;
  final String location;
  final VoidCallback onBack;

  const _Header({required this.fieldName, required this.location, required this.onBack});

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fieldName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withValues(alpha: 0.75)),
                          const SizedBox(width: 3),
                          Text(
                            location,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Banner ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String crop;
  final String area;

  const _StatusBanner({required this.crop, required this.area});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Optimal Conditions',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '$crop · $area',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF4A7A4A),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Start Irrigation',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Health Card ──────────────────────────────────────────────────────────────

class _HealthCard extends StatelessWidget {
  final int score;
  const _HealthCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 85 ? AppColors.primary : const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Ring + labels row
          Row(
            children: [
              // Large score ring
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background track
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 10,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFFEEF1ED),
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Score arc
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 10,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$score',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A1A),
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'out of 100',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF6B7A6B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Right side text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Field Health Score',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up_rounded, size: 15, color: scoreColor),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              score >= 85 ? 'Good condition' : 'Needs attention',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scoreColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.show_chart_rounded, size: 14, color: Color(0xFF6B7A6B)),
                        const SizedBox(width: 5),
                        Text(
                          '5% healthier than last week',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF4A5568),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Wide progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Health Index',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7A6B),
                    ),
                  ),
                  Text(
                    '$score%',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 12,
                  backgroundColor: const Color(0xFFEEF1ED),
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: GoogleFonts.manrope(fontSize: 10, color: const Color(0xFF9E9E9E), fontWeight: FontWeight.w500)),
                  Text('Poor', style: GoogleFonts.manrope(fontSize: 10, color: const Color(0xFFE65100), fontWeight: FontWeight.w600)),
                  Text('Good', style: GoogleFonts.manrope(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  Text('100', style: GoogleFonts.manrope(fontSize: 10, color: const Color(0xFF9E9E9E), fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Weather Card ─────────────────────────────────────────────────────────────

class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  static const _forecast = [
    _WeatherDay(day: 'Mon', temp: '24°', icon: Icons.cloud_queue_rounded, color: Color(0xFFFFA000)),
    _WeatherDay(day: 'Tue', temp: '26°', icon: Icons.wb_sunny_rounded, color: Color(0xFFFFA000)),
    _WeatherDay(day: 'Wed', temp: '21°', icon: Icons.grain_rounded, color: Color(0xFF1565C0)),
    _WeatherDay(day: 'Thu', temp: '22°', icon: Icons.cloud_rounded, color: Color(0xFF78909C)),
    _WeatherDay(day: 'Fri', temp: '25°', icon: Icons.wb_sunny_rounded, color: Color(0xFFFFA000)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFA000), size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                '5-Day Forecast',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'STABLE',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _forecast.map((d) => _DayTile(day: d)).toList(),
          ),
        ],
      ),
    );
  }
}

class _WeatherDay {
  final String day;
  final String temp;
  final IconData icon;
  final Color color;
  const _WeatherDay({required this.day, required this.temp, required this.icon, required this.color});
}

class _DayTile extends StatelessWidget {
  final _WeatherDay day;
  const _DayTile({required this.day});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(day.day, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6B7A6B))),
        const SizedBox(height: 6),
        Icon(day.icon, size: 22, color: day.color),
        const SizedBox(height: 6),
        Text(day.temp, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }
}

// ─── Sensor Readings Card ─────────────────────────────────────────────────────

class _SensorReadingsCard extends StatelessWidget {
  final int moisture;
  const _SensorReadingsCard({required this.moisture});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
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
                child: Icon(Icons.sensors_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Environmental Sensors',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SensorTile(
                  icon: Icons.water_drop_rounded,
                  iconColor: const Color(0xFF1565C0),
                  label: 'Soil Moisture',
                  value: '$moisture%',
                  badge: moisture >= 40 ? 'OPTIMAL' : 'LOW',
                  badgeColor: moisture >= 40 ? AppColors.primary : const Color(0xFFB71C1C),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SensorTile(
                  icon: Icons.science_rounded,
                  iconColor: const Color(0xFF00796B),
                  label: 'Soil pH',
                  value: '6.8',
                  badge: 'NEUTRAL',
                  badgeColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SensorTile(
                  icon: Icons.wb_sunny_rounded,
                  iconColor: const Color(0xFFFFA000),
                  label: 'Sunlight',
                  value: '842 lux',
                  badge: 'HIGH',
                  badgeColor: const Color(0xFFFFA000),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String badge;
  final Color badgeColor;

  const _SensorTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E8DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF6B7A6B)),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              badge,
              style: GoogleFonts.manrope(fontSize: 9, fontWeight: FontWeight.w800, color: badgeColor, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Field Map Card ───────────────────────────────────────────────────────────

class _FieldMapCard extends StatelessWidget {
  const _FieldMapCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            CustomPaint(painter: _MapPainter(), child: Container()),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_rounded, size: 12, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text('Field Map', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fullscreen_rounded, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Expand', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
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

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF3D6B47));
    final line = Paint()..color = Colors.white.withValues(alpha: 0.07)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Field boundary
    canvas.drawRect(
      Rect.fromLTRB(size.width * 0.08, size.height * 0.12, size.width * 0.92, size.height * 0.88),
      Paint()..color = const Color(0xFFB9F474).withValues(alpha: 0.65)..style = PaintingStyle.stroke..strokeWidth = 2,
    );
    canvas.drawRect(
      Rect.fromLTRB(size.width * 0.08, size.height * 0.12, size.width * 0.92, size.height * 0.88),
      Paint()..color = const Color(0xFFB9F474).withValues(alpha: 0.07),
    );
    // Sensor dot
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      6,
      Paint()..color = const Color(0xFF1565C0),
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      12,
      Paint()..color = const Color(0xFF1565C0).withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Activity Timeline ────────────────────────────────────────────────────────

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline();

  static const _activities = [
    _Activity(
      icon: Icons.water_drop_rounded,
      iconColor: Color(0xFF1565C0),
      title: 'Irrigation Delivered',
      detail: '15mm · Zone A-4',
      time: 'Today, 6:00 AM',
    ),
    _Activity(
      icon: Icons.agriculture_rounded,
      iconColor: Color(0xFF2E7D32),
      title: 'Nitrogen Fertilizer Applied',
      detail: '50 kg/acre · Urea',
      time: 'Yesterday',
    ),
    _Activity(
      icon: Icons.sensors_rounded,
      iconColor: Color(0xFF00796B),
      title: 'Sensor Recalibrated',
      detail: 'Moisture-X Hub',
      time: 'Oct 12',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
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
                child: Icon(Icons.history_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Recent Activity',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(_activities.length, (i) => _TimelineTile(
                activity: _activities[i],
                isLast: i == _activities.length - 1,
              )),
        ],
      ),
    );
  }
}

class _Activity {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final String time;
  const _Activity({required this.icon, required this.iconColor, required this.title, required this.detail, required this.time});
}

class _TimelineTile extends StatelessWidget {
  final _Activity activity;
  final bool isLast;
  const _TimelineTile({required this.activity, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: activity.iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(activity.icon, color: activity.iconColor, size: 16),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1, color: const Color(0xFFDDE1DA), margin: const EdgeInsets.symmetric(vertical: 4)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activity.title, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(activity.detail, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF4A5568))),
                      const SizedBox(width: 8),
                      Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF9E9E9E))),
                      const SizedBox(width: 8),
                      Text(activity.time, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF9E9E9E))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
