import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'device_pairing_screen.dart';

class ConnectedSensorsScreen extends StatelessWidget {
  const ConnectedSensorsScreen({super.key});

  static const _devices = [
    _DeviceData(
      name: 'Moisture-X Hub',
      serial: 'SN: 8821-449-1',
      field: 'Main Field',
      type: 'Soil Moisture + NPK',
      icon: Icons.memory_rounded,
      iconColor: Color(0xFF1565C0),
      battery: 0.88,
      batteryLabel: '88%',
      signalStrength: 3,
      online: true,
      lastSeen: 'Just now',
      readings: [
        _Reading(label: 'Moisture', value: '64%', color: Color(0xFF1565C0)),
        _Reading(label: 'Nitrogen', value: '38 ppm', color: Color(0xFFE65100)),
        _Reading(label: 'Temp', value: '28°C', color: Color(0xFF2E7D32)),
      ],
    ),
    _DeviceData(
      name: 'LightNode Pro',
      serial: 'SN: 7712-003-A',
      field: 'North Field',
      type: 'Light + Temperature',
      icon: Icons.bolt_rounded,
      iconColor: Color(0xFFF9A825),
      battery: 0.42,
      batteryLabel: '42%',
      signalStrength: 2,
      online: true,
      lastSeen: '2 min ago',
      readings: [
        _Reading(label: 'Light', value: '65%', color: Color(0xFFF9A825)),
        _Reading(label: 'Temp', value: '31°C', color: Color(0xFFE65100)),
        _Reading(label: 'Humidity', value: '72%', color: Color(0xFF1565C0)),
      ],
    ),
    _DeviceData(
      name: 'AquaSense Node',
      serial: 'SN: 3309-B12-7',
      field: 'South Field',
      type: 'Water Flow + pH',
      icon: Icons.water_rounded,
      iconColor: Color(0xFF00796B),
      battery: 0.15,
      batteryLabel: '15%',
      signalStrength: 1,
      online: false,
      lastSeen: '3 hours ago',
      readings: [
        _Reading(label: 'pH', value: '6.4', color: Color(0xFF00796B)),
        _Reading(label: 'Flow', value: '0 L/h', color: Color(0xFF9E9E9E)),
        _Reading(label: 'TDS', value: '420 ppm', color: Color(0xFF9E9E9E)),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final online = _devices.where((d) => d.online).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      body: Column(
        children: [
          _Header(
            online: online,
            total: _devices.length,
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // Summary row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      _SummaryChip(
                        label: '$online Online',
                        icon: Icons.wifi_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _SummaryChip(
                        label: '${_devices.length - online} Offline',
                        icon: Icons.wifi_off_rounded,
                        color: const Color(0xFF6B7A6B),
                      ),
                      const SizedBox(width: 8),
                      _SummaryChip(
                        label:
                            '${_devices.where((d) => d.battery < 0.2).length} Low Battery',
                        icon: Icons.battery_alert_rounded,
                        color: const Color(0xFFB71C1C),
                      ),
                    ],
                  ),
                ),

                ...(_devices.map((d) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: _DeviceCard(data: d),
                    ))),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Pair New Device',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int online;
  final int total;
  final VoidCallback onBack;

  const _Header(
      {required this.online, required this.total, required this.onBack});

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
        padding: EdgeInsets.only(
            top: topPad + 12, bottom: 24, left: 16, right: 16),
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
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Connected Sensors',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFB9F474),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$online/$total Active',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Monitor and manage your paired sensor nodes.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary Chip ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Device Card ──────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final _DeviceData data;
  const _DeviceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final batteryColor = data.battery < 0.2
        ? const Color(0xFFB71C1C)
        : data.battery < 0.5
            ? const Color(0xFFE65100)
            : AppColors.primary;

    final batteryIcon = data.battery < 0.2
        ? Icons.battery_alert_rounded
        : data.battery < 0.5
            ? Icons.battery_2_bar_rounded
            : Icons.battery_full_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: data.online
              ? const Color(0xFFBFCABA)
              : const Color(0xFFFFCDD2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + name + status
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: data.iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: data.iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        data.serial,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF6B7A6B),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: data.online
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: data.online
                              ? AppColors.primary
                              : const Color(0xFFB71C1C),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        data.online ? 'Online' : 'Offline',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: data.online
                              ? AppColors.primary
                              : const Color(0xFFB71C1C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Field + type pill row
            Row(
              children: [
                _InfoPill(
                  icon: Icons.map_rounded,
                  label: data.field,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                _InfoPill(
                  icon: Icons.sensors_rounded,
                  label: data.type,
                  color: const Color(0xFF1565C0),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Divider
            const Divider(height: 1, color: Color(0xFFEEF1ED)),
            const SizedBox(height: 12),

            // Live readings
            Row(
              children: data.readings
                  .map((r) => Expanded(
                        child: _ReadingBlock(reading: r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),

            // Bottom row: battery + signal + last seen
            Row(
              children: [
                Icon(batteryIcon, size: 15, color: batteryColor),
                const SizedBox(width: 4),
                Text(
                  data.batteryLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: batteryColor,
                  ),
                ),
                const SizedBox(width: 12),
                _SignalBars(strength: data.signalStrength),
                const SizedBox(width: 6),
                Text(
                  data.online ? 'Good signal' : 'No signal',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7A6B),
                  ),
                ),
                const Spacer(),
                Icon(Icons.access_time_rounded,
                    size: 12, color: const Color(0xFF9E9E9E)),
                const SizedBox(width: 4),
                Text(
                  data.lastSeen,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingBlock extends StatelessWidget {
  final _Reading reading;
  const _ReadingBlock({required this.reading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reading.label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7A6B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          reading.value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: reading.color,
          ),
        ),
      ],
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int strength; // 0–3
  const _SignalBars({required this.strength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final active = i < strength;
        final h = 6.0 + i * 3.0;
        return Container(
          width: 4,
          height: h,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active
                ? (strength == 1
                    ? const Color(0xFFB71C1C)
                    : AppColors.primary)
                : const Color(0xFFDDE1DA),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Reading {
  final String label;
  final String value;
  final Color color;
  const _Reading(
      {required this.label, required this.value, required this.color});
}

class _DeviceData {
  final String name;
  final String serial;
  final String field;
  final String type;
  final IconData icon;
  final Color iconColor;
  final double battery;
  final String batteryLabel;
  final int signalStrength;
  final bool online;
  final String lastSeen;
  final List<_Reading> readings;

  const _DeviceData({
    required this.name,
    required this.serial,
    required this.field,
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.battery,
    required this.batteryLabel,
    required this.signalStrength,
    required this.online,
    required this.lastSeen,
    required this.readings,
  });
}
