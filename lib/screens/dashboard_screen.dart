import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sensor_data.dart';
import '../services/sensor_service.dart';
import '../theme/app_colors.dart';
import 'sensors_screen.dart';
import 'insights_tab.dart';
import 'ai_crop_screen.dart';
import 'reports_tab.dart';
import 'profile_screen.dart';
import 'add_field_screen.dart';
import 'notifications_screen.dart';

const _logoAsset = 'assets/smartcrop_new.png';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;
  final SensorService _sensorService = SensorService();
  SensorData? _sensorData;
  StreamSubscription<SensorData>? _subscription;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
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
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _TopBar(topPad: topPad),
          Expanded(
            child: switch (_selectedTab) {
              0 => _HomeTab(
                  sensorData: _sensorData,
                  onViewSensors: () => setState(() => _selectedTab = 1),
                ),
              1 => const SensorsTab(),
              2 => const InsightsTab(),
              3 => const ReportsTab(),
              4 => const ProfileScreen(),
              _ => Center(
                  child: Text(
                    _tabLabel(_selectedTab),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onBackground),
                  ),
                ),
            },
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFieldScreen()),
              ),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_location_alt_rounded, size: 20),
              label: Text(
                'Add Field',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              elevation: 6,
            )
          : null,
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedTab,
        onTap: (i) => setState(() => _selectedTab = i),
      ),
    );
  }

  String _tabLabel(int i) =>
      const ['Home', 'Sensors', 'Insights', 'Reports', 'Profile'][i];
}

