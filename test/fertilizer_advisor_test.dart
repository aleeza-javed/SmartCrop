import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_crop/models/sensor_data.dart';
import 'package:smart_crop/models/sensor_reading.dart';
import 'package:smart_crop/screens/fertilizer_screen.dart';
import 'package:smart_crop/services/crop_api_service.dart';

/// ── fixtures ──────────────────────────────────────────────────────────────

SensorData reading({double n = 119, double p = 61, double k = 45}) => SensorData(
      airHumidity: 60,
      airTemp: 18,
      ec: 1.0,
      k: k,
      n: n,
      p: p,
      rainPercent: 0,
      soilHumidity: 40,
      soilMoisturePercent: 38,
      soilTemp: 20,
      pH: 6.8,
    );

Map<String, dynamic> nutrientJson({
  String parameter = 'N',
  String label = 'Nitrogen',
  String unit = 'ppm',
  List<num> band = const [107, 131],
  num? buffer = 12,
  num? current,
  String status = 'NORMAL',
  bool? required,
  String? direction,
  num? gap,
  num? nutrientKgHa,
  num? productKgHa,
  Map<String, dynamic>? product,
  String? advice,
  String confidence = 'instant',
  String persistence = 'unavailable',
}) =>
    {
      'parameter': parameter,
      'label': label,
      'unit': unit,
      'band': band,
      'buffer': buffer,
      'current': current,
      'status': status,
      'required': required,
      'direction': direction,
      'gap': gap,
      'nutrient_kg_ha': nutrientKgHa,
      'product_kg_ha': productKgHa,
      'product': product,
      'advice': advice ??
          (status == 'NORMAL'
              ? '$label is within the configured range.'
              : ''),
      'confidence': confidence,
      'persistence': persistence,
    };

Map<String, dynamic> reportJson({
  Map<String, dynamic>? nutrients,
  int score = 100,
  bool partial = false,
  int requiredCount = 0,
  bool stale = false,
  num? readingAgeSeconds,
  String persistence = 'unavailable',
  String confidence = 'instant',
}) =>
    {
      'crop': 'wheat',
      'source': 'crop_thresholds',
      'stale': stale,
      'reading_age_seconds': readingAgeSeconds,
      'stale_after_seconds': 600,
      'health': {
        'score': score,
        'score_out_of': 100,
        'status': score == 100 ? 'NORMAL' : 'WARNING',
        'partial': partial,
        'evaluated': ['N', 'P', 'K'],
        'label': 'SmartCrop Monitoring Health Score',
        'note': partial ? 'Prototype metric. Partial: N only.' : 'Prototype.',
      },
      'summary': {
        'required_count': requiredCount,
        'within_range': const ['N', 'P', 'K'],
        'no_reading': const <String>[],
      },
      'nutrients': nutrients ??
          {
            'N': nutrientJson(
                current: 119, gap: 0, confidence: confidence, persistence: persistence),
            'P': nutrientJson(
              parameter: 'P',
              label: 'Phosphorus',
              band: const [48, 74],
              buffer: 8,
              current: 61,
              confidence: confidence,
              persistence: persistence,
            ),
            'K': nutrientJson(
              parameter: 'K',
              label: 'Potassium',
              band: const [35, 54],
              buffer: 5,
              current: 45,
              confidence: confidence,
              persistence: persistence,
            ),
          },
    };

FertilizerReport reportFrom(Map<String, dynamic> json) =>
    FertilizerReport.fromJson(json);

/// Asserts no estimated amount is offered.
///
/// The footnote legitimately contains "kg/ha", so absence is asserted on the
/// chip wording and product names an amount would produce, not on the unit.
void expectNoAmountOffered(WidgetTester tester) {
  expect(find.textContaining('About '), findsNothing);
  for (final product in ['Urea', 'DAP', 'Muriate']) {
    expect(find.textContaining(product), findsNothing);
  }
}

/// ── model parsing ─────────────────────────────────────────────────────────

