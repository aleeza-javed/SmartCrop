import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/notification_record.dart';
import '../services/notification_history_service.dart';
import '../theme/app_colors.dart';

/// Full history of every notification the app has raised, newest first,
/// grouped by day.
///
/// Backed by `NotificationHistoryService`. This is the only notifications
/// screen: the earlier "current alerts only" view was removed.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static final _history = NotificationHistoryService.instance;

  List<NotificationRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _history.getAll();
    if (!mounted) return;
    setState(() {
      _records = all;
      _loading = false;
    });
  }

  /// Opening the screen counts as reading it, so the unread badge clears when
  /// the user leaves. Done in [dispose] rather than on open, which keeps the
  /// unread styling visible for as long as the list is on screen, and means it
  /// works however the screen was opened (bell, tray tap, deep link).
  @override
  void dispose() {
    _history.markAllRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final groups = _groupByDay(_records);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            topPad: topPad,
            count: _records.length,
            onClear: _records.isEmpty ? null : _confirmClearAll,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const _EmptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          for (final entry in groups.entries) ...[
                            _DayHeader(label: entry.key),
                            const SizedBox(height: 10),
                            for (final record in entry.value)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _NotificationCard(
                                  record: record,
                                  onDelete: () => _delete(record),
                                ),
                              ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(NotificationRecord record) async {
    await _history.delete(record.id);
    if (!mounted) return;
    setState(() => _records = _records.where((r) => r.id != record.id).toList());
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear all notifications?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        content: Text(
          'This permanently removes all ${_records.length} notification '
          '${_records.length == 1 ? 'entry' : 'entries'} from this device.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Clear all',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _history.clearAll();
    if (!mounted) return;
    setState(() => _records = const []);
  }

  /// Groups into Today / Yesterday / d MMM yyyy, preserving input order so
  /// newest stays first.
  static Map<String, List<NotificationRecord>> _groupByDay(
    List<NotificationRecord> records,
  ) {
    final groups = <String, List<NotificationRecord>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final r in records) {
      final d = r.timestamp;
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      final label = diff == 0
          ? 'Today'
          : diff == 1
              ? 'Yesterday'
              : '${d.day} ${_months[d.month - 1]} ${d.year}';
      groups.putIfAbsent(label, () => []).add(r);
    }
    return groups;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

// ─── Header ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final double topPad;
  final int count;
  final VoidCallback? onClear;

  const _Header({
    required this.topPad,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, topPad + 8, 8, 12),
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
                  'Notifications',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  count == 0
                      ? 'No alerts yet'
                      : '$count alert${count == 1 ? '' : 's'} recorded',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            TextButton(
              onPressed: onClear,
              child: Text(
                'Clear all',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Day header ──────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final NotificationRecord record;
  final VoidCallback onDelete;

  const _NotificationCard({required this.record, required this.onDelete});

  static const _criticalBg = Color(0xFFFFEBEE);
  static const _criticalFg = Color(0xFFBA1A1A);
  static const _warningBg = Color(0xFFFFF8E1);
  static const _warningFg = Color(0xFF856404);
  static const _recoveredBg = Color(0xFFE8F5E9);
  static const _recoveredFg = Color(0xFF2E7D32);

  Color get _bg => switch (record.severity) {
        'critical' => _criticalBg,
        'normal' => _recoveredBg,
        _ => _warningBg,
      };

  Color get _fg => switch (record.severity) {
        'critical' => _criticalFg,
        'normal' => _recoveredFg,
        _ => _warningFg,
      };

  IconData get _icon => switch (record.severity) {
        'critical' => Icons.error_outline_rounded,
        'normal' => Icons.check_circle_outline_rounded,
        _ => Icons.warning_amber_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final range = record.measuredVsIdeal;

    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: record.isRead ? Colors.white : _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: record.isRead ? AppColors.outlineVariant : _fg.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_icon, color: _fg, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight:
                                record.isRead ? FontWeight.w600 : FontWeight.w700,
                            color: AppColors.onBackground,
                          ),
                        ),
                      ),
                      if (!record.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record.body,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (range != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.straighten_rounded,
                              size: 10, color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            range,
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _relativeTime(record.timestamp),
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `just now` / `12m ago` / `3h ago` / `5d ago`, then an absolute date.
  static String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${when.day}/${when.month}/${when.year}';
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              'No notifications yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Alerts about soil moisture, N, P and K will appear here once '
              'a reading leaves its ideal range.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
