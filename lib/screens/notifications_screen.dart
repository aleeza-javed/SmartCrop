import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'sensor_alert_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_NotifData> _notifications = [
    _NotifData(
      id: 1,
      type: _NotifType.critical,
      title: 'Low Nitrogen Alert — Sector A-12',
      body: 'Nitrogen levels at 38 ppm, below the 60 ppm threshold for Winter Wheat tillering stage.',
      time: '10m ago',
      isRead: false,
      isToday: true,
    ),
    _NotifData(
      id: 2,
      type: _NotifType.recommendation,
      title: 'Irrigation Recommended',
      body: 'Soil moisture dropped to 21% in North Field. Irrigate within 6 hours for optimal crop health.',
      time: '1h ago',
      isRead: false,
      isToday: true,
    ),
    _NotifData(
      id: 3,
      type: _NotifType.system,
      title: 'Sensor Online — Moisture-X Hub',
      body: 'Your sensor node SN:8821-449-1 is now active and transmitting data.',
      time: '3h ago',
      isRead: true,
      isToday: true,
    ),
    _NotifData(
      id: 4,
      type: _NotifType.summary,
      title: 'Weekly Field Summary',
      body: 'Total water usage decreased by 14% this week. Soil health index improved by 0.3 points.',
      time: 'Yesterday',
      isRead: true,
      isToday: false,
    ),
    _NotifData(
      id: 5,
      type: _NotifType.pest,
      title: 'Pest Risk Detected',
      body: 'Satellite analysis indicates early-stage fungal growth risk in East Field. Inspect recommended.',
      time: '2 days ago',
      isRead: true,
      isToday: false,
    ),
    _NotifData(
      id: 6,
      type: _NotifType.recommendation,
      title: 'Fertilization Window Open',
      body: 'Weather forecast shows clear skies for 48 hours. Ideal window to apply scheduled fertilizer.',
      time: '3 days ago',
      isRead: true,
      isToday: false,
    ),
  ];

  void _markAllRead() {
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
  }

  void _markRead(int id) {
    setState(() {
      _notifications.firstWhere((n) => n.id == id).isRead = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final today = _notifications.where((n) => n.isToday).toList();
    final earlier = _notifications.where((n) => !n.isToday).toList();
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      body: Column(
        children: [
          _Header(
            unreadCount: unreadCount,
            onBack: () => Navigator.pop(context),
            onMarkAll: _markAllRead,
          ),
          Expanded(
            child: _notifications.isEmpty
                ? const _EmptyState()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      if (today.isNotEmpty) ...[
                        _SectionLabel(label: 'Today'),
                        ...today.map((n) => _NotifTile(
                              data: n,
                              onTap: () => _onTap(n),
                            )),
                      ],
                      if (earlier.isNotEmpty) ...[
                        _SectionLabel(label: 'Earlier'),
                        ...earlier.map((n) => _NotifTile(
                              data: n,
                              onTap: () => _onTap(n),
                            )),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _onTap(_NotifData notif) {
    _markRead(notif.id);
    if (notif.type == _NotifType.critical) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SensorAlertDetailScreen()),
      );
    }
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onBack;
  final VoidCallback onMarkAll;

  const _Header({
    required this.unreadCount,
    required this.onBack,
    required this.onMarkAll,
  });

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
                    'Notifications',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (unreadCount > 0)
                  GestureDetector(
                    onTap: onMarkAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Mark all read',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Stay updated with your field health.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB71C1C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadCount unread',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF6B7A6B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Notification Tile ────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final _NotifData data;
  final VoidCallback onTap;

  const _NotifTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cfg = _notifConfig(data.type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: data.isRead ? Colors.white : const Color(0xFFF0FAF0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: data.isRead
                ? const Color(0xFFBFCABA)
                : cfg.borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread accent bar
            if (!data.isRead)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: cfg.accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cfg.iconBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(cfg.icon, color: cfg.iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  data.title,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: data.isRead
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                data.time,
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  color: const Color(0xFF6B7A6B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            data.body,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF4A5568),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _TypeBadge(label: cfg.badgeLabel, color: cfg.accentColor, bg: cfg.iconBg),
                              const Spacer(),
                              if (data.type == _NotifType.critical)
                                _ActionChip(
                                  label: 'View Details',
                                  color: cfg.accentColor,
                                  onTap: onTap,
                                ),
                              if (data.type == _NotifType.recommendation &&
                                  data.title.contains('Irrigation'))
                                _ActionChip(
                                  label: 'Irrigate Now',
                                  color: cfg.accentColor,
                                  onTap: () {},
                                ),
                            ],
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
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _TypeBadge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                size: 36,
                color: AppColors.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'All caught up!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No new alerts for your farm at the moment.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7A6B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data & Config ────────────────────────────────────────────────────────────

enum _NotifType { critical, recommendation, system, summary, pest }

class _NotifData {
  final int id;
  final _NotifType type;
  final String title;
  final String body;
  final String time;
  bool isRead;
  final bool isToday;

  _NotifData({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    required this.isRead,
    required this.isToday,
  });
}

class _NotifConfig {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color accentColor;
  final Color borderColor;
  final String badgeLabel;

  const _NotifConfig({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.accentColor,
    required this.borderColor,
    required this.badgeLabel,
  });
}

_NotifConfig _notifConfig(_NotifType type) {
  switch (type) {
    case _NotifType.critical:
      return const _NotifConfig(
        icon: Icons.warning_rounded,
        iconColor: Color(0xFFB71C1C),
        iconBg: Color(0xFFFFEBEE),
        accentColor: Color(0xFFB71C1C),
        borderColor: Color(0xFFFFCDD2),
        badgeLabel: 'CRITICAL',
      );
    case _NotifType.recommendation:
      return _NotifConfig(
        icon: Icons.lightbulb_rounded,
        iconColor: AppColors.primary,
        iconBg: const Color(0xFFE8F5E9),
        accentColor: AppColors.primary,
        borderColor: const Color(0xFFC8E6C9),
        badgeLabel: 'RECOMMENDATION',
      );
    case _NotifType.system:
      return const _NotifConfig(
        icon: Icons.router_rounded,
        iconColor: Color(0xFF1565C0),
        iconBg: Color(0xFFE3F2FD),
        accentColor: Color(0xFF1565C0),
        borderColor: Color(0xFFBBDEFB),
        badgeLabel: 'SYSTEM',
      );
    case _NotifType.summary:
      return const _NotifConfig(
        icon: Icons.analytics_rounded,
        iconColor: Color(0xFF00796B),
        iconBg: Color(0xFFE0F2F1),
        accentColor: Color(0xFF00796B),
        borderColor: Color(0xFFB2DFDB),
        badgeLabel: 'WEEKLY SUMMARY',
      );
    case _NotifType.pest:
      return const _NotifConfig(
        icon: Icons.pest_control_rounded,
        iconColor: Color(0xFFE65100),
        iconBg: Color(0xFFFFF3E0),
        accentColor: Color(0xFFE65100),
        borderColor: Color(0xFFFFE0B2),
        badgeLabel: 'PEST WARNING',
      );
  }
}
