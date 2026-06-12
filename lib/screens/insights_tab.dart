import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'ai_crop_screen.dart';
import 'fertilizer_screen.dart';
import 'irrigation_screen.dart';

class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Insights',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ML-powered predictions for your field',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          // ── Crop Prediction card ──
          _InsightEntryCard(
            title: 'AI Crop Prediction',
            subtitle: 'Find the best crop for your current soil conditions',
            icon: Icons.eco_rounded,
            iconBg: const Color(0xFF1B5E20),
            badge: 'Wheat · 92% Match',
            badgeColor: AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiCropScreen()),
            ),
          ),
          const SizedBox(height: 14),

          // ── Fertilizer Advisor card ──
          _InsightEntryCard(
            title: 'Fertilizer Advisor',
            subtitle: 'Get AI suggestions when soil nutrients are off-balance',
            icon: Icons.science_rounded,
            iconBg: const Color(0xFF6A1B9A),
            badge: '1 Alert',
            badgeColor: const Color(0xFF856404),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FertilizerScreen()),
            ),
          ),
          const SizedBox(height: 14),

          // ── Irrigation Scheduler card ──
          _InsightEntryCard(
            title: 'Irrigation Scheduler',
            subtitle: 'Auto-schedule irrigation based on soil moisture & weather',
            icon: Icons.water_drop_rounded,
            iconBg: const Color(0xFF0D47A1),
            badge: 'Zone B Active',
            badgeColor: Color(0xFF1565C0),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IrrigationScreen()),
            ),
          ),
          const SizedBox(height: 32),

          // ── Coming soon section ──
          Text(
            'Coming Soon',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 10),
          _ComingSoonCard(
            icon: Icons.pest_control_rounded,
            title: 'Pest & Disease Predictor',
            subtitle: 'Early warning system trained on regional outbreak data',
          ),
          const SizedBox(height: 10),
          _ComingSoonCard(
            icon: Icons.trending_up_rounded,
            title: 'Yield Forecaster',
            subtitle: 'Predict expected yield based on current field conditions',
          ),
        ],
      ),
    );
  }
}

// ─── Entry Card ───────────────────────────────────────────────────────────────

class _InsightEntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _InsightEntryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onBackground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}

// ─── Coming Soon Card ─────────────────────────────────────────────────────────

class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(icon, color: AppColors.outline, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Soon',
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.outline,
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
