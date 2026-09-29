import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_crop/models/alert_rule.dart';
import 'package:smart_crop/models/notification_record.dart';
import 'package:smart_crop/models/sensor_data.dart';
import 'package:smart_crop/services/notification_history_service.dart';

final _history = NotificationHistoryService.instance;

NotificationRecord rec({
  String id = 'r1',
  String crop = 'Wheat',
  String parameter = 'N',
  String direction = 'low',
  String severity = 'critical',
  double? measured = 90,
  DateTime? at,
  bool isRead = false,
}) =>
    NotificationRecord(
      id: id,
      title: '$crop · Nitrogen critical',
      body: 'Nitrogen is below its acceptable range.',
      crop: crop,
      parameter: parameter,
      parameterLabel: 'Nitrogen',
      direction: direction,
      severity: severity,
      measured: measured,
      unit: 'kg/ha',
      idealMin: 107,
      idealMax: 131,
      timestamp: at ?? DateTime(2026, 9, 29, 8, 30),
      isRead: isRead,
    );

/// A real AlertEvent, to prove `fromEvent` derives direction correctly.
AlertEvent eventFor(double n, {String? previous, String? crop}) {
  final rule = AlertRule.fromThreshold('N', const {
    'min': 107.0,
    'max': 131.0,
    'buffer': 12.0,
    'unit': 'kg/ha',
    'label': 'Nitrogen',
    'fertilizer': 'nitrogen-based',
  });
  return AlertEvent(
    rule: rule,
    value: n,
    status: rule.classify(n),
    previous: previous == null
        ? null
        : (previous == 'normal'
            ? AlertStatus.normal
            : previous == 'warning'
                ? AlertStatus.warning
                : AlertStatus.critical),
    at: DateTime(2026, 9, 29, 9, 15),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _history.resetUnreadForTest();
    await _history.clearAll();
  });

  group('add and ordering', () {
    test('a new record is unread and appears first', () async {
      await _history.add(rec(id: 'a', at: DateTime(2026, 9, 29, 9)));
      expect(_history.unreadCount.value, 1);

      final all = await _history.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'a');
      expect(all.first.isRead, isFalse);
    });

    test('newest first regardless of insertion order', () async {
      await _history.add(rec(id: 'old', at: DateTime(2026, 9, 27, 9)));
      await _history.add(rec(id: 'new', at: DateTime(2026, 9, 29, 9)));
      await _history.add(rec(id: 'mid', at: DateTime(2026, 9, 28, 9)));

      final ids = (await _history.getAll()).map((r) => r.id).toList();
      expect(ids, ['new', 'mid', 'old']);
    });
  });

  group('cap at 200', () {
    test('keeps 200 and drops the oldest', () async {
      // Identical timestamps: the later insert must count as newer, so the
      // last 50 written are the ones dropped.
      for (var i = 0; i < 250; i++) {
        await _history.add(rec(id: 'id$i'));
      }
      final all = await _history.getAll();
      expect(all, hasLength(200));
      expect(all.first.id, 'id249');
      expect(all.last.id, 'id50');
      expect(all.any((r) => r.id == 'id0'), isFalse);
    });

    test('distinct increasing timestamps keep the newest 200', () async {
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < 250; i++) {
        await _history.add(rec(id: 'id$i', at: base.add(Duration(minutes: i))));
      }
      final all = await _history.getAll();
      expect(all, hasLength(200));
      expect(all.first.id, 'id249');
      expect(all.last.id, 'id50');
    });
  });

  group('read state', () {
    test('markAllRead clears the unread count and persists', () async {
      await _history.add(rec(id: 'a'));
      await _history.add(rec(id: 'b'));
      expect(_history.unreadCount.value, 2);

      await _history.markAllRead();
      expect(_history.unreadCount.value, 0);

      // Re-read from storage, not memory.
      final all = await _history.getAll();
      expect(all.every((r) => r.isRead), isTrue);
    });

    test('markRead affects only the named record', () async {
      await _history.add(rec(id: 'a'));
      await _history.add(rec(id: 'b'));
      await _history.markRead('a');

      final all = await _history.getAll();
      expect(all.firstWhere((r) => r.id == 'a').isRead, isTrue);
      expect(all.firstWhere((r) => r.id == 'b').isRead, isFalse);
      expect(_history.unreadCount.value, 1);
    });

    test('already-read records are not double counted', () async {
      await _history.add(rec(id: 'a', isRead: true));
      await _history.add(rec(id: 'b'));
      expect(_history.unreadCount.value, 1);
    });
  });

  group('delete and clear', () {
    test('delete removes one record', () async {
      await _history.add(rec(id: 'a'));
      await _history.add(rec(id: 'b'));
      await _history.delete('a');

      final all = await _history.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'b');
      expect(_history.unreadCount.value, 1);
    });

    test('deleting an unknown id is a no-op, not a crash', () async {
      await _history.add(rec(id: 'a'));
      await _history.delete('does-not-exist');
      expect((await _history.getAll()).length, 1);
    });

    test('clearAll empties the list and the count', () async {
      await _history.add(rec(id: 'a'));
      await _history.add(rec(id: 'b'));
      await _history.clearAll();
      expect(await _history.getAll(), isEmpty);
      expect(_history.unreadCount.value, 0);
    });
  });

  group('corrupt storage', () {
    test('non-JSON payload is discarded, not fatal', () async {
      SharedPreferences.setMockInitialValues(
          {NotificationHistoryService.storageKey: 'not json at all'});
      expect(await _history.getAll(), isEmpty);
      expect(_history.unreadCount.value, 0);

      // And the app can carry on writing afterwards.
      await _history.add(rec(id: 'a'));
      expect((await _history.getAll()).length, 1);
    });

    test('wrong top-level shape is discarded', () async {
      SharedPreferences.setMockInitialValues(
          {NotificationHistoryService.storageKey: '{"not": "a list"}'});
      expect(await _history.getAll(), isEmpty);
    });

    test('individual bad rows are skipped, good rows survive', () async {
      SharedPreferences.setMockInitialValues({
        NotificationHistoryService.storageKey: '[null, 42, "text", '
            '{"id":"good","title":"t","crop":"Wheat","parameter":"N",'
            '"direction":"low","severity":"critical","timestamp":'
            '"2026-09-29T09:00:00.000Z","measured":90}]'
      });
      final all = await _history.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'good');
      expect(all.first.measured, 90);
    });

    test('a record missing optional fields still parses', () async {
      SharedPreferences.setMockInitialValues({
        NotificationHistoryService.storageKey:
            '[{"id":"x","title":"t","timestamp":"2026-09-29T09:00:00.000Z"}]'
      });
      final all = await _history.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'x');
      expect(all.first.measured, isNull);
      expect(all.first.isRead, isFalse);
    });
  });

  group('fromEvent', () {
    test('below min gives direction low', () {
      final r = NotificationRecord.fromEvent(eventFor(90), crop: 'wheat');
      expect(r.direction, 'low');
      expect(r.crop, 'Wheat');
      expect(r.title, 'Wheat · Nitrogen critical');
      expect(r.parameter, 'N');
      expect(r.parameterLabel, 'Nitrogen');
      expect(r.severity, 'critical');
      expect(r.measured, 90);
      expect(r.idealMin, 107);
      expect(r.idealMax, 131);
      expect(r.measuredVsIdeal, '90 kg/ha (ideal 107-131)');
    });

    test('above max gives direction high', () {
      final r = NotificationRecord.fromEvent(eventFor(200), crop: 'wheat');
      expect(r.direction, 'high');
      expect(r.severity, 'critical');
    });

    test('a recovery is direction recovered and severity normal', () {
      final r = NotificationRecord.fromEvent(
        eventFor(120, previous: 'warning'),
        crop: 'maize',
      );
      expect(r.direction, 'recovered');
      expect(r.severity, 'normal');
      expect(r.title, 'Maize · Nitrogen recovered');
    });

    test('no crop leaves the title unprefixed', () {
      final r = NotificationRecord.fromEvent(eventFor(90));
      expect(r.crop, '');
      expect(r.title, 'Nitrogen critical');
    });

    test('ids are unique across same-millisecond events', () {
      final at = DateTime(2026, 9, 29, 9);
      final a = NotificationRecord.fromEvent(eventFor(90), crop: 'wheat');
      final b = NotificationRecord.fromEvent(eventFor(90), crop: 'wheat');
      expect(a.id, b.id); // same event, same id

      final other = AlertEvent(
        rule: AlertRule.fromThreshold('P', const {
          'min': 48.0,
          'max': 74.0,
          'buffer': 8.0,
          'label': 'Phosphorus',
        }),
        value: 10,
        status: AlertStatus.critical,
        previous: AlertStatus.normal,
        at: at,
      );
      expect(NotificationRecord.fromEvent(other).id, isNot(a.id));
    });

    test('round-trips through JSON', () {
      final original = NotificationRecord.fromEvent(eventFor(90), crop: 'wheat');
      final back =
          NotificationRecord.fromJson(original.toJson());
      expect(back.id, original.id);
      expect(back.title, original.title);
      expect(back.crop, original.crop);
      expect(back.direction, original.direction);
      expect(back.severity, original.severity);
      expect(back.measured, original.measured);
      expect(back.idealMin, original.idealMin);
      expect(back.timestamp.toUtc().millisecondsSinceEpoch,
          original.timestamp.toUtc().millisecondsSinceEpoch);
    });
  });

  group('SensorData guard (unchanged)', () {
    test('all-zero readings are still recognised as absent', () {
      const empty = SensorData(
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
      expect(empty.isEmpty, isTrue);
    });
  });
}