// ─── Home Tab ────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final SensorData? sensorData;
  final VoidCallback onViewSensors;
  const _HomeTab({required this.sensorData, required this.onViewSensors});

  @override
  Widget build(BuildContext context) {
    final data = sensorData;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _GreetingWeatherRow(airTemp: data?.airTemp),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MainFieldCard(sensorData: data),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Field Overview',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
                GestureDetector(
                  onTap: onViewSensors,
                  child: Text(
                    'View All',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _FieldOverviewRow(
              sensorData: data,
              onTap: onViewSensors,
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'AI Recommendation',
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
            child: _AiRecommendationCard(),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StatusAlert(sensorData: data),
          ),
        ],
      ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final double topPad;
  const _TopBar({required this.topPad});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 14),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: Image.asset(
                _logoAsset,
                fit: BoxFit.contain,
                alignment: const Alignment(0.24, 0.0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'SmartCrop',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: Stack(
              children: [
                Icon(Icons.notifications_outlined,
                    size: 26, color: AppColors.onBackground),
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBA1A1A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
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

// ─── Greeting + Weather Row ───────────────────────────────────────────────────

class _GreetingWeatherRow extends StatelessWidget {
  final double? airTemp;
  const _GreetingWeatherRow({this.airTemp});

  @override
  Widget build(BuildContext context) {
    final temp = airTemp ?? 28;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GOOD MORNING, 👋',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                FirebaseAuth.instance.currentUser?.displayName ?? 'User',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Here's what's happening in your field today.",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Mini weather card
        Container(
          width: 108,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wb_sunny_rounded,
                    color: AppColors.primary, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                '${temp.toStringAsFixed(0)}°C',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                temp >= 30 ? 'Warm' : 'Partly\nCloudy',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Main Field Card ──────────────────────────────────────────────────────────

class _MainFieldCard extends StatelessWidget {
  final SensorData? sensorData;
  const _MainFieldCard({this.sensorData});

  @override
  Widget build(BuildContext context) {
    final data = sensorData;
    final moisture = data?.soilMoisturePercent ?? 42;
    final temp = data?.airTemp ?? 28;
    final ph = data?.pH ?? 6.5;
    final rain = data?.rainPercent ?? 20;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final moistureStatus = moisture >= 40 ? 'NORMAL' : moisture >= 20 ? 'LOW' : 'DRY';
    final tempStatus = temp >= 25 && temp <= 35 ? 'NORMAL' : temp > 35 ? 'HOT' : 'COOL';
    final phStatus = ph >= 6.0 && ph <= 7.5 ? 'NEUTRAL' : ph < 6.0 ? 'ACIDIC' : 'ALKALINE';
    final rainStatus = rain >= 30 ? 'HIGH' : rain >= 10 ? 'LOW' : 'DRY';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Field name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on_outlined,
                    color: Colors.white, size: 17),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Main Field',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 18),
                    ],
                  ),
                  Text(
                    'Vehari, Punjab',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Last Updated',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        time,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.refresh_rounded,
                          color: Colors.white70, size: 14),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Circular metrics row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CircularMetric(
                icon: Icons.water_drop_outlined,
                value: '${moisture.toStringAsFixed(0)}%',
                label: 'SOIL\nMOISTURE',
              ),
              _CircularMetric(
                icon: Icons.thermostat_outlined,
                value: '${temp.toStringAsFixed(0)}°C',
                label: 'TEMPER-\nATURE',
              ),
              _CircularMetricText(
                text: 'pH',
                value: ph.toStringAsFixed(1),
                label: 'pH LEVEL',
              ),
              _CircularMetric(
                icon: Icons.cloudy_snowing,
                value: '${rain.toStringAsFixed(0)}%',
                label: 'RAIN\nCHANCE',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MetricStatus(label: moistureStatus),
              _MetricStatus(label: tempStatus),
              _MetricStatus(label: phStatus),
              _MetricStatus(label: rainStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircularMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _CircularMetric(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.45), width: 1.5),
            color: Colors.white.withValues(alpha: 0.1),
          ),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CircularMetricText extends StatelessWidget {
  final String text;
  final String value;
  final String label;
  const _CircularMetricText(
      {required this.text, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.45), width: 1.5),
            color: Colors.white.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MetricStatus extends StatelessWidget {
  final String label;
  const _MetricStatus({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white70,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Field Overview Row ───────────────────────────────────────────────────────

class _FieldOverviewRow extends StatelessWidget {
  final SensorData? sensorData;
  final VoidCallback onTap;
  const _FieldOverviewRow({this.sensorData, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = sensorData;
    final n = data?.n ?? 38;
    final p = data?.p ?? 24;
    final k = data?.k ?? 210;
    final hum = data?.airHumidity ?? 65;

    return Row(
      children: [
        Expanded(child: _OverviewCard(top: 'N', value: '${n.toStringAsFixed(0)} ppm', status: n.toNutrientStatus().dashboardLabel, onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _OverviewCard(top: 'P', value: '${p.toStringAsFixed(0)} ppm', status: p.toNutrientStatus().dashboardLabel, onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _OverviewCard(top: 'K', value: '${k.toStringAsFixed(0)} ppm', status: k.toNutrientStatus().dashboardLabel, onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _OverviewCardIcon(icon: Icons.light_mode_outlined, value: '${hum.toStringAsFixed(0)}%', status: 'Good', onTap: onTap)),
      ],
    );
  }
}

extension on NutrientStatus {
  String get dashboardLabel {
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

class _OverviewCard extends StatelessWidget {
  final String top;
  final String value;
  final String status;
  final VoidCallback onTap;
  const _OverviewCard(
      {required this.top, required this.value, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            top,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _OverviewCardIcon extends StatelessWidget {
  final IconData icon;
  final String value;
  final String status;
  final VoidCallback onTap;
  const _OverviewCardIcon(
      {required this.icon, required this.value, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AI Recommendation Card ───────────────────────────────────────────────────

class _AiRecommendationCard extends StatelessWidget {
  const _AiRecommendationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eco_rounded,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Wheat',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBackground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '92% Match',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.trending_up_rounded,
                        color: Color(0xFF3E6A00), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Yield: High',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiCropScreen()),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Details',
                style: GoogleFonts.manrope(
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

// ─── Status Alert ─────────────────────────────────────────────────────────────

class _StatusAlert extends StatelessWidget {
  final SensorData? sensorData;
  const _StatusAlert({this.sensorData});

  @override
  Widget build(BuildContext context) {
    final data = sensorData;
    final moisture = data?.soilMoisturePercent ?? 42;
    final isNormal = moisture >= 40;
    final icon = isNormal ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded;
    final bgColor = isNormal ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final borderColor = isNormal ? AppColors.primary.withValues(alpha: 0.2) : const Color(0xFFFFCC80).withValues(alpha: 0.4);
    final iconColor = isNormal ? AppColors.primary : const Color(0xFFE65100);
    final message = isNormal
        ? 'Auto Irrigation is Active. Soil moisture is normal. No irrigation needed.'
        : 'Soil moisture is low (${moisture.toStringAsFixed(0)}%). Consider starting irrigation.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onBackground,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Navigation ────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.sensors_rounded, label: 'Sensors'),
    _NavItem(icon: Icons.auto_awesome_rounded, label: 'Insights'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Reports'),
    _NavItem(icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Icon(
                          _items[i].icon,
                          size: 22,
                          color: selected ? Colors.white : AppColors.outline,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _items[i].label,
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primary
                              : AppColors.outline,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
