import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sensor_data.dart';
import '../services/crop_api_service.dart';
import '../theme/app_colors.dart';

class FertilizerScreen extends StatefulWidget {
  final SensorData? sensorData;
  final String crop;
  const FertilizerScreen({super.key, this.sensorData, this.crop = 'wheat'});

  @override
  State<FertilizerScreen> createState() => _FertilizerScreenState();
}

class _FertilizerScreenState extends State<FertilizerScreen> {
  bool _loading = false;
  Map<String, FertilizerRecommendation>? _recommendations;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  Future<void> _fetchRecommendations() async {
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
      _recommendations = null;
      _error = null;
    });
    try {
      final recs = await CropApiService.getFertilizerRecommendations(
        crop: widget.crop,
        n: data.n,
        p: data.p,
        k: data.k,
      );
      setState(() {
        _recommendations = recs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load recommendations: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(topPad: MediaQuery.of(context).padding.top),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusOverviewCard(),
                  const SizedBox(height: 24),
                  _sectionTitle('Soil Alerts'),
                  const SizedBox(height: 12),
                  _buildAlertsSection(),
                  const SizedBox(height: 24),
                  _sectionTitle('Fertilizer Recommendations'),
                  const SizedBox(height: 12),
                  _buildRecommendationsSection(),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.outlineVariant, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Auto-Schedule Coming Soon',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onBackground,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'ML model will auto-generate weekly fertilizer plans based on live sensor data.',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
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
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorWidget(message: _error!);
    }
    if (_recommendations == null || _recommendations!.isEmpty) {
      return const Center(child: Text('No data available'));
    }
    return Column(
      children: _buildAlertCards(),
    );
  }

  List<Widget> _buildAlertCards() {
    final recs = _recommendations!;
    final widgets = <Widget>[];
    final nutrientLabels = {'N': 'Nitrogen', 'P': 'Phosphorus', 'K': 'Potassium'};
    final nutrientIcons = {'N': Icons.water_drop_outlined, 'P': Icons.science_outlined, 'K': Icons.eco_outlined};

    for (final entry in recs.entries) {
      final symbol = entry.key;
      final rec = entry.value;
      final label = nutrientLabels[symbol] ?? symbol;
      final icon = nutrientIcons[symbol] ?? Icons.science_outlined;

      _Severity severity;
      if (rec.status == 'deficient') {
        severity = _Severity.warning;
      } else if (rec.status == 'excess') {
        severity = _Severity.critical;
      } else {
        severity = _Severity.ok;
      }

      widgets.add(_AlertCard(
        icon: icon,
        title: rec.status == 'sufficient'
            ? '$label Adequate'
            : '$label ${rec.status.capitalize()}',
        detail: rec.advice,
        severity: severity,
      ));
      widgets.add(const SizedBox(height: 10));
    }
    return widgets;
  }

  Widget _buildRecommendationsSection() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorWidget(message: _error!);
    }
    if (_recommendations == null || _recommendations!.isEmpty) {
      return const Center(child: Text('No recommendations available'));
    }
    return Column(
      children: _buildRecommendationCards(),
    );
  }

  List<Widget> _buildRecommendationCards() {
    final recs = _recommendations!;
    final widgets = <Widget>[];
    final nutrientNames = {'N': 'Urea (46-0-0)', 'P': 'DAP (18-46-0)', 'K': 'Muriate of Potash (0-0-60)'};
    final nutrientColors = {'N': const Color(0xFF1565C0), 'P': const Color(0xFF2E7D32), 'K': const Color(0xFF6A1B9A)};

    for (final entry in recs.entries) {
      final symbol = entry.key;
      final rec = entry.value;
      if (rec.status == 'sufficient') continue;
      final priority = rec.status == 'deficient' ? _Priority.high : _Priority.medium;
      widgets.add(_FertilizerCard(
        name: nutrientNames[symbol] ?? symbol,
        purpose: '$symbol ${rec.status == 'deficient' ? 'Top-up' : 'Reduction'}',
        rate: rec.deficit != null
            ? '${rec.deficit!.toStringAsFixed(0)} kg/acre'
            : rec.surplus != null
                ? '${rec.surplus!.toStringAsFixed(0)} kg/acre'
                : 'As needed',
        timing: rec.status == 'deficient' ? 'Within 48 hours' : 'Monitor',
        priority: priority,
        icon: Icons.grain_rounded,
        iconColor: nutrientColors[symbol] ?? AppColors.primary,
      ));
      widgets.add(const SizedBox(height: 10));
    }
    if (widgets.isEmpty) {
      return const [
        _FertilizerCard(
          name: 'All Nutrients Balanced',
          purpose: 'No action needed',
          rate: '—',
          timing: '—',
          priority: _Priority.low,
          icon: Icons.check_circle_outline_rounded,
          iconColor: Color(0xFF2E7D32),
        ),
      ];
    }
    return widgets;
  }

  Text _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.onBackground,
        ),
      );
}

class _ErrorWidget extends StatelessWidget {
  final String message;
  const _ErrorWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
  final double topPad;
  const _Header({required this.topPad});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, topPad + 8, 16, 12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppColors.onBackground),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fertilizer Advisor',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'AI suggestions for your soil',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
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

class _StatusOverviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Overall Soil Health',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Live',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.74,
              minHeight: 8,
              backgroundColor: Color(0xFFE0E4D9),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Based on live sensor readings',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final _Severity severity;

  const _AlertCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.severity,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    switch (severity) {
      case _Severity.ok:
        bg = const Color(0xFFE8F5E9);
        fg = AppColors.primary;
        border = AppColors.primary.withValues(alpha: 0.25);
      case _Severity.warning:
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFF856404);
        border = const Color(0xFFFFE082);
      case _Severity.critical:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFBA1A1A);
        border = const Color(0xFFFFCDD2);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
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

class _FertilizerCard extends StatelessWidget {
  final String name;
  final String purpose;
  final String rate;
  final String timing;
  final _Priority priority;
  final IconData icon;
  final Color iconColor;

  const _FertilizerCard({
    required this.name,
    required this.purpose,
    required this.rate,
    required this.timing,
    required this.priority,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color pColor;
    final String pLabel;
    switch (priority) {
      case _Priority.high:
        pColor = const Color(0xFFBA1A1A);
        pLabel = 'High';
      case _Priority.medium:
        pColor = const Color(0xFFE65100);
        pLabel = 'Medium';
      case _Priority.low:
        pColor = AppColors.primary;
        pLabel = 'Low';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  purpose,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InfoChip(
                        icon: Icons.scale_outlined, label: rate),
                    const SizedBox(width: 6),
                    _InfoChip(
                        icon: Icons.calendar_today_outlined, label: timing),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: pColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              pLabel,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: pColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Severity { ok, warning, critical }

enum _Priority { high, medium, low }

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}