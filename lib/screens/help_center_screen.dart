import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  String _search = '';
  final Set<int> _expanded = {};

  static const _featured = [
    _FeaturedTopic(
      icon: Icons.sensors_rounded,
      iconColor: Color(0xFF1565C0),
      title: 'Pairing your first sensor',
      subtitle: 'Step-by-step guide for SmartCrop Field-A hardware',
      category: 'Setup Guides',
    ),
    _FeaturedTopic(
      icon: Icons.science_rounded,
      iconColor: Color(0xFF00796B),
      title: 'Understanding NPK alerts',
      subtitle: 'Interpret nitrogen, phosphorus & potassium data',
      category: 'Analytics',
    ),
    _FeaturedTopic(
      icon: Icons.water_drop_rounded,
      iconColor: Color(0xFF1565C0),
      title: 'Managing irrigation zones',
      subtitle: 'Configure and automate your watering schedules',
      category: 'Water Management',
    ),
  ];

  static const _categories = [
    _FaqCategory(
      title: 'Setup Guides',
      icon: Icons.build_rounded,
      color: Color(0xFF1565C0),
      items: [
        _FaqItem(q: 'How do I pair my first sensor?', a: 'Go to Sensors tab → tap "Pair Device" → follow the 3-step pairing wizard: Power on, Scan, and Configure.'),
        _FaqItem(q: 'What sensors does SmartCrop support?', a: 'SmartCrop supports soil moisture, NPK, pH, temperature, light intensity, and water flow sensors via Bluetooth Low Energy.'),
        _FaqItem(q: 'How do I add a new field?', a: 'From the dashboard, tap the "Add Field" button or go to Profile → My Fields → Add New Field.'),
      ],
    ),
    _FaqCategory(
      title: 'Troubleshooting',
      icon: Icons.warning_rounded,
      color: Color(0xFFE65100),
      items: [
        _FaqItem(q: 'My sensor shows offline. What should I do?', a: 'Check the battery level, ensure Bluetooth is enabled, and try re-pairing. If the issue persists, restart the device.'),
        _FaqItem(q: 'Why are my NPK readings incorrect?', a: 'Calibrate the sensor probe. Ensure it is inserted at least 10cm deep in moist (not waterlogged) soil.'),
        _FaqItem(q: 'The app is not showing real-time data.', a: 'Pull to refresh or check your internet connection. Sensor data syncs every 5 minutes by default.'),
      ],
    ),
    _FaqCategory(
      title: 'App Features',
      icon: Icons.apps_rounded,
      color: Color(0xFF6A1B9A),
      items: [
        _FaqItem(q: 'What does the AI Recommendation do?', a: 'The AI analyses your soil data, weather forecast, and crop stage to suggest optimal fertilization, irrigation, and pest control actions.'),
        _FaqItem(q: 'How do I set irrigation schedules?', a: 'Go to Irrigation → Irrigation Schedule → Create New Schedule. You can also enable Auto-Pilot Mode for AI-driven scheduling.'),
        _FaqItem(q: 'Can I export my farm reports?', a: 'Yes. Go to Reports tab → tap the share icon to export as PDF or CSV.'),
      ],
    ),
    _FaqCategory(
      title: 'Subscription',
      icon: Icons.star_rounded,
      color: Color(0xFFFFA000),
      items: [
        _FaqItem(q: 'What is included in the free plan?', a: 'The free plan includes up to 1 field, 2 sensors, basic AI recommendations, and 7-day data history.'),
        _FaqItem(q: 'How do I upgrade to SmartCrop Pro?', a: 'Go to Profile → Subscription → Upgrade. Pro includes unlimited fields, sensors, advanced AI, and 1-year history.'),
      ],
    ),
  ];

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
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFCABA)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search guides, troubleshooting tips...',
                        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF9E9E9E)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9E9E9E), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Featured topics
                if (_search.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Featured Topics',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _featured.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _FeaturedCard(topic: _featured[i]),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // FAQ categories
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _search.isEmpty ? 'Browse Topics' : 'Search Results',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                const SizedBox(height: 10),

                ..._categories.map((cat) {
                  final idx = _categories.indexOf(cat);
                  final filteredItems = _search.isEmpty
                      ? cat.items
                      : cat.items.where((item) =>
                          item.q.toLowerCase().contains(_search.toLowerCase()) ||
                          item.a.toLowerCase().contains(_search.toLowerCase())).toList();
                  if (filteredItems.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _CategoryAccordion(
                      category: cat,
                      filteredItems: filteredItems,
                      isExpanded: _expanded.contains(idx),
                      onToggle: () => setState(() {
                        if (_expanded.contains(idx)) {
                          _expanded.remove(idx);
                        } else {
                          _expanded.add(idx);
                        }
                      }),
                    ),
                  );
                }),

                const SizedBox(height: 10),

                // Contact support
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _ContactSection(),
                ),
                const SizedBox(height: 16),

                // Community
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _CommunitySection(),
                ),
              ],
            ),
          ),
        ],
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
                    'Help Center',
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
              'Guides, troubleshooting & precision farming insights.',
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

// ─── Featured Card ────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final _FeaturedTopic topic;
  const _FeaturedCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: topic.iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(topic.icon, color: topic.iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            topic.title,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            topic.category,
            style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: topic.iconColor),
          ),
        ],
      ),
    );
  }
}

// ─── Category Accordion ───────────────────────────────────────────────────────

class _CategoryAccordion extends StatelessWidget {
  final _FaqCategory category;
  final List<_FaqItem> filteredItems;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CategoryAccordion({
    required this.category,
    required this.filteredItems,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFCABA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(category.icon, color: category.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.title,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${filteredItems.length}',
                      style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: category.color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF6B7A6B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFEEF1ED)),
            ...filteredItems.map((item) => _FaqTile(item: item)),
          ],
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: Text('Q', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.q,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              item.a,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF4A5568), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEEF1ED)),
          const SizedBox(height: 0),
        ],
      ),
    );
  }
}

// ─── Contact Section ──────────────────────────────────────────────────────────

class _ContactSection extends StatelessWidget {
  const _ContactSection();

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
          Text(
            'Contact Support',
            style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Our agronomy experts are here to help.',
            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7A6B)),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: _ContactOption(icon: Icons.chat_rounded, label: 'Live Chat', badge: 'Fast', color: Color(0xFF2E7D32))),
              SizedBox(width: 10),
              Expanded(child: _ContactOption(icon: Icons.email_rounded, label: 'Email', badge: null, color: Color(0xFF1565C0))),
              SizedBox(width: 10),
              Expanded(child: _ContactOption(icon: Icons.phone_rounded, label: 'Call Us', badge: null, color: Color(0xFF00796B))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final Color color;

  const _ContactOption({required this.icon, required this.label, this.badge, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
            if (badge != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text(badge!, style: GoogleFonts.manrope(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Community Section ────────────────────────────────────────────────────────

class _CommunitySection extends StatelessWidget {
  const _CommunitySection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SmartCrop Farmer Community',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  'Join thousands of farmers sharing insights.',
                  style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Join',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _FeaturedTopic {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String category;
  const _FeaturedTopic({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.category});
}

class _FaqCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_FaqItem> items;
  const _FaqCategory({required this.title, required this.icon, required this.color, required this.items});
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}
