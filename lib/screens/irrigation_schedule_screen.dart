import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class IrrigationScheduleScreen extends StatefulWidget {
  const IrrigationScheduleScreen({super.key});

  @override
  State<IrrigationScheduleScreen> createState() => _IrrigationScheduleScreenState();
}

class _IrrigationScheduleScreenState extends State<IrrigationScheduleScreen> {
  bool _autoPilot = true;
  int _selectedDay = 0;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dates = ['12', '13', '14', '15', '16', '17', '18'];

  static const _schedules = [
    _ScheduleItem(
      field: 'Main Field',
      timeRange: '06:00 – 07:30 AM',
      volume: '4,200 L',
      type: 'Drip',
      typeIcon: Icons.water_drop_rounded,
      typeColor: Color(0xFF1565C0),
      day: 0,
    ),
    _ScheduleItem(
      field: 'North Field',
      timeRange: '10:15 – 11:00 AM',
      volume: '1,500 L',
      type: 'Sprinkler',
      typeIcon: Icons.shower_rounded,
      typeColor: Color(0xFF00796B),
      day: 0,
    ),
    _ScheduleItem(
      field: 'South Field',
      timeRange: '02:45 – 03:15 PM',
      volume: '850 L',
      type: 'Micro-spray',
      typeIcon: Icons.blur_on_rounded,
      typeColor: Color(0xFF6A1B9A),
      day: 1,
    ),
    _ScheduleItem(
      field: 'East Field',
      timeRange: '08:00 – 09:30 PM',
      volume: '3,100 L',
      type: 'Flooding',
      typeIcon: Icons.waves_rounded,
      typeColor: Color(0xFFE65100),
      day: 2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final daySchedules = _schedules.where((s) => s.day == _selectedDay).toList();
    final totalLiters = daySchedules.fold<int>(
      0,
      (sum, s) => sum + int.parse(s.volume.replaceAll(RegExp(r'[^0-9]'), '')),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // Auto-pilot toggle
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _AutoPilotCard(
                    enabled: _autoPilot,
                    onChanged: (v) => setState(() => _autoPilot = v),
                  ),
                ),
                const SizedBox(height: 16),

                // Weather adaptation notice
                if (_autoPilot)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _WeatherAdaptationCard(),
                  ),
                if (_autoPilot) const SizedBox(height: 16),

                // Day selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DaySelector(
                    days: _days,
                    dates: _dates,
                    selected: _selectedDay,
                    onSelect: (i) => setState(() => _selectedDay = i),
                  ),
                ),
                const SizedBox(height: 16),

                // Schedule items
                if (daySchedules.isEmpty)
                  const _EmptyDay()
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Scheduled Tasks',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${daySchedules.length} tasks',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF6B7A6B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...daySchedules.map((s) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _ScheduleCard(item: s),
                      )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TotalVolumeCard(liters: totalLiters),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Create Schedule',
          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

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
                  child: Text(
                    'Irrigation Schedule',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Optimize hydration with AI-driven precision.',
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

// ─── Auto-Pilot Card ──────────────────────────────────────────────────────────

class _AutoPilotCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _AutoPilotCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)])
            : null,
        color: enabled ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? Colors.transparent : const Color(0xFFBFCABA),
        ),
        boxShadow: [
          BoxShadow(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: enabled ? Colors.white : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Pilot Mode',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  enabled ? 'AI is managing your schedules' : 'Manage schedules manually',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: enabled ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF6B7A6B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: enabled ? Colors.white : AppColors.primary,
            activeTrackColor: enabled
                ? Colors.white.withValues(alpha: 0.35)
                : AppColors.primary.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

// ─── Weather Adaptation Card ──────────────────────────────────────────────────

class _WeatherAdaptationCard extends StatelessWidget {
  const _WeatherAdaptationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_rounded, color: Color(0xFFFFA000), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weather Adaptation Active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A3000),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Reduced watering by 15% due to forecasted precipitation on Wednesday afternoon.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B5000),
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

// ─── Day Selector ─────────────────────────────────────────────────────────────

class _DaySelector extends StatelessWidget {
  final List<String> days;
  final List<String> dates;
  final int selected;
  final ValueChanged<int> onSelect;

  const _DaySelector({
    required this.days,
    required this.dates,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(days.length, (i) {
          final isSelected = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    days[i],
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF6B7A6B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dates[i],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Schedule Card ────────────────────────────────────────────────────────────

class _ScheduleCard extends StatelessWidget {
  final _ScheduleItem item;
  const _ScheduleCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(item.typeIcon, color: item.typeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.field,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 11, color: const Color(0xFF6B7A6B)),
                    const SizedBox(width: 4),
                    Text(
                      item.timeRange,
                      style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF6B7A6B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.volume,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: item.typeColor,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: item.typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.type,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: item.typeColor,
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

// ─── Total Volume Card ────────────────────────────────────────────────────────

class _TotalVolumeCard extends StatelessWidget {
  final int liters;
  const _TotalVolumeCard({required this.liters});

  @override
  Widget build(BuildContext context) {
    final formatted = liters.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Text(
            'Estimated Total Volume',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          Text(
            '$formatted L',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty Day ────────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No schedules',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 6),
          Text(
            'No irrigation tasks for this day.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF6B7A6B)),
          ),
        ],
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _ScheduleItem {
  final String field;
  final String timeRange;
  final String volume;
  final String type;
  final IconData typeIcon;
  final Color typeColor;
  final int day;

  const _ScheduleItem({
    required this.field,
    required this.timeRange,
    required this.volume,
    required this.type,
    required this.typeIcon,
    required this.typeColor,
    required this.day,
  });
}
