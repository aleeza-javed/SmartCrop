import 'package:flutter_test/flutter_test.dart';
import 'package:smart_crop/models/alert_rule.dart';
import 'package:smart_crop/models/sensor_data.dart';
import 'package:smart_crop/services/alert_monitor_service.dart';

/// Builds a reading. Named params default to healthy values so each test
/// only states the parameter it is exercising.
SensorData reading({
  double n = 60,
  double p = 30,
  double k = 90,
  double ph = 6.8,
  double airTemp = 24,
  double airHumidity = 60,
  double soilMoisture = 55,
  double soilTemp = 22,
  double ec = 1.0,
}) {
  return SensorData(
    airHumidity: airHumidity,
    airTemp: airTemp,
    ec: ec,
    k: k,
    n: n,
    p: p,
    rainPercent: 0,
    soilHumidity: soilMoisture,
    soilMoisturePercent: soilMoisture,
    soilTemp: soilTemp,
    pH: ph,
  );
}

void main() {
  group('AlertRule.classify', () {
    final moisture = defaultAlertRules.firstWhere(
      (r) => r.key == 'soil_moisture',
    ); // 40-70 %, buffer 10

    test('inside range is normal', () {
      expect(moisture.classify(55), AlertStatus.normal);
      expect(moisture.classify(40), AlertStatus.normal);
      expect(moisture.classify(70), AlertStatus.normal);
    });

    test('just outside range is warning', () {
      expect(moisture.classify(39), AlertStatus.warning);
      expect(moisture.classify(71), AlertStatus.warning);
      expect(moisture.classify(30), AlertStatus.warning);
      expect(moisture.classify(80), AlertStatus.warning);
    });

    test('beyond buffer is critical', () {
      expect(moisture.classify(29.9), AlertStatus.critical);
      expect(moisture.classify(12), AlertStatus.critical);
      expect(moisture.classify(95), AlertStatus.critical);
    });
  });

  group('AlertMonitorService', () {
    test('first healthy reading is a silent baseline', () {
      final monitor = AlertMonitorService();
      expect(monitor.evaluate(reading()), isEmpty);
      expect(monitor.statusOf('soil_moisture'), AlertStatus.normal);
    });

    test('all-zero reading from a disconnected node is ignored', () {
      final monitor = AlertMonitorService();
      final empty = const SensorData(
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
      // Must not raise nine "critically deficient" alerts at once.
      expect(empty.isEmpty, isTrue);
      expect(monitor.evaluate(empty), isEmpty);
      expect(monitor.statusOf('N'), isNull);
    });

    test('alerts on crossing into a band, not on staying there', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());

      // 35 is inside the warning band (30-40) for the 40-70 % rule.
      final first = monitor.evaluate(reading(soilMoisture: 35));
      expect(first.map((e) => e.rule.key), ['soil_moisture']);
      expect(first.single.status, AlertStatus.warning);
      expect(first.single.previous, AlertStatus.normal);

      // Still in the same band: no further alerts, however many readings.
      for (var i = 0; i < 20; i++) {
        expect(monitor.evaluate(reading(soilMoisture: 34 - i * 0.1)), isEmpty);
      }
    });

    test('escalation warning -> critical fires', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());
      monitor.evaluate(reading(soilMoisture: 35));

      final events = monitor.evaluate(reading(soilMoisture: 10));
      expect(events.single.status, AlertStatus.critical);
      expect(events.single.previous, AlertStatus.warning);
      expect(events.single.isEscalation, isTrue);
      expect(events.single.isRecovery, isFalse);
    });

    test('recovery fires once, then goes quiet', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());
      monitor.evaluate(reading(soilMoisture: 35));

      final recovered = monitor.evaluate(reading(soilMoisture: 55));
      expect(recovered.single.status, AlertStatus.normal);
      expect(recovered.single.isRecovery, isTrue);
      expect(recovered.single.recommendation,
          contains('back within its acceptable range'));

      expect(monitor.evaluate(reading(soilMoisture: 56)), isEmpty);
    });

    test('critical on the very first reading is reported', () {
      final monitor = AlertMonitorService();
      final events = monitor.evaluate(reading(soilMoisture: 8));
      expect(events.single.rule.key, 'soil_moisture');
      expect(events.single.status, AlertStatus.critical);
    });

    test('first reading that is only a warning is not reported', () {
      final monitor = AlertMonitorService();
      expect(monitor.evaluate(reading(soilMoisture: 35)), isEmpty);
      expect(monitor.statusOf('soil_moisture'), AlertStatus.warning);
    });

    test('multiple parameters crossing at once all fire', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());

      final events = monitor.evaluate(reading(n: 2, k: 200, soilMoisture: 10));
      expect(events.length, 3);
      expect(events.map((e) => e.rule.key).toSet(),
          {'N', 'K', 'soil_moisture'});
    });

    test('activeIssues lists what is currently out of range', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());
      monitor.evaluate(reading(soilMoisture: 35, n: 5));
      monitor.evaluate(reading(soilMoisture: 36, n: 5));

      final active = monitor.activeIssues.map((e) => e.rule.key).toSet();
      expect(active, {'soil_moisture', 'N'});
    });

    test('reset re-baselines on the next reading', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading());
      monitor.evaluate(reading(soilMoisture: 35));
      expect(monitor.statusOf('soil_moisture'), AlertStatus.warning);

      monitor.reset();
      expect(monitor.statusOf('soil_moisture'), isNull);
      expect(monitor.evaluate(reading(soilMoisture: 32)), isEmpty);
    });
  });

  group('AlertEvent text', () {
    AlertEvent eventFor(String key, Map<String, dynamic> cfg, double value,
        {AlertStatus? status, AlertStatus? previous}) {
      final rule = AlertRule.fromThreshold(key, cfg);
      return AlertEvent(
        rule: rule,
        value: value,
        status: status ?? rule.classify(value),
        previous: previous ?? AlertStatus.normal,
        at: DateTime(2026),
      );
    }

    test('low nitrogen gives a recommendation, not a reading', () {
      final e = eventFor('N', const {
        'min': 107.0,
        'max': 131.0,
        'buffer': 12.0,
        'unit': 'kg/ha',
        'label': 'Nitrogen',
        'fertilizer': 'nitrogen-based',
      }, 40);

      expect(e.title, 'Nitrogen critical');
      expect(e.recommendation,
          'Nitrogen is below its acceptable range. Inspect the soil and '
          'consider an appropriate nitrogen-based fertilizer after field '
          'assessment.');

      // The measured value and the band must not appear in the text.
      expect(e.recommendation, isNot(contains('40')));
      expect(e.recommendation, isNot(contains('107')));
      expect(e.recommendation, isNot(contains('kg/ha')));
    });

    test('high potassium advises against more application', () {
      final e = eventFor('K', const {
        'min': 35.0,
        'max': 54.0,
        'buffer': 5.0,
        'unit': 'kg/ha',
        'label': 'Potassium',
        'fertilizer': 'potassium-based',
      }, 70);

      // 70 is past 54 + 5, so it is critical rather than a warning.
      expect(e.title, 'Potassium critical');
      expect(e.recommendation,
          'Potassium is above its acceptable range. Avoid applying more and '
          'inspect field conditions.');
      expect(e.recommendation, isNot(contains('70')));
    });

    test('low soil moisture routes to water management, not a fertilizer', () {
      final e = eventFor('soil_moisture', const {
        'min': 27.0,
        'max': 46.0,
        'buffer': 10.0,
        'unit': '%',
        'label': 'Soil moisture',
      }, 12);

      expect(e.title, 'Soil moisture critical');
      expect(e.recommendation,
          'Soil moisture is below its acceptable range. Inspect field '
          'conditions and review water management / irrigation after field '
          'assessment.');
      expect(e.recommendation, isNot(contains('fertilizer')));
    });

    test('recovery text names the parameter and clears the warning', () {
      final e = eventFor('N', const {
        'min': 107.0,
        'max': 131.0,
        'buffer': 12.0,
        'label': 'Nitrogen',
        'fertilizer': 'nitrogen-based',
      }, 120,
          status: AlertStatus.normal,
          previous: AlertStatus.warning);
      // Coming from a warning is what makes this a recovery, not a no-op.
      expect(e.isRecovery, isTrue);
      expect(e.title, 'Nitrogen recovered');
      expect(e.recommendation,
          'Nitrogen is back within its acceptable range.');
    });
  });

  group('backend-derived rules', () {
    // Real entry from crop_thresholds.py for wheat.
    const wheatN = {
      'min': 107.0,
      'max': 131.0,
      'buffer': 12.0,
      'unit': 'kg/ha',
      'label': 'Nitrogen',
      'fertilizer': 'nitrogen-based',
      'derived_from': 'training dataset (mean +/- 1 std)',
    };

    test('uses the backend band, not the generic fallback', () {
      final rule = AlertRule.fromThreshold('N', wheatN);
      // Generic fallback would call 100 a warning (20-120). Wheat's real band
      // is 107-131, so 100 is a deficiency.
      expect(rule.min, 107);
      expect(rule.max, 131);
      expect(rule.classify(100), AlertStatus.warning);
      expect(rule.classify(60), AlertStatus.critical); // past 107 - 12
      expect(rule.label, 'Nitrogen');
      expect(rule.fertilizer, 'nitrogen-based');
    });

    test('backend params map onto the right sensor fields', () {
      final rules = {
        for (final e in {
          'N': wheatN,
          'P': const {
            'min': 48.0,
            'max': 74.0,
            'buffer': 8.0,
            'label': 'Phosphorus'
          },
          'temperature': const {
            'min': 14.4,
            'max': 20.2,
            'buffer': 3.0,
            'label': 'Air temperature'
          },
          'humidity': const {
            'min': 54.0,
            'max': 66.0,
            'buffer': 7.0,
            'label': 'Relative humidity'
          },
          'ph': const {'min': 6.3, 'max': 7.3, 'buffer': 0.4, 'label': 'Soil pH'},
          'soil_moisture': const {
            'min': 27.0,
            'max': 46.0,
            'buffer': 10.0,
            'label': 'Soil moisture'
          },
        }.entries)
          e.key: AlertRule.fromThreshold(e.key, e.value),
      };

      // Distinct values per field, so a mis-wired accessor is unambiguous.
      final data = reading(
        n: 118,
        p: 61,
        airTemp: 24,
        airHumidity: 60,
        ph: 6.8,
        soilMoisture: 55,
      );

      // Backend key -> the sensor field it must read from.
      expect(rules['N']!.read(data), 118);
      expect(rules['P']!.read(data), 61);
      expect(rules['temperature']!.read(data), 24); // from airTemp
      expect(rules['humidity']!.read(data), 60);
      expect(rules['ph']!.read(data), 6.8);
      expect(rules['soil_moisture']!.read(data), 55);

      // And those values land in the band each wheat config implies.
      expect(rules['N']!.classify(118), AlertStatus.normal); // 107-131
      expect(rules['P']!.classify(61), AlertStatus.normal); // 48-74
      expect(rules['ph']!.classify(6.8), AlertStatus.normal); // 6.3-7.3
      expect(rules['temperature']!.classify(24), AlertStatus.critical); // 14.4-20.2
      expect(rules['soil_moisture']!.classify(55), AlertStatus.warning); // 27-46 + 10
    });

    test('an unreported parameter is skipped, never alerted on', () {
      // soilTemp is not a CROP_THRESHOLDS key, so it must not be watched.
      final monitor = AlertMonitorService(rules: [
        AlertRule.fromThreshold('soil_moisture', const {
          'min': 27.0,
          'max': 46.0,
          'buffer': 10.0,
          'label': 'Soil moisture',
        }),
      ]);
      expect(sensorValueFor(reading(), 'soil_temp').isNaN, isTrue);
      expect(sensorValueFor(reading(soilMoisture: 70), 'soil_moisture'),
          70.0);
      // 70 is past 46 + 10, so the first reading is already critical.
      final events = monitor.evaluate(reading(soilMoisture: 70));
      expect(events.single.rule.key, 'soil_moisture');
      expect(events.single.status, AlertStatus.critical);
    });

    test('setRules swaps bands and re-baselines', () {
      final monitor = AlertMonitorService();
      monitor.evaluate(reading(n: 60));
      expect(monitor.statusOf('N'), AlertStatus.normal);

      // 60 is fine generically but far below wheat's 107-131.
      monitor.setRules([AlertRule.fromThreshold('N', wheatN)]);
      expect(monitor.statusOf('N'), isNull);
      final events = monitor.evaluate(reading(n: 60));
      expect(events.single.rule.key, 'N');
      expect(events.single.status, AlertStatus.critical);
    });
  });
}
