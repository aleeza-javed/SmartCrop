import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/alert_rule.dart';
import '../models/notification_record.dart';
import 'notification_history_service.dart';

/// Delivers threshold alerts as Android system notifications.
///
/// Scope and limits, stated plainly:
///
/// * Local only. These fire on-device from the Firebase sensor stream, so
///   they work while the app is open or backgrounded. They do *not* fire
///   when the app is force-stopped - that needs FCM, which the Flask
///   backend has no support for.
/// * The sensor stream is owned by `DashboardScreen`, so nothing is
///   evaluated until the user has signed in and the dashboard is mounted.
/// * [FlutterLocalNotificationsPlugin.initialize] and `.show` both no-op on
///   web, and every call here is guarded, so the web build is unaffected.
///
/// Two channels keep the two situations separable in system settings:
/// an urgent one for critical readings and a quiet one for recoveries, so a
/// return to normal never makes a noise.
class NotificationService {
  static final NotificationService instance = NotificationService._();

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Set false to mute all alerts without tearing down the plugin. Backed by
  /// SharedPreferences via the app's existing storage conventions, and
  /// defaulted to on so alerts work with no setup.
  bool enabled = true;

  static const String _alertChannelId = 'smartcrop_alerts';
  static const String _recoveryChannelId = 'smartcrop_recovery';

  static const AndroidNotificationDetails _alertDetails =
      AndroidNotificationDetails(
    _alertChannelId,
    'Crop alerts',
    channelDescription:
        'Soil moisture, N, P, K and other readings leaving their safe range.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.recommendation,
  );

  static const AndroidNotificationDetails _recoveryDetails =
      AndroidNotificationDetails(
    _recoveryChannelId,
    'Resolved alerts',
    channelDescription: 'Readings that returned to their safe range.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: false,
    enableVibration: false,
  );

  /// Initialises the plugin and, on Android 13+, asks for the runtime
  /// notification permission. Safe to call more than once.
  ///
  /// [onTap] runs when the user taps a tray notification, which is how the
  /// history screen gets opened from outside the app. Supplied by `main.dart`
  /// so this service stays free of any dependency on a screen.
  ///
  /// Returns false when notifications could not be enabled, which is the
  /// normal outcome on web and the case where the user has permanently
  /// denied the permission.
  Future<bool> init({void Function()? onTap}) async {
    if (_initialized || kIsWeb) return _initialized;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: onTap == null
            ? null
            : (NotificationResponse response) => onTap(),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService: init failed: $e');
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return await requestPermission();
    }
    return true;
  }

  /// Asks for POST_NOTIFICATIONS. Returns the granted state; a null result
  /// means the platform did not report one.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
      return false;
    }
  }

  /// Posts one alert and records it in the history.
  ///
  /// Errors are logged rather than thrown: a failed notification must never
  /// break the sensor stream that called it.
  ///
  /// [crop] is the active crop. `AlertEvent` cannot carry it, so the caller
  /// supplies it; it is prefixed onto the title so a user running several
  /// fields can tell the notifications apart.
  ///
  /// The history write sits behind the same `_initialized` / `enabled` guards
  /// as the tray call, and after it succeeds, so nothing that was suppressed -
  /// nor anything the tray failed to show - is recorded.
  Future<void> showAlert(AlertEvent event, {String? crop}) async {
    if (!_initialized || !enabled) return;

    final record = NotificationRecord.fromEvent(event, crop: crop);

    try {
      await _plugin.show(
        _idFor(event.rule.key),
        record.title,
        record.body,
        NotificationDetails(
          android: event.isRecovery ? _recoveryDetails : _alertDetails,
        ),
        payload: event.rule.key,
      );
      await NotificationHistoryService.instance.add(record);
    } catch (e) {
      debugPrint('NotificationService: show failed: $e');
    }
  }

  /// Posts a batch, most severe first so the critical reading is the one the
  /// user notices.
  Future<void> showAll(Iterable<AlertEvent> events, {String? crop}) async {
    final ordered = events.toList()
      ..sort((a, b) => b.status.weight.compareTo(a.status.weight));
    for (final event in ordered) {
      await showAlert(event, crop: crop);
    }
  }

  /// Stable per-parameter id, so a parameter's notifications replace each
  /// other in the shade rather than stacking up.
  int _idFor(String key) => key.hashCode & 0x7fffffff;
}
