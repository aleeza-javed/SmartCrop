// Verifies the save-on-show path: exactly one history record per notification
// actually shown, and nothing recorded for alerts the monitor suppressed.
//
// The flutter_local_notifications platform channel is mocked, so no real
// notification is ever posted.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_crop/models/alert_rule.dart';
import 'package:smart_crop/models/sensor_data.dart';
import 'package:smart_crop/services/alert_monitor_service.dart';
import 'package:smart_crop/services/notification_history_service.dart';
import 'package:smart_crop/services/notification_service.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

final _shown = <MethodCall>[];
final _history = NotificationHistoryService.instance;

SensorData reading({
  double n = 118,
  double p = 61,
  double k = 45,
  double ph = 6.8,
  double airTemp = 17,
  double airHumidity = 60,
  double soilMoisture = 36,
}) =>
    SensorData(
      airHumidity: airHumidity,
      airTemp: airTemp,
      ec: 0,
      k: k,
      n: n,
      p: p,
      rainPercent: 0,
      soilHumidity: soilMoisture,
      soilMoisturePercent: soilMoisture,
      soilTemp: 0,
      pH: ph,
    );

const wheatCfg = {
  'N': {
    'min': 107.0,
    'max': 131.0,
    'buffer': 12.0,
    'unit': 'kg/ha',
    'label': 'Nitrogen',
    'fertilizer': 'nitrogen-based',
  },
  'P': {
    'min': 48.0,
    'max': 74.0,
    'buffer': 8.0,
    'unit': 'kg/ha',
    'label': 'Phosphorus',
    'fertilizer': 'phosphorus-based',
  },
  'K': {
    'min': 35.0,
    'max': 54.0,
    'buffer': 5.0,
    'unit': 'kg/ha',
    'label': 'Potassium',
    'fertilizer': 'potassium-based',
  },
  'ph': {'min': 6.3, 'max': 7.3, 'buffer': 0.4, 'unit': 'pH', 'label': 'Soil pH'},
  'soil_moisture': {
    'min': 27.0,
    'max': 46.0,
    'buffer': 10.0,
    'unit': '%',
    'label': 'Soil moisture',
  },
  'temperature': {
    'min': 14.4,
    'max': 20.2,
    'buffer': 3.0,
    'unit': 'degC',
    'label': 'Air temperature',
  },
  'humidity': {
    'min': 54.0,
    'max': 66.0,
    'buffer': 7.0,
    'unit': '%',
    'label': 'Relative humidity',
  },
};

List<AlertRule> wheatRules() => [
      for (final e in wheatCfg.entries)
        AlertRule.fromThreshold(e.key, e.value),
    ];

/// Exactly what dashboard_screen.dart::_checkThresholds does.
Future<void> run(AlertMonitorService m, SensorData d) async {
  final events = m.evaluate(d);
  if (events.isEmpty) return;
  await NotificationService.instance.showAll(events, crop: 'wheat');
}

int get _shownCount => _shown.where((c) => c.method == 'show').length;

Future<List<dynamic>> stored() async =>
    jsonDecode((await SharedPreferences.getInstance())
        .getString(NotificationHistoryService.storageKey) ??
        '[]') as List<dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // No native registrant under `flutter test`, and defaultTargetPlatform
    // follows the host OS, so both must be forced for the Android path.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() async {
    _shown.clear();
    SharedPreferences.setMockInitialValues({});
    _history.resetUnreadForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      _shown.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'requestNotificationsPermission') return true;
      return null;
    });
    NotificationService.instance.enabled = true;
    await NotificationService.instance.init();
    // Drain any op the previous test left queued, in the real zone.
    await _history.clearAll();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('one shown notification produces exactly one record', () async {
    final m = AlertMonitorService(rules: wheatRules());
    await run(m, reading());
    expect(_shownCount, 0);
    expect(await stored(), isEmpty);

    await run(m, reading(n: 90));
    expect(_shownCount, 1, reason: 'one tray notification');
    final saved = await stored();
    expect(saved.length, 1, reason: 'one history record');
    expect((saved.single as Map)['parameter'], 'N');
    expect((saved.single as Map)['direction'], 'low');
    expect((saved.single as Map)['crop'], 'Wheat');
  });

  test('a batch of two produces two records and two notifications', () async {
    final m = AlertMonitorService(rules: wheatRules());
    await run(m, reading());
    // N low and soil moisture high in the same reading.
    await run(m, reading(n: 90, soilMoisture: 80));

    expect(_shownCount, 2);
    final saved = await stored();
    expect(saved.length, 2);
    final dirs = saved.map((e) => (e as Map)['direction']).toSet();
    expect(dirs, {'low', 'high'});
  });

  test('a same-band repeat is neither shown nor saved', () async {
    final m = AlertMonitorService(rules: wheatRules());
    await run(m, reading());
    await run(m, reading(n: 90));
    expect(_shownCount, 1);
    final after = (await stored()).length;

    // Still in the same band, many times over.
    for (var i = 0; i < 30; i++) {
      await run(m, reading(n: 88 + i * 0.1));
    }
    expect(_shownCount, 1, reason: 'no further tray notifications');
    expect((await stored()).length, after,
        reason: 'no further history records');
  });

  test('an all-zero reading is never shown or saved', () async {
    final m = AlertMonitorService(rules: wheatRules());
    const zero = SensorData(
      airHumidity: 0,
      airTemp: 0,
      ec: 0,
      k: 0,
      n: 0,
      p: 0,
      rainPercent: 0,
      soilHumidity: 0,
      soilMoisturePercent: 0,
      soilTemp: 0,
      pH: 0,
    );
    for (var i = 0; i < 10; i++) {
      await run(m, zero);
    }
    expect(_shownCount, 0, reason: 'reset sensor must not alert');
    expect(await stored(), isEmpty);
  });

  test('a recovery is shown and saved with direction recovered', () async {
    final m = AlertMonitorService(rules: wheatRules());
    await run(m, reading());
    await run(m, reading(n: 90));
    await run(m, reading(n: 118));

    final saved = await stored();
    final rec = saved.first as Map;
    expect(rec['direction'], 'recovered');
    expect(rec['severity'], 'normal');
    expect(rec['crop'], 'Wheat');
    expect(rec['title'], contains('Wheat'));
  });

  test('a disabled service neither shows nor saves', () async {
    final svc = NotificationService.instance;
    svc.enabled = false;
    addTearDown(() => svc.enabled = true);

    final m = AlertMonitorService(rules: wheatRules());
    await run(m, reading());
    await run(m, reading(n: 90));

    expect(_shownCount, 0);
    expect(await stored(), isEmpty);
  });
}
