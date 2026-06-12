import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'add_field_screen.dart';
import 'field_detail_screen.dart';

class MyFieldsScreen extends StatefulWidget {
  const MyFieldsScreen({super.key});

  @override
  State<MyFieldsScreen> createState() => _MyFieldsScreenState();
}

class _MyFieldsScreenState extends State<MyFieldsScreen> {
  String _search = '';

  static const _fields = [
    _FieldData(
      name: 'Main Field',
      location: 'Sector A-12, Faisalabad',
      crop: 'Wheat (Gehun)',
      cropIcon: Icons.grass_rounded,
      area: '5.2 acres',
      moisture: 64,
      healthScore: 92,
      status: _FieldStatus.healthy,
      phase: 'Tillering',
    ),
    _FieldData(
      name: 'North Field',
      location: 'Sector B-04, Faisalabad',
      crop: 'Cotton (Kapas)',
      cropIcon: Icons.yard_rounded,
      area: '3.8 acres',
      moisture: 12,
      healthScore: 78,
      status: _FieldStatus.critical,
      phase: 'Boll Formation',
    ),
    _FieldData(
      name: 'South Field',
      location: 'Sector C-09, Faisalabad',
      crop: 'Sugarcane (Ganna)',
      cropIcon: Icons.eco_rounded,
      area: '7.1 acres',
      moisture: 58,
      healthScore: 89,
      status: _FieldStatus.healthy,
      phase: 'Grand Growth',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final filtered = _search.isEmpty
        ? _fields
        : _fields
            .where((f) =>
                f.name.toLowerCase().contains(_search.toLowerCase()) ||
                f.crop.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFCABA)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1A1A1A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search fields or crops...',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: const Color(0xFF9E9E9E),
                        ),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: const Color(0xFF9E9E9E), size: 20),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                // Summary row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      _SummaryChip(
                        label: '${_fields.length} Fields',
                        icon: Icons.map_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _SummaryChip(
                        label:
                            '${_fields.where((f) => f.status == _FieldStatus.healthy).length} Healthy',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _SummaryChip(
                        label:
                            '${_fields.where((f) => f.status == _FieldStatus.critical).length} Critical',
                        icon: Icons.warning_rounded,
                        color: const Color(0xFFB71C1C),
                      ),
                    ],
                  ),
                ),

                if (filtered.isEmpty)
                  const _EmptySearch()
                else
                  ...filtered.map((f) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _FieldCard(data: f),
                      )),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddFieldScreen()),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_location_alt_rounded, size: 20),
        label: Text(
          'Add New Field',
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
                    'My Fields',
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
            const SizedBox(height: 14),
            Text(
              'Manage and monitor your active cultivation zones.',
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

// ─── Field Card ───────────────────────────────────────────────────────────────

class _FieldCard extends StatelessWidget {
  final _FieldData data;
  const _FieldCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final statusCfg = _statusConfig(data.status);
    final moistureColor = data.moisture < 20
        ? const Color(0xFFB71C1C)
        : data.moisture < 40
            ? const Color(0xFFE65100)
            : AppColors.primary;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map placeholder strip
          Container(
            height: 90,
            decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                children: [
                  CustomPaint(
                    painter: _FieldMapPainter(),
                    child: Container(),
                  ),
                  Positioned(
                    top: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            data.location,
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusCfg.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusCfg.label,
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + area
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A1A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.area,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Crop + phase
                Row(
                  children: [
                    Icon(data.cropIcon,
                        size: 14, color: const Color(0xFF6B7A6B)),
                    const SizedBox(width: 5),
                    Text(
                      data.crop,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4A5568),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      data.phase,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6B7A6B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Moisture + Health
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        label: 'Moisture',
                        value: '${data.moisture}%',
                        valueColor: moistureColor,
                        sub: data.moisture < 20
                            ? 'Critical'
                            : data.moisture < 40
                                ? 'Low'
                                : 'Optimal',
                        subColor: moistureColor,
                      ),
                    ),
                    Container(
                        width: 1,
                        height: 36,
                        color: const Color(0xFFEEF1ED)),
                    Expanded(
                      child: _MetricBlock(
                        label: 'Health Score',
                        value: '${data.healthScore}/100',
                        valueColor: data.healthScore >= 85
                            ? AppColors.primary
                            : const Color(0xFFE65100),
                        sub: data.healthScore >= 85 ? 'Good' : 'Fair',
                        subColor: data.healthScore >= 85
                            ? AppColors.primary
                            : const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Moisture bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: data.moisture / 100,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFEEF1ED),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(moistureColor),
                  ),
                ),
                const SizedBox(height: 14),

                // View Details button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FieldDetailScreen(
                          fieldName: data.name,
                          crop: data.crop,
                          area: data.area,
                          location: data.location,
                          healthScore: data.healthScore,
                          moisture: data.moisture,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: Text(
                      'View Details',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
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

class _MetricBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String sub;
  final Color subColor;
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.sub,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7A6B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          Text(
            sub,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Field Map Painter ────────────────────────────────────────────────────────

class _FieldMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF3D6B47),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Field boundary
    final border = Paint()
      ..color = const Color(0xFFB9F474).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTRB(size.width * 0.1, size.height * 0.2,
          size.width * 0.9, size.height * 0.85),
      border,
    );
    canvas.drawRect(
      Rect.fromLTRB(size.width * 0.1, size.height * 0.2,
          size.width * 0.9, size.height * 0.85),
      Paint()..color = const Color(0xFFB9F474).withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Empty Search ─────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No fields found',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different field name or crop.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF6B7A6B),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

enum _FieldStatus { healthy, warning, critical }

class _StatusConfig {
  final String label;
  final Color color;
  const _StatusConfig({required this.label, required this.color});
}

_StatusConfig _statusConfig(_FieldStatus s) {
  switch (s) {
    case _FieldStatus.healthy:
      return _StatusConfig(label: 'HEALTHY', color: AppColors.primary);
    case _FieldStatus.warning:
      return const _StatusConfig(
          label: 'WARNING', color: Color(0xFFE65100));
    case _FieldStatus.critical:
      return const _StatusConfig(
          label: 'CRITICAL', color: Color(0xFFB71C1C));
  }
}

class _FieldData {
  final String name;
  final String location;
  final String crop;
  final IconData cropIcon;
  final String area;
  final int moisture;
  final int healthScore;
  final _FieldStatus status;
  final String phase;

  const _FieldData({
    required this.name,
    required this.location,
    required this.crop,
    required this.cropIcon,
    required this.area,
    required this.moisture,
    required this.healthScore,
    required this.status,
    required this.phase,
  });
}
