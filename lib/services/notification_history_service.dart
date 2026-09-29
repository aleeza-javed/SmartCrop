import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_record.dart';

/// Persists the full notification history in SharedPreferences as one JSON
/// array, newest first.
///
/// Mirrors the shape of the existing services in this project: a static
/// instance, plain async methods, SharedPreferences underneath. No new
/// packages.
///
/// Every mutation goes through [_serialize] so concurrent calls (an alert
/// arriving while the history screen is deleting something) cannot interleave
/// a read-modify-write and lose an entry.
///
/// Corrupt stored data is never fatal: a bad top-level value is discarded, and
/// individual unreadable entries are skipped so one bad row cannot take the
/// whole history with it.
class NotificationHistoryService {
  static final NotificationHistoryService instance =
      NotificationHistoryService._();

  NotificationHistoryService._();

  static const String storageKey = 'notification_history_v1';

  /// Hard cap. Oldest records past this point are dropped.
  static const int maxRecords = 200;

  /// Live unread count. The dashboard badge listens to this.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Serialises all writes so a read-modify-write can't interleave.
  Future<void> _queue = Future<void>.value();

  /// Appends [record] and refreshes [unreadCount].
  ///
  /// Only called for notifications that were actually shown - the caller sits
  /// behind the same guards as the tray call, so suppressed readings (zero
  /// readings, same-band repeats) never reach this.
  ///
  /// The list is re-sorted by timestamp rather than simply prepended, so
  /// "newest first" holds even if a record is written out of order (a stale
  /// timestamp from a delayed evaluation, or a clock adjustment). Ties keep
  /// insertion order, since `List.sort` is not stable and would otherwise
  /// reshuffle the list on every write.
  Future<void> add(NotificationRecord record) {
    return _enqueue(() async {
      final all = await _read();

      // Assign the next sequence. Doing it here rather than deriving it from
      // list position keeps the ordering permanent once written.
      var highest = 0;
      for (final r in all) {
        if (r.sequence > highest) highest = r.sequence;
      }
      all.add(record.copyWith(sequence: highest + 1));

      all.sort((a, b) {
        final byTime = b.timestamp.compareTo(a.timestamp);
        return byTime != 0 ? byTime : b.sequence.compareTo(a.sequence);
      });

      if (all.length > maxRecords) {
        all.removeRange(maxRecords, all.length);
      }
      await _write(all);
    });
  }

  /// All records, newest first.
  Future<List<NotificationRecord>> getAll() => _read();

  Future<void> markAllRead() {
    return _enqueue(() async {
      final all = await _read();
      final changed = all.any((r) => !r.isRead);
      if (!changed) return;
      await _write([for (final r in all) r.copyWith(isRead: true)]);
    });
  }

  Future<void> markRead(String id) {
    return _enqueue(() async {
      final all = await _read();
      final next = [
        for (final r in all) r.id == id ? r.copyWith(isRead: true) : r,
      ];
      await _write(next);
    });
  }

  Future<void> delete(String id) {
    return _enqueue(() async {
      final all = await _read();
      all.removeWhere((r) => r.id == id);
      await _write(all);
    });
  }

  Future<void> clearAll() {
    return _enqueue(() async {
      await _write(const []);
    });
  }

  /// Recomputes [unreadCount] from storage. Call once at startup so a relaunch
  /// shows the right badge before any alert fires.
  Future<void> refreshUnreadCount() async {
    final all = await _read();
    _publish(all);
  }

  /// Test seam: resets the notifier without touching storage.
  @visibleForTesting
  void resetUnreadForTest() => unreadCount.value = 0;

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<List<NotificationRecord>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _publish(const []);
      return [];
    }

    List<dynamic> decoded;
    try {
      decoded = json.decode(raw) as List<dynamic>;
    } catch (_) {
      // Corrupt payload: drop it rather than crashing on every launch.
      debugPrint(
          'NotificationHistoryService: discarding unreadable history');
      await prefs.remove(storageKey);
      _publish(const []);
      return [];
    }

    final records = <NotificationRecord>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        records.add(
            NotificationRecord.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip a single bad row; keep the rest.
        continue;
      }
    }

    _publish(records);
    return records;
  }

  Future<void> _write(List<NotificationRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(
          storageKey, json.encode([for (final r in records) r.toJson()]));
    } catch (e) {
      debugPrint('NotificationHistoryService: write failed: $e');
    }
    _publish(records);
  }

  void _publish(List<NotificationRecord> records) {
    final count = records.where((r) => !r.isRead).length;
    if (unreadCount.value != count) unreadCount.value = count;
  }
}