void main() {
  group('FertilizerReport.fromJson', () {
    test('parses a deficient nutrient with its estimate', () {
      final report = reportFrom(reportJson(
        score: 92,
        requiredCount: 1,
        nutrients: {
          'N': nutrientJson(
            current: 100,
            status: 'WARNING',
            required: true,
            direction: 'deficient',
            gap: 7,
            nutrientKgHa: 14.0,
            productKgHa: 30.4,
            product: const {
              'fertilizer': 'nitrogen-based',
              'name': 'Urea (46-0-0)',
              'role': 'Quick top-up',
              'nutrient_fraction': 0.46,
            },
            advice: 'Nitrogen is 7.0 ppm below the configured range. '
                'Estimated about 30.4 kg/ha of Urea (46-0-0) needed to reach '
                'the range.',
          ),
        },
      ));

      final n = report.nutrients['N']!;
      expect(n.status, FertilizerStatus.warning);
      expect(n.required, isTrue);
      expect(n.needsAction, isTrue);
      expect(n.isDeficient, isTrue);
      expect(n.isExcess, isFalse);
      expect(n.isNoReading, isFalse);
      expect(n.unit, 'ppm');
      expect(n.band, [107.0, 131.0]);
      expect(n.buffer, 12.0);
      expect(n.current, 100.0);
      expect(n.gap, 7.0);
      expect(n.nutrientKgHa, 14.0);
      expect(n.productKgHa, 30.4);
      expect(n.product!.name, 'Urea (46-0-0)');
      expect(n.product!.nutrientFraction, 0.46);
      expect(n.hasEstimate, isTrue);
      expect(n.advice.toLowerCase(), contains('estimated'));
      expect(report.summary.requiredCount, 1);
      expect(report.health.score, 92);
    });

    test('parses an excess nutrient with no product and no amount', () {
      final report = reportFrom(reportJson(
        requiredCount: 1,
        nutrients: {
          'K': nutrientJson(
            parameter: 'K',
            label: 'Potassium',
            band: const [35, 54],
            buffer: 5,
            current: 62,
            status: 'CRITICAL',
            required: true,
            direction: 'excess',
            gap: 8,
            advice: 'Potassium is 8.0 ppm above the configured range. '
                'Hold off on applying more K; no product is recommended.',
          ),
        },
      ));

      final k = report.nutrients['K']!;
      expect(k.status, FertilizerStatus.critical);
      expect(k.isExcess, isTrue);
      expect(k.isDeficient, isFalse);
      expect(k.product, isNull);
      expect(k.productKgHa, isNull);
      expect(k.nutrientKgHa, isNull);
      expect(k.hasEstimate, isFalse);
      expect(k.advice, isNot(contains('kg/ha')));
    });

    test('parses NO_READING with null required, current and gap', () {
      final report = reportFrom(reportJson(
        partial: true,
        requiredCount: 0,
        nutrients: {
          'N': nutrientJson(
            current: null,
            status: 'NO_READING',
            required: null,
            direction: null,
            gap: null,
            nutrientKgHa: null,
            productKgHa: null,
            product: null,
            advice: 'Sensor not reporting',
          ),
        },
      ));

      final n = report.nutrients['N']!;
      expect(n.status, FertilizerStatus.noReading);
      expect(n.isNoReading, isTrue);
      // null, not false: "we do not know" is not "not required".
      expect(n.required, isNull);
      // A null required must not be coerced into an action item.
      expect(n.needsAction, isFalse);
      expect(n.current, isNull);
      expect(n.gap, isNull);
      expect(n.product, isNull);
      expect(n.advice, 'Sensor not reporting');
      expect(report.health.partial, isTrue);
      expect(report.summary.requiredCount, 0);
    });

    test('parses the stale flag and reading age', () {
      final fresh = reportFrom(reportJson(stale: false, readingAgeSeconds: 12.4));
      expect(fresh.stale, isFalse);
      expect(fresh.readingAgeSeconds, 12.4);

      final stale =
          reportFrom(reportJson(stale: true, readingAgeSeconds: 4200.0));
      expect(stale.stale, isTrue);
      expect(stale.readingAgeSeconds, 4200.0);
      expect(stale.staleAfterSeconds, 600);
    });

    test('a missing timestamp leaves the age null but not stale', () {
      final report = reportFrom(reportJson());
      expect(report.readingAgeSeconds, isNull);
      expect(report.stale, isFalse);
    });

    test('an unknown status degrades to unknown, not a crash', () {
      final report = reportFrom(reportJson(
        nutrients: {
          'N': nutrientJson(status: 'SOMETHING_NEW', required: true),
        },
      ));
      final n = report.nutrients['N']!;
      expect(n.status, FertilizerStatus.unknown);
      expect(n.isWithinRange, isFalse);
      expect(n.isDeficient, isFalse);
      expect(n.isNoReading, isFalse);
      // `required` is honoured, so a new backend still drives the badge.
      expect(n.needsAction, isTrue);
    });

    test('tolerates missing and malformed optional fields', () {
      final report = reportFrom({
        'crop': 'wheat',
        'nutrients': {
          'N': {'label': 'Nitrogen', 'status': 'NORMAL'},
        },
      });
      final n = report.nutrients['N']!;
      expect(n.unit, '');
      expect(n.band, isEmpty);
      expect(n.buffer, isNull);
      expect(n.current, isNull);
      expect(n.gap, isNull);
      expect(n.required, isNull);
      expect(n.advice, '');
      expect(n.persistence, 'unavailable');
      expect(n.confidenceKnown, isFalse);
      // Absent health/summary still produce safe defaults.
      expect(report.health.fraction, 0);
      expect(report.summary.requiredCount, 0);
    });

    test('skips non-object nutrient entries and orders N, P, K', () {
      final report = reportFrom({
        'nutrients': {'N': 'garbage', 'K': {'label': 'Potassium'}, 'P': {}},
      });
      expect(report.nutrients.keys, ['K', 'P']);
      expect(report.order, ['P', 'K']);
    });

    test('health.fraction is clamped', () {
      final over = reportFrom({
        'health': {'score': 250, 'score_out_of': 100},
      });
      expect(over.health.fraction, 1.0);
      final under = reportFrom({
        'health': {'score': -40, 'score_out_of': 100},
      });
      expect(under.health.fraction, 0.0);
      final zero = reportFrom({'health': {'score': 50, 'score_out_of': 0}});
      expect(zero.health.fraction, 0.0);
    });

    test('persistence drives whether confidence may be shown', () {
      final instant = reportFrom(reportJson(persistence: 'unavailable'));
      expect(instant.nutrients['N']!.confidenceKnown, isFalse);

      final persistent = reportFrom(
          reportJson(persistence: 'persistent', confidence: 'persistent'));
      expect(persistent.nutrients['N']!.confidenceKnown, isTrue);
      expect(persistent.nutrients['N']!.confidence, 'persistent');
    });
  });

  // ── widget tests ─────────────────────────────────────────────────────────

  group('FertilizerScreen', () {
    /// Pumps the screen with an injected fetch, so no network or Firebase.
    Future<void> pump(
      WidgetTester tester, {
      required Map<String, dynamic> json,
      Stream<SensorData>? stream,
      List<SensorReading>? history,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: FertilizerScreen(
          sensorData: reading(),
          stream: stream ?? const Stream<SensorData>.empty(),
          historyLoader: (_) async => history ?? const [],
          fetch: ({
            required crop,
            required npk,
            current,
            history,
            readingAt,
          }) async =>
              reportFrom(json),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders a balanced nutrient as within configured range',
        (tester) async {
      await pump(tester, json: reportJson());
      expect(find.text('Nitrogen: Within configured range'), findsOneWidget);
      expect(find.textContaining('configured range 107-131 ppm'),
          findsOneWidget);
      // No amount is offered for a nutrient that needs nothing.
      expectNoAmountOffered(tester);
    });

    testWidgets('renders NO_READING as sensor not reporting', (tester) async {
      await pump(
        tester,
        json: reportJson(
          partial: true,
          nutrients: {
            'N': nutrientJson(
              current: null,
              status: 'NO_READING',
              required: null,
              advice: 'Sensor not reporting',
            ),
          },
        ),
      );
      expect(find.text('Nitrogen: Sensor not reporting'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expectNoAmountOffered(tester);
    });

    testWidgets('renders a deficiency with the estimated amount',
        (tester) async {
      await pump(
        tester,
        json: reportJson(
          score: 92,
          requiredCount: 1,
          nutrients: {
            'N': nutrientJson(
              current: 100,
              status: 'WARNING',
              required: true,
              direction: 'deficient',
              gap: 7,
              nutrientKgHa: 14.0,
              productKgHa: 30.4,
              product: const {
                'fertilizer': 'nitrogen-based',
                'name': 'Urea (46-0-0)',
                'role': 'Quick top-up',
                'nutrient_fraction': 0.46,
              },
              advice: 'Nitrogen is 7.0 ppm below the configured range. '
                  'Estimated about 30.4 kg/ha of Urea (46-0-0) needed to '
                  'reach the range.',
            ),
          },
        ),
      );

      expect(find.text('Nitrogen below the configured range'), findsOneWidget);
      // Gap is reported in the sensor's unit, the amount in kg/ha.
      expect(find.text('7 ppm below range'), findsOneWidget);
      expect(find.text('About 30 kg/ha Urea (46-0-0)'), findsOneWidget);
      // Progress reflects the real score, not a placeholder.
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.92, 0.001));
    });

    testWidgets('renders an excess with no amount', (tester) async {
      await pump(
        tester,
        json: reportJson(
          requiredCount: 1,
          nutrients: {
            'K': nutrientJson(
              parameter: 'K',
              label: 'Potassium',
              band: const [35, 54],
              buffer: 5,
              current: 62,
              status: 'CRITICAL',
              required: true,
              direction: 'excess',
              gap: 8,
              advice: 'Potassium is 8.0 ppm above the configured range. '
                  'Hold off on applying more K; no product is recommended.',
            ),
          },
        ),
      );

      expect(find.text('Potassium above the configured range'), findsOneWidget);
      expect(find.text('8 ppm above range'), findsOneWidget);
      expectNoAmountOffered(tester);
    });

    testWidgets('always renders all three nutrients', (tester) async {
      await pump(
        tester,
        json: reportJson(
          requiredCount: 2,
          nutrients: {
            'N': nutrientJson(
              current: 100,
              status: 'WARNING',
              required: true,
              direction: 'deficient',
              gap: 7,
              nutrientKgHa: 14,
              productKgHa: 30.4,
              product: const {'name': 'Urea (46-0-0)', 'nutrient_fraction': 0.46},
            ),
            'P': nutrientJson(
                parameter: 'P',
                label: 'Phosphorus',
                band: const [48, 74],
                buffer: 8,
                current: 61),
            'K': nutrientJson(
              parameter: 'K',
              label: 'Potassium',
              band: const [35, 54],
              buffer: 5,
              current: null,
              status: 'NO_READING',
              required: null,
              advice: 'Sensor not reporting',
            ),
          },
        ),
      );

      expect(find.text('Nitrogen below the configured range'), findsOneWidget);
      expect(find.text('Phosphorus: Within configured range'), findsOneWidget);
      expect(find.text('Potassium: Sensor not reporting'), findsOneWidget);
    });

    testWidgets('hides the confidence chip when persistence is unavailable',
        (tester) async {
      await pump(
        tester,
        json: reportJson(
          requiredCount: 1,
          persistence: 'unavailable',
          nutrients: {
            'N': nutrientJson(
              current: 100,
              status: 'WARNING',
              required: true,
              direction: 'deficient',
              gap: 7,
              nutrientKgHa: 14,
              productKgHa: 30.4,
              product: const {'name': 'Urea (46-0-0)', 'nutrient_fraction': 0.46},
            ),
          },
        ),
      );
      expect(find.text('From the latest reading'), findsNothing);
      expect(find.text('Confirmed over recent readings'), findsNothing);
    });

    testWidgets('shows the confidence chip when history backs the advice',
        (tester) async {
      await pump(
        tester,
        json: reportJson(
          requiredCount: 1,
          persistence: 'persistent',
          confidence: 'persistent',
          nutrients: {
            'N': nutrientJson(
              current: 100,
              status: 'WARNING',
              required: true,
              direction: 'deficient',
              gap: 7,
              nutrientKgHa: 14,
              productKgHa: 30.4,
              product: const {'name': 'Urea (46-0-0)', 'nutrient_fraction': 0.46},
              confidence: 'persistent',
              persistence: 'persistent',
            ),
          },
        ),
      );
      expect(find.text('Confirmed over recent readings'), findsOneWidget);
    });

    testWidgets('shows the stale state when the backend flags the reading',
        (tester) async {
      await pump(tester, json: reportJson(stale: true));
      expect(find.text('Stale'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
    });

    testWidgets('shows Live for a fresh reading', (tester) async {
      await pump(tester, json: reportJson());
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('always shows the prototype footnote', (tester) async {
      await pump(tester, json: reportJson());
      expect(
        find.textContaining('Estimated amounts use 1 ppm is about 2 kg/ha'),
        findsOneWidget,
      );
      expect(find.textContaining('Confirm with a soil test.'), findsOneWidget);
    });

    testWidgets('a stream event triggers one debounced refetch', (tester) async {
      final controller = StreamController<SensorData>();
      addTearDown(controller.close);

      var fetches = 0;
      await tester.pumpWidget(MaterialApp(
        home: FertilizerScreen(
          sensorData: reading(),
          stream: controller.stream,
          historyLoader: (_) async => const [],
          fetch: ({
            required crop,
            required npk,
            current,
            history,
            readingAt,
          }) async {
            fetches++;
            return reportFrom(reportJson());
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(fetches, 1, reason: 'the initial load fetches once');

      // A burst of readings inside the debounce window coalesces into one call.
      controller.add(reading(n: 100));
      controller.add(reading(n: 101));
      controller.add(reading(n: 102));
      await tester.pump();
      expect(fetches, 1, reason: 'still inside the debounce window');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(fetches, 2, reason: 'the burst produced exactly one refetch');

      // A later reading is debounced independently.
      controller.add(reading(n: 110));
      await tester.pump();
      expect(fetches, 2);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(fetches, 3);
    });

    testWidgets('disposes without calling setState after dispose',
        (tester) async {
      final controller = StreamController<SensorData>();
      addTearDown(controller.close);

      await tester.pumpWidget(MaterialApp(
        home: FertilizerScreen(
          sensorData: reading(),
          stream: controller.stream,
          historyLoader: (_) async => const [],
          fetch: ({
            required crop,
            required npk,
            current,
            history,
            readingAt,
          }) async =>
              reportFrom(reportJson()),
        ),
      ));
      await tester.pumpAndSettle();

      // Tear the screen down while a debounced refetch is still pending.
      controller.add(reading(n: 90));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // No exception means no setState-after-dispose.
      expect(tester.takeException(), isNull);
    });
  });
}
