import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_crop/models/crop_stage.dart';
import 'package:smart_crop/services/crop_tracking_service.dart';

/// The 30 label classes the Random Forest can predict, read from
/// smartcrop_rf_model.pkl. The stage table must cover exactly these.
const modelClasses = [
  'apple', 'banana', 'blackgram', 'chickpea', 'coconut', 'coffee', 'cotton',
  'grapes', 'jute', 'kidneybeans', 'lentil', 'maize', 'mango', 'mothbeans',
  'mungbean', 'muskmelon', 'mustard', 'onion', 'orange', 'papaya',
  'pigeonpeas', 'pomegranate', 'rice', 'sorghum', 'sugarcane', 'sunflower',
  'tobacco', 'tomato', 'watermelon', 'wheat',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tracking = CropTrackingService.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ═════════════════════════════════════════════════════════════════════
  group('A. scope', () {
    test('all 30 model crops have a profile, and nothing extra', () {
      expect(cropProfiles.keys.toSet(), modelClasses.toSet());
      expect(cropProfiles.length, 30);
    });

    test('every model crop resolves through profileFor', () {
      for (final c in modelClasses) {
        expect(profileFor(c), isNotNull, reason: c);
      }
    });

    test('unknown and display-form names return null', () {
      for (final v in ['', 'millet', 'barley', 'Wheat (Gehun)', 'nonsense']) {
        expect(profileFor(v), isNull, reason: v);
      }
    });

    test('profileFor tolerates casing and whitespace', () {
      for (final v in ['wheat', 'WHEAT', ' Wheat ']) {
        expect(profileFor(v), isNotNull, reason: v);
      }
    });

    test('provinces are drawn from the four provinces only', () {
      for (final c in modelClasses) {
        for (final p in profileFor(c)!.provinces) {
          expect(Province.values, contains(p), reason: '$c -> $p');
        }
      }
    });

    test('no province list means the crop is not a Pakistani mainstream crop', () {
      // Previously expressed as a KP-only region note.
      for (final c in ['jute', 'coffee', 'coconut']) {
        expect(profileFor(c)!.isUncommonInPakistan, isTrue, reason: c);
        expect(profileFor(c)!.provinces, isEmpty, reason: c);
      }
    });

    test('core Pakistani crops list their provinces', () {
      expect(profileFor('wheat')!.provinces.length, 4);
      expect(profileFor('rice')!.provinces, contains(Province.kp));
      expect(profileFor('mango')!.provinces, contains(Province.sindh));
    });

    test('nothing is marked verified and every band has advice', () {
      for (final c in modelClasses) {
        final p = profileFor(c)!;
        expect(p.verified, isFalse, reason: c);
        for (final band in StageBand.values) {
          expect(p.fertilizer[band], isNotNull, reason: '$c $band');
          expect(p.irrigation[band], isNotNull, reason: '$c $band');
          expect(p.fertilizer[band]!.trim(), isNotEmpty, reason: '$c $band');
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('A. sowing-window warning logic', () {
    final wheat = profileFor('wheat')!;

    test('wheat carries the researched windows per province', () {
      expect(wheat.sowingWindows.length, 7);
      final byLabel = {for (final w in wheat.sowingWindows) w.label: w};

      expect(byLabel['Punjab south']!.startLabel, '1 Nov');
      expect(byLabel['Punjab south']!.endLabel, '30 Dec');
      expect(byLabel['Punjab central and north (irrigated)']!.endLabel,
          '15 Dec');
      expect(byLabel['Sindh south']!.endLabel, '25 Dec');
      expect(byLabel['Sindh north']!.endLabel, '31 Dec');
      expect(byLabel['Khyber Pakhtunkhwa plains']!.startLabel, '25 Oct');
      expect(byLabel['Khyber Pakhtunkhwa plains']!.endLabel, '15 Dec');
      expect(byLabel['Khyber Pakhtunkhwa hills']!.startLabel, '1 Nov');
      expect(byLabel['Balochistan plains']!.endLabel, '15 Dec');
    });

    test('a date inside the window does not warn', () {
      // 15 Nov is inside every wheat window.
      expect(wheat.isOutsideWindow(DateTime(2026, 11, 15), Province.punjab),
          isFalse);
      expect(
          wheat.isOutsideWindow(DateTime(2026, 11, 15), Province.kp), isFalse);
    });

    test('a date outside the window warns', () {
      // 25 Feb is far outside an Oct-Dec window.
      expect(wheat.isOutsideWindow(DateTime(2026, 2, 25), Province.punjab),
          isTrue);
    });

    test('a date outside one province can be inside another', () {
      // 20 Dec: fine for Punjab south (to 30 Dec), too late for KP (to 15 Dec).
      final date = DateTime(2026, 12, 20);
      expect(wheat.isOutsideWindow(date, Province.punjab), isFalse);
      expect(wheat.isOutsideWindow(date, Province.kp), isTrue);
    });

    test('sub-regions collapse into one effective range per province', () {
      final pun = wheat.effectiveWindow(Province.punjab)!;
      // Punjab south runs to 30 Dec, central/north only to 15 Dec.
      expect(pun.startLabel, '1 Nov');
      expect(pun.endLabel, '30 Dec');

      final kp = wheat.effectiveWindow(Province.kp)!;
      // KP plains start 25 Oct; hills start 1 Nov.
      expect(kp.startLabel, '25 Oct');
      expect(kp.endLabel, '15 Dec');
    });

    test('the effective window honours the boundary days', () {
      final w = wheat.effectiveWindow(Province.kp)!;
      expect(w.contains(DateTime(2026, 10, 25)), isTrue, reason: 'start day');
      expect(w.contains(DateTime(2026, 12, 15)), isTrue, reason: 'end day');
      expect(w.contains(DateTime(2026, 10, 24)), isFalse, reason: 'day before');
      expect(w.contains(DateTime(2026, 12, 16)), isFalse, reason: 'day after');
    });

    test('a crop with no window for a province never warns', () {
      final lentil = profileFor('lentil')!;
      expect(lentil.sowingWindows, isEmpty);
      expect(lentil.isOutsideWindow(DateTime(2026, 3, 3), Province.punjab),
          isFalse);
      expect(lentil.effectiveWindow(Province.punjab), isNull);
    });

    test('a province with no window for that crop never warns', () {
      // Muskmelon only has a Punjab window.
      final melon = profileFor('muskmelon')!;
      expect(melon.effectiveWindow(Province.kp), isNull);
      expect(melon.isOutsideWindow(DateTime(2026, 3, 3), Province.kp), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('B. wheat', () {
    final wheat = profileFor('wheat')!;

    test('the total cycle is in the researched 150-165 day range', () {
      expect(wheat.typicalDuration, inInclusiveRange(150, 165));
    });

    test('stages start near the researched days after sowing', () {
      int start(String name) =>
          wheat.stages.firstWhere((s) => s.name == name).startDay;

      expect(start('Crown root initiation'), inInclusiveRange(20, 25));
      expect(start('Tillering'), inInclusiveRange(40, 60));
      expect(start('Jointing'), inInclusiveRange(60, 70));
      expect(start('Flowering'), inInclusiveRange(85, 95));
      expect(start('Milk'), inInclusiveRange(100, 105));
      expect(start('Dough'), inInclusiveRange(120, 125));
      // Maturity is whatever remains.
      expect(wheat.stages.last.name, 'Maturity');
    });

    test('stages stay contiguous across the whole cycle', () {
      for (var i = 1; i < wheat.stages.length; i++) {
        expect(wheat.stages[i].startDay, wheat.stages[i - 1].endDay + 1,
            reason: '${wheat.stages[i].name} follows '
                '${wheat.stages[i - 1].name}');
      }
      expect(wheat.stages.last.endDay, wheat.typicalDuration);
    });

    test('the late-sowing warning is carried on the profile', () {
      // Conditional: rendered only when the date is past the window end.
      expect(wheat.lateSowingWarning, isNotNull);
      expect(wheat.lateSowingWarning!.toLowerCase(), contains('shorter'));
      expect(wheat.lateSowingWarning!.toLowerCase(), contains('earlier'));
    });

    test('irrigation advice carries the researched watering pattern', () {
      final all = wheat.irrigation.values.join(' ').toLowerCase();
      expect(all, contains('four to five'));
      for (final stage in ['crown', 'tillering', 'jointing', 'flowering', 'milk']) {
        expect(all, contains(stage), reason: 'missing $stage');
      }
      expect(all, contains('three irrigations'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('C. rice', () {
    final rice = profileFor('rice')!;

    test('the date field is a transplanting date', () {
      expect(rice.dateAnchor, DateAnchor.transplanting);
      expect(rice.isTransplanted, isTrue);
      expect(rice.dateFieldLabel, 'Transplanting date');
    });

    test('the nursery hint is present', () {
      expect(rice.dateHint, isNotNull);
      expect(rice.dateHint!.toLowerCase(), contains('nursery'));
      expect(rice.dateHint!.toLowerCase(), contains('thirty'));
    });

    test('the total is the researched 100-120 days from transplanting', () {
      expect(rice.typicalDuration, inInclusiveRange(100, 120));
      expect(rice.stages.last.endDay, rice.typicalDuration);
    });

    test('transplanting is counted from day one, not from sowing', () {
      expect(rice.stages.first.startDay, 1);
      expect(rice.stageForDay(1)!.name, 'Establishment');
      // Every day maps to a stage, so day 1 is unambiguously transplanting+0.
      for (var d = 1; d <= rice.typicalDuration; d++) {
        expect(rice.stages.where((s) => s.contains(d)).length, 1,
            reason: 'day $d');
      }
    });

    test('the transplanting window is June-July in Punjab', () {
      // Field-confirmed: nursery from mid-May, transplanting June through
      // July. The old table started in mid-April, which is the nursery.
      final w = rice.effectiveWindow(Province.punjab)!;
      expect(w.startLabel, '1 Jun');
      expect(w.endLabel, '31 Jul');
      expect(rice.isOutsideWindow(DateTime(2026, 6, 1), Province.punjab),
          isFalse);
      expect(rice.isOutsideWindow(DateTime(2026, 7, 31), Province.punjab),
          isFalse);
      expect(rice.isOutsideWindow(DateTime(2026, 5, 31), Province.punjab),
          isTrue, reason: 'nursery time, not transplanting');
    });

    test('transplanting starts earliest in Sindh and Balochistan', () {
      // Sindh gets the heat first, so it transplants from May.
      for (final prov in [Province.sindh, Province.balochistan]) {
        final w = rice.effectiveWindow(prov)!;
        expect(w.startLabel, '1 May', reason: prov.label);
        expect(w.endLabel, '15 Jun', reason: prov.label);
        expect(rice.isOutsideWindow(DateTime(2026, 5, 1), prov), isFalse,
            reason: prov.label);
        expect(rice.isOutsideWindow(DateTime(2026, 4, 15), prov), isTrue,
            reason: prov.label);
      }
    });

    test('Khyber Pakhtunkhwa runs latest on the cooler weather', () {
      final w = rice.effectiveWindow(Province.kp)!;
      expect(w.startLabel, '15 Jun');
      expect(w.endLabel, '15 Jul');
    });

    test('Balochistan is now a listed rice province', () {
      expect(rice.provinces, contains(Province.balochistan));
      expect(rice.provinces.length, 4);
    });

    test('the window note separates nursery from transplanting', () {
      final notes = rice.windowNotes.join(' ');
      expect(notes, contains('transplanting dates'));
      expect(notes, contains('nursery is sown well before'));
      expect(notes, contains('mid-May'), reason: 'coarse and hybrid types');
      expect(notes, contains('Basmati'));
    });

    test('harvest notes cover IRRI, Basmati and the Sindh lead', () {
      final notes = rice.windowNotes.join(' ').toLowerCase();
      expect(notes, contains('october'));
      expect(notes, contains('basmati'));
      expect(notes, contains('sindh'));
      expect(notes, contains('starts earliest'),
          reason: 'Sindh leads because the heat arrives first');
      expect(notes, contains('khyber pakhtunkhwa'),
          reason: 'KP runs later on cooler weather');
    });

    test('rice is marked flooded and shows no soil-moisture target', () {
      expect(rice.floodedField, isTrue);
      expect(rice.moistureNote, isNotNull);
      expect(rice.moistureNote!.toLowerCase(), contains('standing water'));
      // The numeric soil-moisture target is neutralised, not shown.
      for (final band in StageBand.values) {
        final t = rice.monitoring[band]!;
        expect(t.soilMoistureMin, 0, reason: '$band');
        expect(t.soilMoistureMax, 0, reason: '$band');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('D. maize seasons', () {
    final maize = profileFor('maize')!;

    test('maize has exactly two named seasons', () {
      expect(maize.hasVariants, isTrue);
      expect(maize.variants.map((v) => v.name), ['Spring', 'Autumn']);
    });

    test('each season has its own stage table and total', () {
      final spring = maize.variantByName('Spring')!;
      final autumn = maize.variantByName('Autumn')!;

      expect(spring.typicalDuration, isNot(autumn.typicalDuration));
      expect(spring.stages.length, autumn.stages.length);
      expect(spring.stages.first.startDay, 1);
      expect(spring.stages.last.endDay, spring.typicalDuration);
      expect(autumn.stages.last.endDay, autumn.typicalDuration);
      // Contiguous within each season.
      for (final v in [spring, autumn]) {
        for (var i = 1; i < v.stages.length; i++) {
          expect(v.stages[i].startDay, v.stages[i - 1].endDay + 1,
              reason: '${v.name} ${v.stages[i].name}');
        }
      }
    });

    test('the two season tables genuinely diverge across the cycle', () {
      var differing = 0;
      for (var d = 1; d <= maize.durationForVariant('Spring'); d++) {
        final a = maize.stageForDay(d, variantName: 'Spring');
        final b = maize.stageForDay(d, variantName: 'Autumn');
        if (a != null && b != null && a.name != b.name) differing++;
      }
      // The season lengths and stage boundaries are not a straight copy.
      expect(differing, greaterThan(20),
          reason: 'only $differing days differ between the seasons');
    });

    test('a specific day resolves to different stages per season', () {
      // Day 30: still Seedling in spring, already Tillering in autumn.
      expect(maize.stageForDay(30, variantName: 'Spring')!.name, 'Seedling');
      expect(maize.stageForDay(30, variantName: 'Autumn')!.name, 'Tillering');
    });

    test('the season is suggested from the sowing month', () {
      // Spring is sown Jan-Feb; autumn is sown late July-August.
      expect(maize.suggestedVariantForDate(DateTime(2026, 2, 1))!.name,
          'Spring');
      expect(maize.suggestedVariantForDate(DateTime(2026, 1, 15))!.name,
          'Spring');
      expect(maize.suggestedVariantForDate(DateTime(2026, 8, 5))!.name,
          'Autumn');
      expect(maize.suggestedVariantForDate(DateTime(2026, 7, 25))!.name,
          'Autumn');
    });

    test('spring windows are Punjab late Jan to late Feb, Sindh early', () {
      final spring = maize.variantByName('Spring')!;
      final pun = spring.windows
          .firstWhere((w) => w.province == Province.punjab);
      expect(pun.startLabel, '21 Jan');
      expect(pun.endLabel, '28 Feb');

      final sin = spring.windows
          .firstWhere((w) => w.province == Province.sindh);
      expect(sin.startLabel, '1 Jan');
      expect(sin.endLabel, '10 Feb');
    });

    test('autumn windows cover Punjab, KP and Sindh', () {
      final autumn = maize.variantByName('Autumn')!;
      expect(autumn.windows.length, 3);
      final pun = autumn.windows
          .firstWhere((w) => w.province == Province.punjab);
      expect(pun.endLabel, '20 Aug');
      final kp =
          autumn.windows.firstWhere((w) => w.province == Province.kp);
      expect(kp.endLabel, '15 Aug');
      final sin = autumn.windows
          .firstWhere((w) => w.province == Province.sindh);
      expect(sin.startLabel, '1 Aug');
      expect(sin.endLabel, '30 Aug');
    });

    test('the Peshawar valley mid-July warning is carried', () {
      final autumn = maize.variantByName('Autumn')!;
      expect(autumn.regionNote, isNotNull);
      expect(autumn.regionNote!.toLowerCase(), contains('peshawar'));
      expect(autumn.regionNote!.toLowerCase(), contains('mid-july'));
    });

    test('the window check follows the selected season', () {
      // 5 Jan is inside the Sindh spring window (1 Jan - 10 Feb) but before
      // the Punjab one opens (21 Jan).
      final date = DateTime(2026, 1, 5);
      expect(
          maize.isOutsideWindow(date, Province.sindh, variantName: 'Spring'),
          isFalse);
      expect(
          maize.isOutsideWindow(date, Province.punjab, variantName: 'Spring'),
          isTrue);
      // In autumn the same January date is outside both.
      expect(
          maize.isOutsideWindow(date, Province.sindh, variantName: 'Autumn'),
          isTrue);
    });

    test('an unknown season name falls back to the default table', () {
      expect(maize.stageForDay(60, variantName: 'Monsoon')!.name,
          maize.stageForDay(60)!.name);
      expect(maize.durationForVariant('Monsoon'), maize.typicalDuration);
    });

    test('isPastLastStage respects the season length', () {
      final spring = maize.variantByName('Spring')!;
      expect(maize.isPastLastStage(spring.typicalDuration, variantName: 'Spring'),
          isFalse);
      expect(
          maize.isPastLastStage(spring.typicalDuration + 1,
              variantName: 'Spring'),
          isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. general structure', () {
    test('days-after-anchor stages are contiguous for every crop', () {
      for (final entry in cropProfiles.entries) {
        final p = entry.value;
        if (p.isMonthBased) continue;
        // A crop with seasons may leave the default table empty and put the
        // stages on the variants instead, so at least one list must exist.
        final lists = [p.stages, for (final v in p.variants) v.stages]
            .where((l) => l.isNotEmpty)
            .toList();
        expect(lists, isNotEmpty, reason: entry.key);
        for (final list in lists) {
          expect(list.first.startDay, 1, reason: entry.key);
          for (var i = 1; i < list.length; i++) {
            expect(list[i].startDay, list[i - 1].endDay + 1,
                reason: '${entry.key}: ${list[i].name}');
          }
        }
      }
    });

    test('stage names are unique within each stage list', () {
      for (final entry in cropProfiles.entries) {
        final p = entry.value;
        // Uniqueness is per list. A two-season crop legitimately repeats the
        // same stage names across its seasons, so they are checked apart.
        void check(List<String> names, String label) {
          expect(names.toSet().length, names.length, reason: '$entry.key $label');
        }

        check(p.stages.map((s) => s.name).toList(), 'days');
        check(p.monthStages.map((s) => s.name).toList(), 'months');
        for (final v in p.variants) {
          check(v.stages.map((s) => s.name).toList(), v.name);
        }
      }
    });

    test('month stages cover all 12 months with no overlap', () {
      for (final entry in cropProfiles.entries) {
        final p = entry.value;
        if (!p.isMonthBased) continue;
        final hits = <int, String>{};
        for (final s in p.monthStages) {
          expect(s.startMonth, inInclusiveRange(1, 12));
          expect(s.endMonth, inInclusiveRange(1, 12));
          for (final m in s.months) {
            expect(hits.containsKey(m), isFalse,
                reason: '${entry.key}: month $m in ${hits[m]} and ${s.name}');
            hits[m] = s.name;
          }
        }
        expect(hits.length, 12, reason: entry.key);
      }
    });

    test('year-wrapping month ranges list months in calendar order', () {
      final dormancy = profileFor('apple')!.monthStages
          .firstWhere((s) => s.name == 'Dormancy');
      expect(dormancy.wrapsYear, isTrue);
      expect(dormancy.months, [11, 12, 1, 2]);

      final harvest =
          profileFor('orange')!.monthStages.firstWhere((s) => s.name == 'Harvest');
      expect(harvest.months, [11, 12, 1]);
      expect(harvest.monthsUntilStart(3), 8);
    });

    test('next-stage lookup advances and wraps', () {
      final grape = profileFor('grapes')!;
      expect(grape.nextMonthStageAfter(2)!.name,
          grape.monthStages.firstWhere((s) => s.name == 'Bud break').name);
      // Past the last stage it wraps to the first.
      final last = grape.monthStages.last;
      expect(grape.nextMonthStageAfter(last.startMonth)!.name,
          grape.monthStages.first.name);

      final mango = profileFor('mango')!;
      expect(mango.nextMonthStageAfter(2)!.name, 'Fruit set');
    });

    test('monitoring ranges are ordered and physically sane', () {
      for (final entry in cropProfiles.entries) {
        for (final band in StageBand.values) {
          final t = entry.value.monitoring[band]!;
          final where = '${entry.key} $band';
          expect(t.soilMoistureMin, lessThanOrEqualTo(t.soilMoistureMax),
              reason: where);
          expect(t.soilMoistureMax, lessThanOrEqualTo(100), reason: where);
          expect(t.tempMin, lessThan(t.tempMax), reason: where);
          expect(t.humidityMin, lessThan(t.humidityMax), reason: where);
          expect(t.humidityMax, lessThanOrEqualTo(100), reason: where);
        }
      }
    });

    test('only flooded crops have a zeroed moisture target', () {
      for (final c in modelClasses) {
        final p = profileFor(c)!;
        for (final band in StageBand.values) {
          final t = p.monitoring[band]!;
          if (t.soilMoistureMax == 0) {
            expect(p.floodedField, isTrue,
                reason: '$c $band has no moisture target but is not flooded');
          }
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. advice wording', () {
    test('no advice text contains a dosage or a rate unit', () {
      final banned = <RegExp>[
        RegExp(r'\bkg\b', caseSensitive: false),
        RegExp(r'\bkgs?\b', caseSensitive: false),
        RegExp(r'\bg\b', caseSensitive: false),
        RegExp(r'\blbs?\b', caseSensitive: false),
        RegExp(r'per\s+acre', caseSensitive: false),
        RegExp(r'per\s+hectare', caseSensitive: false),
        RegExp(r'per\s+ha\b', caseSensitive: false),
        RegExp(r'\d+\s*%', caseSensitive: false),
        RegExp(r'\d+\s*DAS', caseSensitive: false),
      ];
      for (final c in modelClasses) {
        final p = profileFor(c)!;
        for (final band in StageBand.values) {
          for (final text in [p.fertilizer[band]!, p.irrigation[band]!]) {
            for (final r in banned) {
              expect(r.hasMatch(text), isFalse,
                  reason: '$c $band matches ${r.pattern}: $text');
            }
          }
        }
      }
    });

    test('no advice text contains a digit at all', () {
      // Strictest form of the guard: advice prose carries no numbers-with-units
      // or bare figures, so every count and interval is spelled out.
      final digit = RegExp(r'\d');
      for (final c in modelClasses) {
        final p = profileFor(c)!;
        for (final band in StageBand.values) {
          for (final text in [p.fertilizer[band]!, p.irrigation[band]!]) {
            expect(digit.hasMatch(text), isFalse,
                reason: '$c $band has a digit in advice: $text');
          }
        }
      }
    });

    test('the crop notes also avoid bare digits', () {
      final digit = RegExp(r'\d');
      for (final c in modelClasses) {
        final note = profileFor(c)!.note;
        if (note == null) continue;
        expect(digit.hasMatch(note), isFalse, reason: '$c note: $note');
      }
    });

    test('wording-only numbers are spelled out, not digitised', () {
      // The researched irrigation counts are prose, not dosages.
      final wheat = profileFor('wheat')!;
      final all = wheat.irrigation.values.join(' ').toLowerCase();
      expect(all, contains('four to five irrigations'));
      expect(all, contains('fifteen to twenty days'));
    });

    test('the updated pulse crops spell their timings out', () {
      expect(profileFor('chickpea')!.irrigation.values.join(' ').toLowerCase(),
          contains('fifty to sixty days'));
      final mustard = profileFor('mustard')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(mustard, contains('thirty to forty days'));
      expect(mustard, contains('sixty to seventy days'));
      final lentil = profileFor('lentil')!.note!.toLowerCase();
      expect(lentil, contains('one or two supplemental'));
    });
  });

  group('A. exact crop coverage', () {
    // The 30 label classes the Random Forest can predict, spelled out here so
    // this test is the single source of truth for the expected set.
    const expected = [
      'apple', 'banana', 'blackgram', 'chickpea', 'coconut', 'coffee',
      'cotton', 'grapes', 'jute', 'kidneybeans', 'lentil', 'maize', 'mango',
      'mothbeans', 'mungbean', 'muskmelon', 'mustard', 'onion', 'orange',
      'papaya', 'pigeonpeas', 'pomegranate', 'rice', 'sorghum', 'sugarcane',
      'sunflower', 'tobacco', 'tomato', 'watermelon', 'wheat',
    ];

    test('the profile keys are exactly the 30 model classes', () {
      expect(expected.length, 30);
      expect(cropProfiles.length, 30);
      expect(cropProfiles.keys.toSet(), expected.toSet());
    });

    test('the expected list matches the model classes list', () {
      expect(expected.toSet(), modelClasses.toSet());
    });

    test('each of the 30 is present, named explicitly', () {
      for (final c in expected) {
        expect(cropProfiles.containsKey(c), isTrue, reason: c);
        expect(profileFor(c), isNotNull, reason: c);
      }
    });

    test('barley is not a profile, whatever the casing or spacing', () {
      expect(cropProfiles.containsKey('barley'), isFalse);
      expect(profileFor('barley'), isNull);
      for (final v in ['barley', 'BARLEY', ' Barley ', 'barley (jau)']) {
        expect(profileFor(v), isNull, reason: v);
      }
    });

    test('other names outside the model are rejected', () {
      for (final v in ['', 'millet', 'soybean', 'peanut', 'nonsense']) {
        expect(profileFor(v), isNull, reason: v);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('B. sunflower', () {
    final sunflower = profileFor('sunflower')!;

    test('the cycle is back to about 100-120 days', () {
      expect(sunflower.typicalDuration, inInclusiveRange(100, 120));
      for (final v in sunflower.variants) {
        expect(v.stages.last.endDay, v.typicalDuration, reason: v.name);
        expect(v.typicalDuration, inInclusiveRange(100, 120), reason: v.name);
      }
    });

    test('stages are contiguous across the shorter cycle', () {
      // Seasons live on the variants, so walk every table, not one default.
      final tables = [for (final v in sunflower.variants) v.stages];
      expect(tables, isNotEmpty);
      for (final table in tables) {
        for (var i = 1; i < table.length; i++) {
          expect(table[i].startDay, table[i - 1].endDay + 1,
              reason: table[i].name);
        }
        expect(table.first.startDay, 1);
      }
    });

    test('every day of the cycle maps to exactly one stage', () {
      for (final v in sunflower.variants) {
        for (var d = 1; d <= v.typicalDuration; d++) {
          expect(v.stages.where((s) => s.contains(d)).length, 1,
              reason: '${v.name} day $d');
        }
      }
    });

    test('the note compares the two crops a year', () {
      // The sowing months now live in the windows, not the note.
      final note = sunflower.note!.toLowerCase();
      expect(note, contains('two crops a year'));
      expect(note, contains('less than the spring crop'));
      expect(sunflower.variants.length, 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('B. confidence is only claimed where researched', () {
    test('exactly wheat, rice and maize are high confidence', () {
      final high = modelClasses
          .where((c) => profileFor(c)!.confidence == Confidence.high)
          .toList();
      expect(high..sort(), ['maize', 'rice', 'wheat']);
    });

    test('the earlier medium upgrades stay undone apart from mango', () {
      // These were briefly medium; they are back to low.
      const reverted = [
        'apple', 'orange', 'banana', 'papaya', 'jute', 'blackgram',
        'kidneybeans', 'muskmelon', 'sorghum', 'tobacco', 'mothbeans',
      ];
      for (final c in reverted) {
        expect(profileFor(c)!.confidence, Confidence.low, reason: c);
      }
    });

    test('the medium set is the six crops revised against a source', () {
      // wheat / rice / maize stay high; these six are medium. Rest is low.
      final medium = modelClasses
          .where((c) => profileFor(c)!.confidence == Confidence.medium)
          .toList();
      expect(medium..sort(),
          ['chickpea', 'cotton', 'mango', 'mustard', 'onion', 'sugarcane']);
    });

    test('the remaining crops are low confidence', () {
      for (final c in modelClasses) {
        if (['wheat', 'rice', 'maize'].contains(c)) continue;
        if (['chickpea', 'cotton', 'mango', 'mustard', 'onion', 'sugarcane']
          .contains(c)) {
          continue;
        }
        expect(profileFor(c)!.confidence, Confidence.low, reason: c);
      }
    });

    test('nothing is verified, so the Draft badge always shows', () {
      for (final c in modelClasses) {
        expect(profileFor(c)!.verified, isFalse, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('C. next-stage phrasing', () {
    final wheat = profileFor('wheat')!;
    final sown = DateTime(2026, 11, 15);

    test('starting later gives a count and the calendar date', () {
      // Day 30 sits in Crown root initiation (20-39); Tillering starts day 40.
      final tillering = wheat.nextStageAfter(30)!;
      expect(tillering.name, 'Tillering');
      // 15 Nov + 39 days = 24 Dec (November has 30 days).
      final phrase = nextStagePhrase(tillering, daysSince: 30, anchorDate: sown);
      expect(phrase, 'starts in 10 days (around 24 Dec)');
    });

    test('starting tomorrow is worded as such', () {
      // Day 19 is the last day of Germination; CRI starts on day 20.
      final cri = wheat.nextStageAfter(19)!;
      expect(cri.name, 'Crown root initiation');
      expect(nextStagePhrase(cri, daysSince: 19, anchorDate: sown),
          'starts tomorrow');
    });

    test('starting today is handled', () {
      final germ = wheat.stages.first; // starts on day 1
      expect(nextStagePhrase(germ, daysSince: 1, anchorDate: sown),
          'starts today');
    });

    test('a date that has already passed also reads as today', () {
      final germ = wheat.stages.first;
      expect(nextStagePhrase(germ, daysSince: 3, anchorDate: sown),
          'starts today');
    });

    test('without an anchor date it falls back to the day number', () {
      final tillering = wheat.nextStageAfter(30)!;
      expect(nextStagePhrase(tillering, daysSince: 30),
          'starts in 10 days (around day 40)');
    });

    test('the calendar date rolls over into the new year', () {
      // Wheat sown 20 Dec; tillering starts on day 40, i.e. 29 Jan next year.
      final late = DateTime(2026, 12, 20);
      final tillering = wheat.stages.firstWhere((s) => s.name == 'Tillering');
      // 20 Dec + 39 days lands on 28 Jan of the following year.
      final on = stageStartDate(anchorDate: late, startDay: 40);
      expect(on.year, 2027);
      expect(on.month, 1);
      expect(on.day, 28);
      expect(
          nextStagePhrase(tillering, daysSince: 30, anchorDate: late),
          'starts in 10 days (around 28 Jan)');
    });

    test('months are formatted from a manual list, with no intl', () {
      expect(shortDate(1, 5), '5 Jan');
      expect(shortDate(12, 31), '31 Dec');
      expect(monthName(3), 'March');
      expect(monthName(13), 'Unknown month');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('C. next-month phrasing', () {
    final orange = profileFor('orange')!;

    test('a stage starting next month is worded as such', () {
      final flowering = orange.monthStages
          .firstWhere((s) => s.name == 'Late harvest and flowering');
      expect(nextMonthStagePhrase(flowering, currentMonth: 1),
          'starts next month (around February)');
    });

    test('a stage further away counts the months', () {
      final growth = orange.monthStages
          .firstWhere((s) => s.name == 'Fruit growth'); // May
      expect(nextMonthStagePhrase(growth, currentMonth: 3),
          'starts in 2 months (around May)');
    });

    test('a stage already running reads as this month', () {
      final flowering = orange.monthStages
          .firstWhere((s) => s.name == 'Late harvest and flowering');
      expect(nextMonthStagePhrase(flowering, currentMonth: 3),
          'starts this month');
    });

    test('a wrap from December into the new year says so', () {
      // Orange now leads with Harvest (Nov-Jan), so the wrap sits in Fruit
      // growth, which runs May-October and restarts the following May.
      final growth = orange.monthStages
          .firstWhere((s) => s.name == 'Fruit growth');
      final phrase = nextMonthStagePhrase(growth, currentMonth: 12);
      expect(phrase, contains('5 months'));
      expect(phrase, contains('May'));
      expect(phrase, contains('next year'));
    });

    test('a non-wrapping stage does not claim a new year', () {
      final set = orange.monthStages
          .firstWhere((s) => s.name == 'Fruit set'); // April
      final phrase = nextMonthStagePhrase(set, currentMonth: 3);
      expect(phrase, isNot(contains('next year')));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('D. anchor-date picker range', () {
    final today = DateTime(2026, 9, 29);

    test('today is inside the range', () {
      final r = sowingPickerRange(today: today, cycleDays: 120);
      expect(r.contains(today), isTrue);
    });

    test('the lower bound tracks the crop cycle, not a fixed 400 days', () {
      // Regression: a 400-day floor put most of last October on screen, so
      // asking for "the twenty-first of October" could silently land a year
      // earlier and the crop then read as finished.
      final r = sowingPickerRange(today: today, cycleDays: 60);
      // 60 + 60 = 120 days back from 29 Sep 2026.
      expect(r.first, DateTime(2026, 6, 1));
      expect(r.contains(DateTime(2025, 10, 21)), isFalse,
          reason: 'last October is out of reach for a short crop');
    });

    test('the previous October is unreachable for wheat', () {
      // Wheat is 160 days, so the bound is 160 + 60 = 220 days back.
      final wheat = profileFor('wheat')!;
      final r = sowingPickerRange(today: today, cycleDays: wheat.typicalDuration);
      expect(r.contains(DateTime(2026, 10, 21)), isTrue,
          reason: 'this October is the valid one and must be pickable');
      expect(r.contains(DateTime(2025, 10, 21)), isFalse,
          reason: 'last October would read as a finished crop');
    });

    test('a long-cycle crop reaches back past its own cycle', () {
      // Sugarcane autumn runs 540 days, so the bound is 540 + 60 = 600 days.
      final sugarcane = profileFor('sugarcane')!;
      final r = sowingPickerRange(
          today: today, cycleDays: sugarcane.maxDurationAcrossVariants);
      // 600 days before 29 Sep 2026 is 6 Feb 2025.
      expect(r.first, DateTime(2025, 2, 6));
      // A whole previous cycle is therefore enterable.
      expect(r.contains(DateTime(2025, 3, 1)), isTrue,
          reason: 'a full 540-day cycle back must be reachable');
    });

    test('a very old date is accepted for a long-cycle crop', () {
      final sugarcane = profileFor('sugarcane')!;
      final r = sowingPickerRange(
          today: today, cycleDays: sugarcane.maxDurationAcrossVariants);
      expect(r.contains(DateTime(2025, 3, 15)), isTrue);
      // Anything before the bound is clamped rather than rejected.
      expect(r.contains(DateTime(2020, 1, 1)), isFalse);
      expect(r.clamp(DateTime(2020, 1, 1)), r.first);
    });

    test('the upper bound allows planning a whole season ahead', () {
      final r = sowingPickerRange(today: today, cycleDays: 120);
      expect(r.last, DateTime(2027, 1, 27));
      expect(r.contains(DateTime(2026, 10, 1)), isTrue);
      expect(r.contains(DateTime(2026, 12, 15)), isTrue,
          reason: 'a wheat window can run into late December');
      expect(r.contains(DateTime(2027, 1, 28)), isFalse,
          reason: 'beyond the planning horizon');
    });

    test('both October and December are reachable for a wheat sowing', () {
      final wheat = profileFor('wheat')!;
      final r = sowingPickerRange(today: today, cycleDays: wheat.typicalDuration);
      for (final d in [
        DateTime(2026, 10, 21),
        DateTime(2026, 11, 1),
        DateTime(2026, 12, 15),
      ]) {
        expect(r.contains(d), isTrue, reason: '$d');
        // Every one of them is a planned sowing, never a finished crop.
        expect(wheat.cycleStatus(today.difference(d).inDays),
            CycleStatus.upcoming, reason: '$d');
      }
    });

    test('a saved date past the horizon is clamped to the last day', () {
      final r = sowingPickerRange(today: today, cycleDays: 120);
      final saved = DateTime(2027, 5, 1);
      expect(r.contains(saved), isFalse);
      expect(r.clamp(saved), r.last);
    });

    test('a saved date before the range is clamped to the first day', () {
      final r = sowingPickerRange(today: today, cycleDays: 120);
      final saved = DateTime(2010, 1, 1);
      expect(r.contains(saved), isFalse);
      expect(r.clamp(saved), r.first);
    });

    test('a saved date inside the range is left alone', () {
      final r = sowingPickerRange(today: today, cycleDays: 120);
      final saved = DateTime(2026, 9, 20);
      expect(r.clamp(saved), saved);
    });

    test('clamping always yields something the picker accepts', () {
      final r = sowingPickerRange(
          today: today, cycleDays: profileFor('banana')!.typicalDuration);
      for (final d in [
        DateTime(1990, 5, 5),
        DateTime(2026, 1, 1),
        today,
        DateTime(2030, 12, 31),
      ]) {
        expect(r.contains(r.clamp(d)), isTrue, reason: '$d');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('D. planned (future) sowing', () {
    final wheat = profileFor('wheat')!;
    final planned = DateTime(2026, 10, 20); // in the future

    test('a future date is upcoming, not an error', () {
      final daysSince = DateTime(2026, 9, 29).difference(planned).inDays;
      expect(daysSince, lessThan(0));
      expect(wheat.cycleStatus(daysSince), CycleStatus.upcoming);
    });

    test('an active date is active', () {
      expect(wheat.cycleStatus(30), CycleStatus.active);
      expect(wheat.cycleStatus(1), CycleStatus.active);
    });

    test('a date past the last stage is complete', () {
      expect(wheat.cycleStatus(wheat.typicalDuration), CycleStatus.active);
      expect(wheat.cycleStatus(wheat.typicalDuration + 1),
          CycleStatus.complete);
    });

    test('milestone dates are counted forward from the future date', () {
      final daysSince = DateTime(2026, 9, 29).difference(planned).inDays;
      final milestones = wheat.milestonesFrom(
        anchorDate: planned,
        daysSince: daysSince,
      );

      expect(milestones.length, wheat.stages.length);
      // Every milestone is still in the future.
      expect(milestones.every((m) => !m.reached), isTrue);
      // First stage begins on the planned date itself (day 1).
      expect(milestones.first.stage, 'Germination');
      expect(milestones.first.date, planned);
      // Tillering starts on day 40, i.e. 39 days after 20 Oct = 28 Nov.
      final tillering = milestones.firstWhere((m) => m.stage == 'Tillering');
      expect(tillering.date, DateTime(2026, 11, 28));
      expect(tillering.reached, isFalse);
    });

    test('milestone dates roll over the year correctly', () {
      // Planned for 20 December: flowering on day 85 lands in the new year.
      final late = DateTime(2026, 12, 20);
      final milestones = wheat.milestonesFrom(
        anchorDate: late,
        daysSince: -5,
      );
      final flowering = milestones.firstWhere((m) => m.stage == 'Flowering');
      expect(flowering.date.year, 2027);
      expect(flowering.date.month, 3);
    });

    test('once the date arrives the milestones are reached', () {
      final milestones = wheat.milestonesFrom(
        anchorDate: planned,
        daysSince: 45,
      );
      expect(milestones.first.reached, isTrue, reason: 'Germination on day 1');
      expect(
        milestones.firstWhere((m) => m.stage == 'Flowering').reached,
        isFalse,
        reason: 'Flowering starts on day 85',
      );
    });

    test('milestones follow the selected season', () {
      final maize = profileFor('maize')!;
      final autumn = maize.milestonesFrom(
        anchorDate: planned,
        daysSince: 0,
        variantName: 'Autumn',
      );
      final spring = maize.milestonesFrom(
        anchorDate: planned,
        daysSince: 0,
        variantName: 'Spring',
      );
      // Autumn is the shorter cycle, so its last stage starts sooner.
      expect(autumn.last.date.isBefore(spring.last.date), isTrue,
          reason: 'autumn ends at 115 days, spring at 125');
      // Both still start their first stage on the anchor date itself.
      expect(autumn.first.date, planned);
      expect(spring.first.date, planned);
    });

    test('a month-based perennial has no day milestones', () {
      expect(
        profileFor('apple')!
            .milestonesFrom(anchorDate: planned, daysSince: 10),
        isEmpty,
      );
      expect(profileFor('apple')!.cycleStatus(-5), CycleStatus.active);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. cotton', () {
    final cotton = profileFor('cotton')!;

    test('confidence is medium', () {
      expect(cotton.confidence, Confidence.medium);
      expect(cotton.verified, isFalse);
    });

    test('the cycle is inside the researched 150-180 days', () {
      expect(cotton.typicalDuration, inInclusiveRange(150, 180));
      expect(cotton.stages.last.endDay, cotton.typicalDuration);
    });

    test('stages match the researched milestones and stay contiguous', () {
      int start(String n) =>
          cotton.stages.firstWhere((s) => s.name == n).startDay;
      int end(String n) =>
          cotton.stages.firstWhere((s) => s.name == n).endDay;

      expect(cotton.stages.first.name, 'Emergence');
      expect(start('Emergence'), 1);
      expect(end('Emergence'), 10);
      expect(start('Seedling'), 11);
      expect(end('Seedling'), 35);
      expect(start('Squaring'), 36);
      expect(end('Squaring'), 55);
      expect(start('Flowering'), 56);
      expect(end('Flowering'), 100);
      expect(start('Boll development'), 101);
      expect(end('Boll development'), 140);
      expect(start('Boll opening and picking'), 141);

      // No gaps and no overlaps.
      for (var i = 1; i < cotton.stages.length; i++) {
        expect(cotton.stages[i].startDay, cotton.stages[i - 1].endDay + 1,
            reason: cotton.stages[i].name);
      }
    });

    test('every day of the cycle maps to exactly one stage', () {
      for (var d = 1; d <= cotton.typicalDuration; d++) {
        expect(cotton.stages.where((s) => s.contains(d)).length, 1,
            reason: 'day $d');
      }
    });

    test('the windows are Punjab April-May and Sindh March-April', () {
      final pun = cotton.effectiveWindow(Province.punjab)!;
      expect(pun.startLabel, '1 Apr');
      expect(pun.endLabel, '31 May');

      final sin = cotton.effectiveWindow(Province.sindh)!;
      expect(sin.startLabel, '25 Mar');
      expect(sin.endLabel, '30 Apr');
    });

    test('there is no KP window', () {
      expect(cotton.effectiveWindow(Province.kp), isNull);
      expect(cotton.windowsForProvince(Province.kp), isEmpty);
      // And no warning is raised for KP at all.
      expect(
          cotton.isOutsideWindow(DateTime(2026, 4, 20), Province.kp), isFalse);
    });

    test('KP is dropped from the province list', () {
      expect(cotton.provinces, isNot(contains(Province.kp)));
    });

    test('the late-sowing note names the yield loss', () {
      final w = profileFor('cotton')!.lateSowingWarning!;
      expect(w, startsWith('Sown after the end of the recommended window.'));
      expect(w, contains('Cotton sown late loses yield.'));
      // No digits, and no mid-June phrasing left over from the old wording.
      expect(RegExp(r'\\d').hasMatch(w), isFalse);
      expect(w, isNot(contains('mid-June')));
      expect(w, isNot(contains('Check with')));
    });

    test('the boll-picking note explains the rounds', () {
      final note = cotton.note!.toLowerCase();
      expect(note, contains('rounds'));
      expect(note, contains('fifteen'));
      expect(note, contains('twenty'));
      expect(note, contains('forty'));
    });

    test('irrigation advice states the first timing and the critical window',
        () {
      final all = cotton.irrigation.values.join(' ').toLowerCase();
      expect(all, contains('thirty to thirty-five days'));
      expect(all, contains('twelve to fifteen days'));
      expect(all, contains('forty to one hundred and twenty days'));
      expect(all, contains('steady'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. sugarcane', () {
    final cane = profileFor('sugarcane')!;

    test('confidence is medium and nothing is verified', () {
      expect(cane.confidence, Confidence.medium);
      expect(cane.verified, isFalse);
    });

    test('it has two seasons with different totals', () {
      expect(cane.hasVariants, isTrue);
      final spring = cane.variantByName('Spring')!;
      final autumn = cane.variantByName('Autumn')!;

      expect(spring.typicalDuration, inInclusiveRange(300, 450));
      expect(autumn.typicalDuration, inInclusiveRange(400, 540));
      // Autumn runs longer because winter slows growth.
      expect(autumn.typicalDuration, greaterThan(spring.typicalDuration));
    });

    test('the season is suggested from the planting month', () {
      expect(cane.suggestedVariantForDate(DateTime(2026, 2, 20))!.name,
          'Spring');
      expect(cane.suggestedVariantForDate(DateTime(2026, 3, 15))!.name,
          'Spring');
      expect(cane.suggestedVariantForDate(DateTime(2026, 9, 20))!.name,
          'Autumn');
      expect(cane.suggestedVariantForDate(DateTime(2026, 10, 5))!.name,
          'Autumn');
    });

    test('the season totals are inside the researched ranges', () {
      expect(cane.durationForVariant('Spring'), inInclusiveRange(300, 450));
      expect(cane.durationForVariant('Autumn'), inInclusiveRange(400, 540));
    });

    test('each season is contiguous and ends at its own total', () {
      for (final v in cane.variants) {
        expect(v.stages.first.startDay, 1, reason: v.name);
        for (var i = 1; i < v.stages.length; i++) {
          expect(v.stages[i].startDay, v.stages[i - 1].endDay + 1,
              reason: '${v.name}: ${v.stages[i].name}');
        }
        expect(v.stages.last.endDay, v.typicalDuration, reason: v.name);
      }
    });

    test('stage boundaries follow the researched pattern', () {
      final spring = cane.variantByName('Spring')!;
      int start(String n) =>
          spring.stages.firstWhere((s) => s.name == n).startDay;

      expect(start('Germination'), 1);
      expect(spring.stages.first.endDay, 45);
      expect(start('Tillering'), 46);
      expect(spring.stages[1].endDay, 120);
      expect(start('Grand growth'), 121);
      expect(spring.stages[2].endDay, 270);
      expect(start('Ripening'), 271);
    });

    test('the windows are Feb-Mar for spring and Sep-Oct for autumn', () {
      final spring = cane.variantByName('Spring')!;
      final punSpring = spring.windows
          .firstWhere((w) => w.province == Province.punjab);
      expect(punSpring.startLabel, '10 Feb');
      expect(punSpring.endLabel, '31 Mar');

      final autumn = cane.variantByName('Autumn')!;
      final punAutumn = autumn.windows
          .firstWhere((w) => w.province == Province.punjab);
      expect(punAutumn.startLabel, '1 Sep');
      expect(punAutumn.endLabel, '15 Oct');
    });

    test('KP grows sugarcane in spring only', () {
      final spring = cane.variantByName('Spring')!;
      final autumn = cane.variantByName('Autumn')!;
      expect(spring.provinces, contains(Province.kp));
      expect(autumn.provinces, isNot(contains(Province.kp)));
      // Both seasons cover Punjab and Sindh.
      for (final v in [spring, autumn]) {
        expect(v.provinces, contains(Province.punjab), reason: v.name);
        expect(v.provinces, contains(Province.sindh), reason: v.name);
      }
      // And the province lookup follows the season.
      expect(cane.provincesFor('Spring'), contains(Province.kp));
      expect(cane.provincesFor('Autumn'), isNot(contains(Province.kp)));
    });

    test('the date picker reaches back about 600 days for sugarcane', () {
      final today = DateTime(2026, 9, 29);
      final r = sowingPickerRange(
          today: today, cycleDays: cane.maxDurationAcrossVariants);
      // Autumn is 540 days, so the bound is 540 + 60 = 600.
      expect(cane.maxDurationAcrossVariants, 540);
      expect(r.first, DateTime(2025, 2, 6));
      // A whole previous autumn cycle is enterable.
      expect(r.contains(DateTime(2025, 3, 20)), isTrue);
    });

    test('the picker uses the longest season even before a choice', () {
      // Switching to the longer season must not need a different range.
      final today = DateTime(2026, 9, 29);
      final a = sowingPickerRange(
          today: today, cycleDays: cane.durationForVariant('Spring'));
      final b = sowingPickerRange(
          today: today, cycleDays: cane.durationForVariant('Autumn'));
      expect(b.first.isBefore(a.first), isTrue);
    });

    test('irrigation advice flags the first 120 days as critical', () {
      final all = cane.irrigation.values.join(' ').toLowerCase();
      expect(all, contains('first hundred and twenty days'));
      expect(all, contains('many irrigations'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. the two fixes', () {
    final wheat = profileFor('wheat')!;
    final cotton = profileFor('cotton')!;

    test('the late-sowing warning is conditional, not always shown', () {
      expect(wheat.lateSowingWarning, isNotNull);
      // It is no longer in the always-on windowNotes list.
      expect(
        wheat.windowNotes.join(' ').toLowerCase(),
        isNot(contains('shorter cycle')),
      );
    });

    test('a date before the window opens does NOT trigger it', () {
      // 29 September sits 33 days before a 1 Nov window opens: early.
      final early = DateTime(2026, 9, 29);
      expect(wheat.isAfterWindow(early, Province.punjab), isFalse);
      // It is still outside the window, so the non-blocking warning shows.
      expect(wheat.isOutsideWindow(early, Province.punjab), isTrue);
    });

    test('a date inside the window triggers neither', () {
      final inside = DateTime(2026, 11, 20);
      expect(wheat.isAfterWindow(inside, Province.punjab), isFalse);
      expect(wheat.isOutsideWindow(inside, Province.punjab), isFalse);
    });

    test('20 January for wheat is LATE, not early', () {
      // The Punjab window runs 1 Nov - 30 Dec. 20 January is 21 days past the
      // end and 285 days before the window reopens, so it is the nearer
      // boundary and therefore late.
      final late = DateTime(2027, 1, 20);
      expect(wheat.isAfterWindow(late, Province.punjab), isTrue);
      expect(wheat.isOutsideWindow(late, Province.punjab), isTrue);
    });

    test('29 September for wheat is EARLY, not late', () {
      // 273 days past the 30 Dec end but only 33 days before 1 Nov opens, so
      // the start is nearer and the date is early.
      final early = DateTime(2026, 9, 29);
      expect(wheat.isAfterWindow(early, Province.punjab), isFalse);
    });

    test('the late/early split holds across the whole year for wheat', () {
      // The switch-over sits at 1 June, where the distance past the 30 Dec
      // window end equals the distance to the 1 Nov opening.
      expect(wheat.isAfterWindow(DateTime(2026, 12, 31), Province.punjab),
          isTrue);
      expect(wheat.isAfterWindow(DateTime(2027, 1, 1), Province.punjab),
          isTrue);
      expect(wheat.isAfterWindow(DateTime(2027, 5, 31), Province.punjab),
          isTrue, reason: 'a day before the switch-over is still late');
      expect(wheat.isAfterWindow(DateTime(2027, 6, 1), Province.punjab),
          isFalse, reason: 'the switch-over date itself is early');
      expect(wheat.isAfterWindow(DateTime(2027, 6, 15), Province.punjab),
          isFalse, reason: 'past the switch-over, so early');
    });

    test('Punjab cotton switches from late to early around 30 October', () {
      expect(cotton.isAfterWindow(DateTime(2026, 10, 30), Province.punjab),
          isTrue, reason: '30 Oct is closer to the 31 May window end');
      expect(cotton.isAfterWindow(DateTime(2026, 10, 31), Province.punjab),
          isFalse,
          reason: '31 Oct is already closer to the 1 Apr opening, so early');
    });

    test('15 June for Punjab cotton is LATE', () {
      // The Punjab window closes 31 May, so mid-June is past it.
      expect(
          cotton.isAfterWindow(DateTime(2026, 6, 15), Province.punjab), isTrue);
      expect(cotton.isAfterWindow(DateTime(2026, 6, 15), Province.sindh),
          isTrue);
    });

    test('1 January for cotton is EARLY', () {
      expect(cotton.isAfterWindow(DateTime(2027, 1, 1), Province.sindh),
          isFalse);
      expect(cotton.isAfterWindow(DateTime(2027, 1, 1), Province.punjab),
          isFalse);
    });

    test('one day past the window end fires, one day before does not', () {
      // The Punjab window closes 30 Dec, so 31 Dec is genuinely late.
      expect(wheat.isAfterWindow(DateTime(2026, 12, 31), Province.punjab),
          isTrue);
      expect(wheat.isAfterWindow(DateTime(2026, 12, 30), Province.punjab),
          isFalse);
      // And one day before the window opens is early.
      expect(wheat.isAfterWindow(DateTime(2026, 10, 31), Province.punjab),
          isFalse);
      expect(wheat.isAfterWindow(DateTime(2026, 11, 1), Province.punjab),
          isFalse, reason: 'the first day of the window is neither');
    });

    test('a leap year does not shift the classification', () {
      // 2028 is a leap year. The same mid-season date must classify the same
      // way in a leap and a non-leap year.
      final nonLeap = wheat.isAfterWindow(DateTime(2026, 3, 15), Province.punjab);
      final leap = wheat.isAfterWindow(DateTime(2028, 3, 15), Province.punjab);
      expect(leap, nonLeap);
      // 2028 is a leap year and 2026 is not, so this is a real comparison.
      expect(wheat.isAfterWindow(DateTime(2028, 1, 20), Province.punjab),
          isTrue);
    });

    test('a year-wrapping window classifies correctly too', () {
      // Grapes fruit set and berry growth runs June, a single-month window.
      final grapes = profileFor('grapes')!;
      final setStage = grapes.monthStages
          .firstWhere((s) => s.name == 'Fruit set and berry growth');
      expect(setStage.startMonth, 6);
      expect(setStage.endMonth, 6);
      // A month-based crop has no day windows, so no warning either way.
      expect(grapes.isAfterWindow(DateTime(2026, 8, 1), Province.kp), isFalse);
    });

    test('cotton behaves the same way', () {
      // Sindh window closes 30 Apr. 15 July is late.
      expect(cotton.isAfterWindow(DateTime(2026, 7, 15), Province.sindh),
          isTrue);
      // 10 Feb is early, not late.
      expect(cotton.isAfterWindow(DateTime(2026, 2, 10), Province.sindh),
          isFalse);
    });

    test('the Punjab wheat window shows the combined sub-region wording', () {
      expect(
        wheat.windowLabel(Province.punjab),
        '1 Nov-15 Dec (central and north), to 30 Dec in the south',
      );
    });

    test('the Punjab label does not change the comparison range', () {
      // The data still spans 1 Nov to 30 Dec; only the wording is custom.
      final w = wheat.effectiveWindow(Province.punjab)!;
      expect(w.startLabel, '1 Nov');
      expect(w.endLabel, '30 Dec');
      expect(w.contains(DateTime(2026, 12, 20)), isTrue);
    });

    test('other provinces keep the computed range', () {
      expect(wheat.windowLabel(Province.kp), '25 Oct to 15 Dec');
      expect(wheat.windowLabel(Province.sindh), '1 Nov to 31 Dec');
      expect(wheat.windowLabel(Province.balochistan), '1 Nov to 15 Dec');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. updated pulse and oilseed crops', () {
    /// Asserts a 1-based, contiguous stage table that ends at its own total.
    void checkShape(CropProfile p) {
      expect(p.stages.first.startDay, 1, reason: p.name);
      expect(p.stages.first.name, 'Emergence', reason: p.name);
      for (var i = 1; i < p.stages.length; i++) {
        expect(p.stages[i].startDay, p.stages[i - 1].endDay + 1,
            reason: '${p.name}: ${p.stages[i].name}');
      }
      expect(p.stages.last.endDay, p.typicalDuration, reason: p.name);
      for (var d = 1; d <= p.typicalDuration; d++) {
        expect(p.stages.where((s) => s.contains(d)).length, 1,
            reason: '${p.name} day $d');
      }
    }

    int startOf(CropProfile p, String stage) =>
        p.stages.firstWhere((s) => s.name == stage).startDay;
    int endOf(CropProfile p, String stage) =>
        p.stages.firstWhere((s) => s.name == stage).endDay;

    test('chickpea: shape, boundaries, confidence and windows', () {
      final p = profileFor('chickpea')!;
      checkShape(p);
      expect(p.typicalDuration, 130);
      expect(p.confidence, Confidence.medium);
      expect(p.verified, isFalse);

      expect(endOf(p, 'Emergence'), 10);
      expect(startOf(p, 'Branching'), 11);
      expect(endOf(p, 'Branching'), 45);
      expect(startOf(p, 'Flowering'), 46);
      expect(endOf(p, 'Flowering'), 75);
      expect(startOf(p, 'Pod filling'), 76);
      expect(endOf(p, 'Pod filling'), 110);
      expect(startOf(p, 'Maturity'), 111);

      // Punjab only, split rainfed vs irrigated.
      expect(p.sowingWindows.length, 2);
      final rainfed = p.windowsForProvince(Province.punjab)
          .firstWhere((w) => w.region == 'rainfed');
      expect(rainfed.startLabel, '20 Oct');
      expect(rainfed.endLabel, '10 Nov');
      final irrigated = p.windowsForProvince(Province.punjab)
          .firstWhere((w) => w.region == 'irrigated');
      expect(irrigated.startLabel, '1 Nov');
      expect(irrigated.endLabel, '15 Nov');
      // Effective window collapses both sub-regions.
      final eff = p.effectiveWindow(Province.punjab)!;
      expect(eff.startLabel, '20 Oct');
      expect(eff.endLabel, '15 Nov');

      // No other province has a window.
      for (final prov in [Province.sindh, Province.kp, Province.balochistan]) {
        expect(p.windowsForProvince(prov), isEmpty, reason: prov.label);
        expect(p.effectiveWindow(prov), isNull, reason: prov.label);
      }
    });

    test('chickpea irrigation covers both irrigations and the kabuli case',
        () {
      final all = profileFor('chickpea')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('two irrigations'));
      expect(all, contains('branching'));
      expect(all, contains('pod filling'));
      expect(all, contains('kabuli'));
      expect(all, contains('fifty to sixty days'));
    });

    test('mustard: shape, boundaries, confidence and all four provinces', () {
      final p = profileFor('mustard')!;
      checkShape(p);
      expect(p.typicalDuration, 150);
      expect(p.confidence, Confidence.medium);

      expect(endOf(p, 'Emergence'), 10);
      expect(startOf(p, 'Rosette'), 11);
      expect(endOf(p, 'Rosette'), 60);
      expect(startOf(p, 'Flowering'), 61);
      expect(endOf(p, 'Flowering'), 95);
      expect(startOf(p, 'Pod and seed fill'), 96);
      expect(endOf(p, 'Pod and seed fill'), 130);
      expect(startOf(p, 'Maturity'), 131);

      // KP, Punjab, Sindh and Balochistan are all covered.
      final kp = p.effectiveWindow(Province.kp)!;
      expect(kp.startLabel, '15 Sep');
      expect(kp.endLabel, '15 Oct');

      final pun = p.effectiveWindow(Province.punjab)!;
      expect(pun.startLabel, '1 Oct');
      expect(pun.endLabel, '30 Nov');

      for (final prov in [Province.sindh, Province.balochistan]) {
        final w = p.effectiveWindow(prov)!;
        expect(w.startLabel, '15 Oct', reason: prov.label);
        expect(w.endLabel, '15 Nov', reason: prov.label);
      }
      // South Punjab is the narrower of the two Punjab sub-regions.
      final south = p.windowsForProvince(Province.punjab)
          .firstWhere((w) => w.region == 'south');
      expect(south.startLabel, '15 Oct');
      expect(south.endLabel, '15 Nov');
    });

    test('mustard irrigation names the critical flowering window', () {
      final all = profileFor('mustard')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('three to four irrigations'));
      expect(all, contains('rosette'));
      expect(all, contains('thirty to forty days'));
      expect(all, contains('sixty to seventy days'));
      expect(all, contains('most critical'));
    });

    test('lentil: shape, boundaries, low confidence, no windows', () {
      final p = profileFor('lentil')!;
      checkShape(p);
      expect(p.typicalDuration, 140);
      // The scale is low/medium/high, so mid-confidence is not available.
      expect(p.confidence, Confidence.low);

      expect(endOf(p, 'Emergence'), 12);
      expect(startOf(p, 'Vegetative'), 13);
      expect(endOf(p, 'Vegetative'), 60);
      expect(startOf(p, 'Flowering'), 61);
      expect(endOf(p, 'Flowering'), 100);
      expect(startOf(p, 'Pod filling'), 101);
      expect(endOf(p, 'Pod filling'), 125);
      expect(startOf(p, 'Maturity'), 126);

      expect(p.sowingWindows, isEmpty);
      for (final prov in Province.values) {
        expect(p.effectiveWindow(prov), isNull, reason: prov.label);
      }
    });

    test('lentil note carries the season and the rainfed habit', () {
      final note = profileFor('lentil')!.note!.toLowerCase();
      expect(note, contains('october'));
      expect(note, contains('november'));
      expect(note, contains('march'));
      expect(note, contains('april'));
      expect(note, contains('rainfed'));
      expect(note, contains('supplemental irrigations'));
    });

    test('mungbean: shape, boundaries, low confidence, no windows', () {
      final p = profileFor('mungbean')!;
      checkShape(p);
      expect(p.typicalDuration, 70);
      expect(p.confidence, Confidence.low);
      // Punjab, Balochistan, KP and Sindh.
      expect(p.provinces.toSet(),
          {Province.punjab, Province.balochistan, Province.kp, Province.sindh});

      expect(endOf(p, 'Emergence'), 7);
      expect(startOf(p, 'Vegetative'), 8);
      expect(endOf(p, 'Vegetative'), 30);
      expect(startOf(p, 'Flowering'), 31);
      expect(endOf(p, 'Flowering'), 45);
      expect(startOf(p, 'Pod filling'), 46);
      expect(endOf(p, 'Pod filling'), 60);
      expect(startOf(p, 'Maturity'), 61);

      // No official windows were available, so none are registered.
      expect(p.sowingWindows, isEmpty);
    });

    test('mungbean note records both seasons and the long older varieties', () {
      final note = profileFor('mungbean')!.note!.toLowerCase();
      expect(note, contains('sixty to seventy days'));
      expect(note, contains('ninety'));
      expect(note, contains('spring'));
      expect(note, contains('kharif'));
    });

    test('mungbean irrigation says two to three with pod fill most critical',
        () {
      final all = profileFor('mungbean')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('two to three irrigations'));
      expect(all, contains('establishment'));
      expect(all, contains('flowering'));
      expect(all, contains('pod fill is the most critical'));
    });

    test('blackgram: shape, boundaries, provinces and confidence', () {
      final p = profileFor('blackgram')!;
      checkShape(p);
      expect(p.typicalDuration, 90);
      expect(p.confidence, Confidence.low);
      // Punjab and KP only; Sindh was dropped.
      expect(p.provinces.toSet(), {Province.punjab, Province.kp});

      expect(endOf(p, 'Emergence'), 7);
      expect(startOf(p, 'Vegetative'), 8);
      expect(endOf(p, 'Vegetative'), 35);
      expect(startOf(p, 'Flowering'), 36);
      expect(endOf(p, 'Flowering'), 55);
      expect(startOf(p, 'Pod filling'), 56);
      expect(endOf(p, 'Pod filling'), 80);
      expect(startOf(p, 'Maturity'), 81);
    });

    test('blackgram note records the season and the barani habit', () {
      final note = profileFor('blackgram')!.note!.toLowerCase();
      expect(note, contains('july'));
      expect(note, contains('august'));
      expect(note, contains('october'));
      expect(note, contains('november'));
      expect(note, contains('rain'));
    });

    test('blackgram irrigation splits irrigated and barani areas', () {
      final all = profileFor('blackgram')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('two to three irrigations'));
      expect(all, contains('irrigated zones'));
      expect(all, contains('barani'));
    });

    test('chickpea and mustard are medium, the other pulses are low', () {
      expect(profileFor('chickpea')!.confidence, Confidence.medium);
      expect(profileFor('mustard')!.confidence, Confidence.medium);
      for (final c in ['lentil', 'mungbean', 'blackgram']) {
        expect(profileFor(c)!.confidence, Confidence.low, reason: c);
      }
    });

    test('lentil, mungbean and blackgram stay low', () {
      for (final c in ['lentil', 'mungbean', 'blackgram']) {
        expect(profileFor(c)!.confidence, Confidence.low, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('E. horticulture crops', () {
    /// 1-based, contiguous, ends at the crop's own total.
    void checkShape(CropProfile p, int total, {String firstStage = 'Establishment'}) {
      expect(p.stages.first.startDay, 1, reason: p.name);
      expect(p.stages.first.name, firstStage, reason: p.name);
      for (var i = 1; i < p.stages.length; i++) {
        expect(p.stages[i].startDay, p.stages[i - 1].endDay + 1,
            reason: '${p.name}: ${p.stages[i].name}');
      }
      expect(p.stages.last.endDay, total, reason: p.name);
      for (var d = 1; d <= total; d++) {
        expect(p.stages.where((s) => s.contains(d)).length, 1,
            reason: '${p.name} day $d');
      }
    }

    int startOf(CropProfile p, String stage) =>
        p.stages.firstWhere((s) => s.name == stage).startDay;
    int endOf(CropProfile p, String stage) =>
        p.stages.firstWhere((s) => s.name == stage).endDay;

    test('onion is counted from transplanting', () {
      final p = profileFor('onion')!;
      expect(p.dateAnchor, DateAnchor.transplanting);
      expect(p.isTransplanted, isTrue);
      expect(p.dateFieldLabel, 'Transplanting date');
      expect(p.anchorNoun, 'transplanting');
      expect(p.anchorNounTitle, 'Transplanting');
      expect(p.noDateLabel, 'Set transplanting date');
      expect(p.dateHint, isNotNull);
      expect(p.dateHint!.toLowerCase(), contains('nursery'));
      expect(p.dateHint!.toLowerCase(), contains('forty-five to sixty days'));
    });

    test('onion shape, boundaries, confidence and provinces', () {
      final p = profileFor('onion')!;
      expect(p.typicalDuration, 120);
      checkShape(p, 120, firstStage: 'Recovery and leaf growth');
      expect(p.stages.first.name, 'Recovery and leaf growth');
      expect(endOf(p, 'Recovery and leaf growth'), 30);
      expect(startOf(p, 'Bulb enlargement'), 31);
      expect(endOf(p, 'Bulb enlargement'), 90);
      expect(startOf(p, 'Ripening and neck fall'), 91);
      expect(endOf(p, 'Ripening and neck fall'), 120);

      expect(p.confidence, Confidence.medium);
      expect(p.provinces.toSet(),
          {Province.punjab, Province.sindh, Province.kp, Province.balochistan});
    });

    test('onion windows are KP mid-December and Punjab December-January', () {
      final p = profileFor('onion')!;
      final kp = p.windowsForProvince(Province.kp).single;
      expect(kp.startLabel, '15 Dec');
      expect(kp.endLabel, '15 Jan');
      // The KP window crosses New Year and must be treated as wrapping.
      expect(kp.wrapsYear, isTrue);
      expect(kp.contains(DateTime(2026, 12, 20)), isTrue);
      expect(kp.contains(DateTime(2027, 1, 10)), isTrue);
      expect(kp.contains(DateTime(2026, 6, 1)), isFalse);

      final pun = p.windowsForProvince(Province.punjab).single;
      expect(pun.startLabel, '1 Dec');
      expect(pun.endLabel, '31 Jan');
      expect(pun.wrapsYear, isTrue);
      expect(pun.contains(DateTime(2027, 1, 15)), isTrue);
    });

    test('onion note flags early transplanting and bolting', () {
      final note = profileFor('onion')!.note!.toLowerCase();
      expect(note, contains('early transplanting'));
      expect(note, contains('bolting'));
      expect(note, contains('longer'));
    });

    test('onion irrigation gives the count, the pinch point and the stop',
        () {
      final all = profileFor('onion')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('six to eight irrigations'));
      expect(all, contains('most water-sensitive'));
      expect(all, contains('sixty days'));
      expect(all, contains('three weeks before harvest'));
    });

    test('tomato is counted from transplanting', () {
      final p = profileFor('tomato')!;
      expect(p.dateAnchor, DateAnchor.transplanting);
      expect(p.dateFieldLabel, 'Transplanting date');
      expect(p.noDateLabel, 'Set transplanting date');
      expect(p.dateHint!.toLowerCase(), contains('nursery'));
      expect(p.dateHint!.toLowerCase(), contains('thirty to forty days'));
    });

    test('tomato has Autumn and Winter-spring seasons', () {
      final p = profileFor('tomato')!;
      expect(p.hasVariants, isTrue);
      expect(p.variants.map((v) => v.name), ['Autumn', 'Winter-spring']);
      expect(p.durationForVariant('Autumn'), 130);
      expect(p.durationForVariant('Winter-spring'), 120);
      expect(p.maxDurationAcrossVariants, 130);
    });

    test('the tomato season is suggested from the transplanting month', () {
      final p = profileFor('tomato')!;
      expect(p.suggestedVariantForDate(DateTime(2026, 8, 20))!.name, 'Autumn');
      expect(p.suggestedVariantForDate(DateTime(2026, 9, 10))!.name, 'Autumn');
      expect(p.suggestedVariantForDate(DateTime(2026, 12, 1))!.name,
          'Winter-spring');
      expect(p.suggestedVariantForDate(DateTime(2027, 2, 1))!.name,
          'Winter-spring');
    });

    test('each tomato season is contiguous and ends at its own total', () {
      final p = profileFor('tomato')!;
      for (final v in p.variants) {
        expect(v.stages.first.startDay, 1, reason: v.name);
        expect(v.stages.first.name, 'Establishment', reason: v.name);
        for (var i = 1; i < v.stages.length; i++) {
          expect(v.stages[i].startDay, v.stages[i - 1].endDay + 1,
              reason: '${v.name}: ${v.stages[i].name}');
        }
        expect(v.stages.last.endDay, v.typicalDuration, reason: v.name);
        int s(int day) => v.stages
            .firstWhere((st) => st.contains(day))
            .startDay;
        expect(s(15), 15, reason: v.name);
        expect(s(36), 36, reason: v.name);
        expect(s(61), 61, reason: v.name);
        expect(s(76), 76, reason: v.name);
      }
    });

    test('tomato windows: autumn for all, winter-spring Punjab only', () {
      final p = profileFor('tomato')!;
      final autumn = p.variantByName('Autumn')!;
      expect(autumn.windows.length, 4);
      for (final w in autumn.windows) {
        expect(w.startLabel, '1 Aug', reason: w.province.label);
        expect(w.endLabel, '30 Sep', reason: w.province.label);
      }

      final winter = p.variantByName('Winter-spring')!;
      expect(winter.windows.length, 1);
      final w = winter.windows.single;
      expect(w.province, Province.punjab);
      expect(w.startLabel, '15 Nov');
      expect(w.endLabel, '10 Feb');
      expect(w.wrapsYear, isTrue, reason: 'November to February wraps');
      expect(w.contains(DateTime(2026, 12, 20)), isTrue);
      expect(w.contains(DateTime(2027, 1, 20)), isTrue);
    });

    test('tomato note mentions the Swat summer crop', () {
      final note = profileFor('tomato')!.note!.toLowerCase();
      expect(note, contains('swat'));
      expect(note, contains('summer crop'));
      expect(note, contains('july'));
      expect(note, contains('september'));
    });

    test('tomato irrigation stresses even watering and avoiding swings', () {
      final all = profileFor('tomato')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('regularly and evenly'));
      expect(all, contains('swings'));
    });

    test('watermelon: direct sown, shape, boundaries and confidence', () {
      final p = profileFor('watermelon')!;
      expect(p.isTransplanted, isFalse);
      expect(p.dateFieldLabel, 'Sowing date');
      expect(p.typicalDuration, 95);
      checkShape(p, 95);
      expect(endOf(p, 'Establishment'), 12);
      expect(startOf(p, 'Vine growth'), 13);
      expect(endOf(p, 'Vine growth'), 35);
      expect(startOf(p, 'Flowering'), 36);
      expect(endOf(p, 'Flowering'), 53);
      expect(startOf(p, 'Fruit filling'), 54);
      expect(endOf(p, 'Fruit filling'), 78);
      expect(startOf(p, 'Ripening'), 79);
      expect(endOf(p, 'Ripening'), 95);
      expect(p.confidence, Confidence.low);
      expect(p.provinces.toSet(),
          {Province.punjab, Province.sindh, Province.kp});
    });

    test('watermelon windows: Punjab spring, plus KP and central Punjab in July',
        () {
      final p = profileFor('watermelon')!;
      expect(p.sowingWindows.length, 3);
      final punSpring = p.windowsForProvince(Province.punjab)
          .firstWhere((w) => w.region == null);
      expect(punSpring.startLabel, '1 Feb');
      expect(punSpring.endLabel, '31 Mar');

      final central = p.windowsForProvince(Province.punjab)
          .firstWhere((w) => w.region == 'central');
      expect(central.startLabel, '1 Jul');
      expect(central.endLabel, '31 Jul');

      final kp = p.windowsForProvince(Province.kp).single;
      expect(kp.startLabel, '1 Jul');
      expect(kp.endLabel, '31 Jul');
      expect(p.windowsForProvince(Province.sindh), isEmpty);
    });

    test('watermelon irrigation opens heavy, then stays regular', () {
      final all = profileFor('watermelon')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('one heavy irrigation'));
      expect(all, contains('vine growth'));
      expect(all, contains('fruit filling'));
      expect(all, contains('reduce at ripening'));
    });

    test('muskmelon: direct sown, shape, boundaries and confidence', () {
      final p = profileFor('muskmelon')!;
      expect(p.isTransplanted, isFalse);
      expect(p.typicalDuration, 90);
      checkShape(p, 90);
      expect(endOf(p, 'Establishment'), 12);
      expect(startOf(p, 'Vine growth'), 13);
      expect(endOf(p, 'Vine growth'), 35);
      expect(startOf(p, 'Flowering'), 36);
      expect(endOf(p, 'Flowering'), 50);
      expect(startOf(p, 'Fruit development'), 51);
      expect(endOf(p, 'Fruit development'), 75);
      expect(startOf(p, 'Ripening'), 76);
      expect(endOf(p, 'Ripening'), 90);
      expect(p.confidence, Confidence.low);
      expect(p.provinces.toSet(), {Province.punjab, Province.sindh});
    });

    test('muskmelon window is Punjab February-March only', () {
      final p = profileFor('muskmelon')!;
      expect(p.sowingWindows.length, 1);
      final w = p.effectiveWindow(Province.punjab)!;
      expect(w.startLabel, '1 Feb');
      expect(w.endLabel, '31 Mar');
      for (final prov in [Province.sindh, Province.kp, Province.balochistan]) {
        expect(p.effectiveWindow(prov), isNull, reason: prov.label);
      }
    });

    test('muskmelon note records the alternative April-May practice', () {
      final note = profileFor('muskmelon')!.note!.toLowerCase();
      expect(note, contains('april'));
      expect(note, contains('may'));
      expect(note, contains('june'));
      expect(note, contains('august'));
    });

    test('muskmelon irrigation gives the count and the stop', () {
      final all = profileFor('muskmelon')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(all, contains('four to five irrigations'));
      expect(all, contains('two weeks before harvest'));
      expect(all, contains('flavour'));
    });

    test('the confidence set is exactly as specified', () {
      final high = modelClasses
          .where((c) => profileFor(c)!.confidence == Confidence.high)
          .toList();
      expect(high..sort(), ['maize', 'rice', 'wheat']);

      final medium = modelClasses
          .where((c) => profileFor(c)!.confidence == Confidence.medium)
          .toList();
      expect(medium..sort(),
          ['chickpea', 'cotton', 'mango', 'mustard', 'onion', 'sugarcane']);

      for (final c in modelClasses) {
        if (['wheat', 'rice', 'maize'].contains(c)) continue;
        if (['chickpea', 'cotton', 'mango', 'mustard', 'onion', 'sugarcane']
          .contains(c)) {
          continue;
        }
        expect(profileFor(c)!.confidence, Confidence.low, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('F. oilseed, fodder and cash crops', () {
    /// Every stage list on a crop: the default table plus each variant.
    List<List<CropStage>> allTables(CropProfile p) => [
          p.stages,
          for (final v in p.variants) v.stages,
        ].where((l) => l.isNotEmpty).toList();

    /// 1-based, contiguous, ends at the table's own total.
    void checkTable(List<CropStage> list, int total, String label) {
      expect(list.first.startDay, 1, reason: label);
      for (var i = 1; i < list.length; i++) {
        expect(list[i].startDay, list[i - 1].endDay + 1,
            reason: '$label: ${list[i].name}');
      }
      expect(list.last.endDay, total, reason: label);
      for (var d = 1; d <= total; d++) {
        expect(list.where((st) => st.contains(d)).length, 1,
            reason: '$label day $d');
      }
    }

    int startOf(List<CropStage> list, String name) =>
        list.firstWhere((st) => st.name == name).startDay;
    int endOf(List<CropStage> list, String name) =>
        list.firstWhere((st) => st.name == name).endDay;

    List<SowingWindow> wins(CropProfile p, String variant, Province prov) =>
        p.windowsForProvince(prov, variantName: variant);

    // ── sunflower ─────────────────────────────────────────────────────
    test('sunflower has a Spring and an Autumn season', () {
      final p = profileFor('sunflower')!;
      expect(p.hasVariants, isTrue);
      expect(p.variants.map((v) => v.name), ['Spring', 'Autumn']);
      expect(p.durationForVariant('Spring'), 110);
      expect(p.durationForVariant('Autumn'), 100);
      expect(p.typicalDuration, 110);
      expect(p.maxDurationAcrossVariants, 110);
      expect(p.confidence, Confidence.low);
      expect(p.provinces.toSet(),
          {Province.punjab, Province.sindh, Province.kp, Province.balochistan});
    });

    test('every sunflower season is contiguous and ends at its own total', () {
      final p = profileFor('sunflower')!;
      for (final t in allTables(p)) {
        checkTable(t, t.last.endDay, p.name);
      }
      final spring = p.variantByName('Spring')!.stages;
      final autumn = p.variantByName('Autumn')!.stages;
      expect(spring.last.endDay, 110);
      expect(autumn.last.endDay, 100);
      // The tail is trimmed, not the head: both seasons share a shape.
      expect(spring.map((st) => st.name), autumn.map((st) => st.name));
      expect(startOf(spring, 'Germination'), 1);
      expect(startOf(spring, 'Vegetative'), 9);
      expect(startOf(spring, 'Bud initiation'), 31);
      expect(startOf(spring, 'Flowering'), 46);
      expect(startOf(spring, 'Seed filling'), 61);
      expect(startOf(spring, 'Maturity'), 101);
      expect(endOf(spring, 'Seed filling'), 100);
      expect(startOf(autumn, 'Maturity'), 91);
      expect(endOf(autumn, 'Seed filling'), 90);
    });

    test('sunflower Spring windows match the region list', () {
      final p = profileFor('sunflower')!;
      expect(wins(p, 'Spring', Province.punjab).length, 3);
      void w(String region, int sm, int sd, int em, int ed) {
        final win = wins(p, 'Spring', Province.punjab)
            .firstWhere((x) => x.region == region);
        expect(win.startMonth, sm, reason: region);
        expect(win.startDay, sd, reason: region);
        expect(win.endMonth, em, reason: region);
        expect(win.endDay, ed, reason: region);
      }

      w('central', 1, 1, 1, 31);
      w('north', 1, 1, 2, 15);
      w('south', 1, 1, 1, 31);

      void sv(String region, int sm, int sd, int em, int ed, bool wrap) {
        final win = wins(p, 'Spring', Province.sindh)
            .firstWhere((x) => x.region == region);
        expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
            [sm, sd, em, ed], reason: region);
        expect(win.wrapsYear, wrap, reason: region);
      }

      sv('lower', 11, 25, 1, 31, true); // November into January wraps.
      sv('upper', 12, 1, 2, 28, true); // December into February wraps.

      final bal = wins(p, 'Spring', Province.balochistan).single;
      expect([bal.startMonth, bal.startDay, bal.endMonth, bal.endDay],
          [1, 1, 2, 28]);
      expect(bal.wrapsYear, isFalse);

      final kp = wins(p, 'Spring', Province.kp).single;
      expect([kp.startMonth, kp.startDay, kp.endMonth, kp.endDay],
          [2, 1, 2, 28]);
      expect(kp.contains(DateTime(2026, 2, 14)), isTrue);
      expect(kp.contains(DateTime(2026, 2, 20)), isTrue);
      expect(kp.contains(DateTime(2026, 2, 28)), isTrue);
      expect(kp.contains(DateTime(2026, 3, 1)), isFalse);
    });

    test('sunflower Autumn windows are Jul-Sep for Pundjab and Sindh', () {
      final p = profileFor('sunflower')!;
      for (final prov in [Province.punjab, Province.sindh]) {
        final win = wins(p, 'Autumn', prov).single;
        expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
            [7, 1, 9, 15], reason: prov.label);
      }
      for (final prov in [Province.balochistan, Province.kp]) {
        final win = wins(p, 'Autumn', prov).single;
        expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
            [7, 1, 8, 31], reason: prov.label);
      }
    });

    test('sunflower note says autumn yields less and south Punjab stops early',
        () {
      final note = profileFor('sunflower')!.note!.toLowerCase();
      expect(note, contains('less than the spring crop'));
      expect(note, contains('south punjab'));
      expect(note, contains('end of january'));
    });

    test('sunflower season is suggested from the sowing month', () {
      final p = profileFor('sunflower')!;
      expect(p.suggestedVariantForDate(DateTime(2026, 1, 15))!.name, 'Spring');
      expect(p.suggestedVariantForDate(DateTime(2026, 12, 1))!.name, 'Spring');
      expect(p.suggestedVariantForDate(DateTime(2026, 2, 10))!.name, 'Spring');
      expect(p.suggestedVariantForDate(DateTime(2026, 8, 10))!.name, 'Autumn');
      expect(p.suggestedVariantForDate(DateTime(2026, 9, 15))!.name, 'Autumn');
      // Outside both windows it still returns the nearer season, never null.
      expect(p.suggestedVariantForDate(DateTime(2026, 3, 1))!.name, 'Spring');
      expect(p.suggestedVariantForDate(DateTime(2026, 5, 1))!.name, 'Autumn');
    });

    // ── sorghum ───────────────────────────────────────────────────────
    test('sorghum has a Grain and a Fodder season', () {
      final p = profileFor('sorghum')!;
      expect(p.variants.map((v) => v.name), ['Grain', 'Fodder']);
      expect(p.durationForVariant('Grain'), 105);
      expect(p.durationForVariant('Fodder'), 60);
      expect(p.typicalDuration, 105);
      expect(p.confidence, Confidence.low);
      // Union of both seasons: grain is Punjab only, fodder adds S and KP.
      expect(p.provinces.toSet(),
          {Province.punjab, Province.sindh, Province.kp});
    });

    test('every sorghum season is contiguous and ends at its own total', () {
      final p = profileFor('sorghum')!;
      for (final t in allTables(p)) {
        checkTable(t, t.last.endDay, p.name);
      }
      final grain = p.variantByName('Grain')!.stages;
      expect(grain.last.endDay, 105);
      expect(startOf(grain, 'Establishment'), 1);
      expect(startOf(grain, 'Vegetative growth'), 11);
      expect(startOf(grain, 'Grand growth'), 41);
      expect(startOf(grain, 'Heading and flowering'), 71);
      expect(startOf(grain, 'Grain filling'), 86);
      expect(startOf(grain, 'Maturity'), 101);

      final fodder = p.variantByName('Fodder')!.stages;
      expect(fodder.length, 3);
      expect(fodder.last.endDay, 60);
      expect(startOf(fodder, 'Establishment'), 1);
      expect(startOf(fodder, 'Vegetative growth'), 11);
      expect(startOf(fodder, 'Heading and first cut'), 41);
      expect(endOf(fodder, 'Heading and first cut'), 60);
    });

    test('sorghum grain window is May-June for Punjab only', () {
      final p = profileFor('sorghum')!;
      final v = p.variantByName('Grain')!;
      expect(v.provinces, [Province.punjab]);
      expect(v.windows.length, 1);
      final win = wins(p, 'Grain', Province.punjab).single;
      expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
          [5, 1, 6, 30]);
      expect(win.contains(DateTime(2026, 5, 20)), isTrue);
      expect(win.contains(DateTime(2026, 7, 1)), isFalse);
      // The other provinces have no grain window at all.
      for (final prov in
          [Province.sindh, Province.kp, Province.balochistan]) {
        expect(wins(p, 'Grain', prov), isEmpty, reason: prov.label);
        expect(p.effectiveWindow(prov, variantName: 'Grain'), isNull,
            reason: prov.label);
      }
      expect(p.provinces.toSet(),
          {Province.punjab, Province.sindh, Province.kp},
          reason: 'crop list is the union of both seasons');
    });

    test('sorghum note flags the grain window as one research trial', () {
      final p = profileFor('sorghum')!;
      expect(p.note, contains('single research trial'));
      expect(p.variantByName('Grain')!.regionNote,
          contains('single research trial'));
    });

    test('sorghum fodder window is mid-February to mid-March', () {
      final p = profileFor('sorghum')!;
      expect(wins(p, 'Fodder', Province.punjab).length, 1);
      final win = wins(p, 'Fodder', Province.punjab).single;
      expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
          [2, 15, 3, 15]);
      expect(win.contains(DateTime(2026, 3, 1)), isTrue);
      expect(win.contains(DateTime(2026, 3, 20)), isFalse);
      expect(win.wrapsYear, isFalse);
    });

    test('sorghum note says fodder is cut early and regrows', () {
      final note = profileFor('sorghum')!.note!.toLowerCase();
      expect(note, contains('fodder sorghum is cut early and regrows'));
      expect(note, contains('later cuttings'));
      expect(note, contains('normal harvest prompt applies to it'));
    });

    test('sorghum irrigation separates the irrigated and rainfed cases', () {
      final irr = profileFor('sorghum')!.irrigation.values.join(' ').toLowerCase();
      expect(irr, contains('three to four irrigations'));
      expect(irr, contains('rainfed'));
      expect(irr, contains('monsoon'));
      expect(irr, contains('heading'));
    });

    test('sorghum fodder irrigation waits about three weeks then repeats', () {
      final irr = profileFor('sorghum')!.irrigation.values.join(' ').toLowerCase();
      expect(irr, contains('after each cut'));
      expect(irr, contains('regrowth'));
    });

    test('sorghum season is suggested from the sowing month', () {
      final p = profileFor('sorghum')!;
      expect(p.suggestedVariantForDate(DateTime(2026, 5, 20))!.name, 'Grain');
      expect(p.suggestedVariantForDate(DateTime(2026, 6, 30))!.name, 'Grain');
      expect(p.suggestedVariantForDate(DateTime(2026, 3, 1))!.name, 'Fodder');
      expect(p.suggestedVariantForDate(DateTime(2026, 2, 20))!.name, 'Fodder');
      expect(p.suggestedVariantForDate(DateTime(2026, 7, 15))!.name, 'Grain');
    });

    // ── tobacco ───────────────────────────────────────────────────────
    test('tobacco is counted from transplanting and is KP only', () {
      final p = profileFor('tobacco')!;
      expect(p.dateAnchor, DateAnchor.transplanting);
      expect(p.isTransplanted, isTrue);
      expect(p.dateFieldLabel, 'Transplanting date');
      expect(p.noDateLabel, 'Set transplanting date');
      expect(p.anchorNoun, 'transplanting');
      expect(p.provinces, [Province.kp]);
      expect(p.confidence, Confidence.low);
      expect(p.verified, isFalse, reason: 'Draft badge must stay');
    });

    test('tobacco transplanting hint names the nursery season', () {
      final hint = profileFor('tobacco')!.dateHint!.toLowerCase();
      expect(hint, contains('nursery'));
      expect(hint, contains('october'));
      expect(hint, contains('december'));
      expect(hint, contains('january'));
    });

    test('tobacco stage boundaries and contiguity', () {
      final p = profileFor('tobacco')!;
      expect(p.typicalDuration, 175);
      checkTable(p.stages, 175, 'tobacco');
      expect(p.stages.first.name, 'Establishment');
      expect(startOf(p.stages, 'Establishment'), 1);
      expect(endOf(p.stages, 'Establishment'), 20);
      expect(startOf(p.stages, 'Vegetative growth'), 21);
      expect(endOf(p.stages, 'Vegetative growth'), 70);
      expect(startOf(p.stages, 'Topping and flowering'), 71);
      expect(endOf(p.stages, 'Topping and flowering'), 100);
      expect(startOf(p.stages, 'Leaf ripening and harvest'), 101);
      expect(endOf(p.stages, 'Leaf ripening and harvest'), 175);
    });

    test('tobacco window is KP December-January and wraps the year', () {
      final p = profileFor('tobacco')!;
      expect(p.sowingWindows.length, 1);
      final win = p.sowingWindows.single;
      expect(win.province, Province.kp);
      expect([win.startMonth, win.startDay, win.endMonth, win.endDay],
          [12, 1, 1, 31]);
      expect(win.wrapsYear, isTrue);
      expect(win.contains(DateTime(2026, 12, 20)), isTrue);
      expect(win.contains(DateTime(2027, 1, 20)), isTrue);
      expect(win.contains(DateTime(2026, 2, 1)), isFalse);
      expect(p.effectiveWindow(Province.kp), isNotNull);
      for (final prov in [Province.punjab, Province.sindh, Province.balochistan]) {
        expect(p.effectiveWindow(prov), isNull, reason: prov.label);
      }
    });

    test('tobacco note says harvest runs in rounds until about June', () {
      final note = profileFor('tobacco')!.note!.toLowerCase();
      expect(note, contains('continues in several rounds until about june'));
    });

    test('tobacco note covers licensing, rounds and curing', () {
      final note = profileFor('tobacco')!.note!.toLowerCase();
      expect(note, contains('licensed'));
      expect(note, contains('company supervision'));
      expect(note, contains('april'));
      expect(note, contains('june'));
      expect(note, contains('rounds'));
      expect(note, contains('curing'));
      expect(note, contains('barns'));
    });

    // ── the set ───────────────────────────────────────────────────────
    test('the confidence set now has mango at medium too', () {
      final by = {
        for (final c in modelClasses) c: profileFor(c)!.confidence
      };
      expect(by['wheat'], Confidence.high);
      expect(by['rice'], Confidence.high);
      expect(by['maize'], Confidence.high);
      for (final c in
          ['chickpea', 'cotton', 'mango', 'mustard', 'onion', 'sugarcane']) {
        expect(by[c], Confidence.medium, reason: c);
      }
      final low = modelClasses
          .where((c) => by[c] == Confidence.low)
          .toList();
      expect(low.length, 21, reason: '21 low-confidence crops');
    });

    test('the crop list still has exactly thirty entries', () {
      expect(modelClasses.length, 30);
      expect(modelClasses.toSet().length, 30, reason: 'no duplicates');
      for (final c in ['sunflower', 'sorghum', 'tobacco']) {
        expect(profileFor(c), isNotNull, reason: c);
        expect(profileFor(c)!.verified, isFalse, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('G. multi-cut crops', () {
    test('the flag is on the fodder season, not the grain one', () {
      final p = profileFor('sorghum')!;
      expect(p.variantByName('Fodder')!.multiCut, isTrue);
      expect(p.variantByName('Grain')!.multiCut, isFalse);
      expect(p.isMultiCut(variantName: 'Fodder'), isTrue);
      expect(p.isMultiCut(variantName: 'Grain'), isFalse);
      expect(p.isMultiCut(), isFalse, reason: 'no season chosen yet');
    });

    test('the perennial fruits that regrow are multi-cut', () {
      // Banana is cut back after one bunch and the sucker carries the next;
      // papaya keeps fruiting for years after its first harvest.
      for (final c in ['banana', 'papaya']) {
        final p = profileFor(c)!;
        expect(p.multiCut, isTrue, reason: c);
        expect(p.isMultiCut(), isTrue, reason: c);
      }
    });

    test('the temperate perennials are not multi-cut', () {
      // These all follow one annual dormancy to harvest cycle.
      for (final c in ['apple', 'pomegranate', 'grapes']) {
        expect(profileFor(c)!.multiCut, isFalse, reason: c);
      }
    });

    test('only the three intended crops carry a multi-cut flag', () {
      // Profile-level: the tropical perennials. Sorghum carries it on the
      // fodder season instead, so with no season chosen it reads false.
      for (final c in modelClasses) {
        final p = profileFor(c)!;
        expect(p.multiCut, {'banana', 'papaya'}.contains(c), reason: c);
        for (final v in p.variants) {
          final want = c == 'sorghum' && v.name == 'Fodder';
          expect(v.multiCut, want, reason: '$c / ${v.name}');
        }
      }
    });

    test('banana and papaya still report being past their first harvest', () {
      // Suppression is UI copy only; the underlying lookup stays truthful.
      final banana = profileFor('banana')!;
      expect(banana.typicalDuration, 400);
      expect(banana.isPastLastStage(401), isTrue);
      expect(banana.stageForDay(401), isNull);
      expect(banana.isPastLastStage(400), isFalse);
      expect(banana.stageForDay(400)!.name, 'Harvest');

      final papaya = profileFor('papaya')!;
      expect(papaya.isPastLastStage(400), isTrue);
      expect(papaya.stageForDay(400), isNull);
      expect(papaya.isPastLastStage(300), isFalse);
      expect(papaya.stageForDay(300)!.name, 'First harvest');
    });

    test('fodder still reports being past its first cut', () {
      final p = profileFor('sorghum')!;
      // The suppression is in the UI copy, not in the underlying stage lookup.
      expect(p.isPastLastStage(61, variantName: 'Fodder'), isTrue);
      expect(p.stageForDay(61, variantName: 'Fodder'), isNull);
    });

    test('grain sorghum keeps the normal past-the-end behaviour', () {
      final p = profileFor('sorghum')!;
      expect(p.isPastLastStage(106, variantName: 'Grain'), isTrue);
      expect(p.stageForDay(106, variantName: 'Grain'), isNull);
      // Inside the cycle the grain crop is unaffected by the flag.
      expect(p.isPastLastStage(105, variantName: 'Grain'), isFalse);
      expect(p.stageForDay(105, variantName: 'Grain')!.name, 'Maturity');
      expect(p.isPastLastStage(71, variantName: 'Grain'), isFalse);
      expect(p.stageForDay(71, variantName: 'Grain')!.name,
          'Heading and flowering');
    });

    test('the multi-cut copy avoids harvest wording and has no digits', () {
      final p = profileFor('sorghum')!;
      final badge = p.multiCutBadge.toLowerCase();
      expect(badge, isNot(contains('harvest')));
      expect(badge, contains('cut'));
      expect(badge, contains('regrows'));
      final note = p.multiCutNote.toLowerCase();
      expect(note, contains('cut early'));
      expect(note, contains('regrows'));
      expect(note, contains('later cuttings'));
      expect(RegExp(r'\\d').hasMatch(p.multiCutBadge), isFalse);
      expect(RegExp(r'\\d').hasMatch(p.multiCutNote), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('H. unsourced minor crops', () {
    const unsourced = 'No Pakistani stage source was found; this is general '
        'guidance and timing varies widely by variety.';

    test('each minor crop carries the unsourced caveat', () {
      for (final c in ['pigeonpeas', 'mothbeans', 'jute', 'kidneybeans']) {
        final note = profileFor(c)!.note;
        expect(note, isNotNull, reason: c);
        expect(note, contains(unsourced), reason: c);
      }
    });

    test('pigeonpeas also gives the variety-dependent range', () {
      final note = profileFor('pigeonpeas')!.note!;
      expect(note, contains('one hundred and ten'));
      expect(note, contains('two hundred days or more'));
      expect(note, contains('depending on the variety'));
    });

    test('the minor crops stay low confidence with no windows', () {
      for (final c in ['pigeonpeas', 'mothbeans', 'jute', 'kidneybeans']) {
        final p = profileFor(c)!;
        expect(p.confidence, Confidence.low, reason: c);
        expect(p.sowingWindows, isEmpty, reason: c);
        expect(p.verified, isFalse, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('I. perennial fruit crops', () {
    List<MonthStage> monthsOf(String c) => profileFor(c)!.monthStages;

    /// Every calendar month falls in exactly one stage.
    void checkMonthCoverage(String c) {
      final stages = monthsOf(c);
      final owner = <int, List<String>>{};
      for (final st in stages) {
        final a = st.startMonth, b = st.endMonth;
        final span = a <= b
            ? List.generate(b - a + 1, (i) => a + i)
            : [...List.generate(13 - a, (i) => a + i), ...List.generate(b, (i) => i + 1)];
        for (final m in span) {
          owner.putIfAbsent(m, () => []).add(st.name);
        }
      }
      expect(owner.keys.toSet(), {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
          reason: c);
      for (final e in owner.entries) {
        expect(e.value.length, 1, reason: '$c month ${e.key}: ${e.value}');
      }
      // Contiguous: each stage starts the month after the previous ends.
      for (var i = 1; i < stages.length; i++) {
        expect(stages[i].startMonth, stages[i - 1].endMonth + 1,
            reason: '$c: ${stages[i].name} follows ${stages[i - 1].name}');
      }
    }

    void checkDasShape(String c, int total) {
      final st = profileFor(c)!.stages;
      expect(st.first.startDay, 1, reason: c);
      for (var i = 1; i < st.length; i++) {
        expect(st[i].startDay, st[i - 1].endDay + 1,
            reason: '$c: ${st[i].name}');
      }
      expect(st.last.endDay, total, reason: c);
      for (var d = 1; d <= total; d++) {
        expect(st.where((x) => x.contains(d)).length, 1, reason: '$c day $d');
      }
    }

    // ── apple ─────────────────────────────────────────────────────────
    test('apple covers the calendar once, contiguously', () {
      checkMonthCoverage('apple');
      expect(profileFor('apple')!.isMonthBased, isTrue);
    });

    test('apple stage boundaries', () {
      final st = monthsOf('apple');
      int startOf(String n) => st.firstWhere((x) => x.name == n).startMonth;
      int endOf(String n) => st.firstWhere((x) => x.name == n).endMonth;
      expect(startOf('Dormancy'), 11);
      expect(endOf('Dormancy'), 2, reason: 'wraps the year');
      expect(startOf('Bud break'), 3);
      expect(endOf('Bud break'), 3);
      expect(startOf('Flowering'), 4);
      expect(endOf('Flowering'), 4);
      expect(startOf('Fruit set'), 5);
      expect(endOf('Fruit set'), 5);
      expect(startOf('Fruit development'), 6);
      expect(endOf('Fruit development'), 7);
      expect(startOf('Ripening and harvest'), 8);
      expect(endOf('Ripening and harvest'), 10);
      expect(monthsOf('apple').map((x) => x.name),
          isNot(contains('Harvest')), reason: 'ripening and harvest merged');
    });

    test('pomegranate covers the calendar once, contiguously', () {
      checkMonthCoverage('pomegranate');
    });

    test('pomegranate stage boundaries', () {
      final st = monthsOf('pomegranate');
      int startOf(String n) => st.firstWhere((x) => x.name == n).startMonth;
      int endOf(String n) => st.firstWhere((x) => x.name == n).endMonth;
      expect(startOf('Dormancy and pruning'), 12);
      expect(endOf('Dormancy and pruning'), 2);
      expect(startOf('Flowering'), 3);
      expect(endOf('Flowering'), 4);
      expect(startOf('Fruit set'), 5);
      expect(startOf('Fruit development'), 6);
      expect(endOf('Fruit development'), 8);
      expect(startOf('Harvest'), 9);
      expect(endOf('Harvest'), 11);
    });

    test('pomegranate Punjab planting window is February-March', () {
      final p = profileFor('pomegranate')!;
      expect(p.sowingWindows.length, 1);
      final w = p.sowingWindows.single;
      expect(w.province, Province.punjab);
      expect([w.startMonth, w.startDay, w.endMonth, w.endDay], [2, 1, 3, 31]);
      expect(w.wrapsYear, isFalse);
      expect(w.contains(DateTime(2026, 2, 15)), isTrue);
      expect(w.contains(DateTime(2026, 4, 1)), isFalse);
      expect(p.effectiveWindow(Province.sindh), isNull);
    });

    test('pomegranate dormancy irrigation withholds water on purpose', () {
      final irr = profileFor('pomegranate')!.irrigation.values
          .join(' ')
          .toLowerCase();
      expect(irr, contains('withheld'));
      expect(irr, contains('flower'));
      expect(irr, contains('cracking'));
    });

    // ── grapes ────────────────────────────────────────────────────────
    test('grapes covers the calendar once, contiguously', () {
      checkMonthCoverage('grapes');
    });

    test('grapes stage boundaries', () {
      final st = monthsOf('grapes');
      expect(st.length, 7);
      int startOf(String n) => st.firstWhere((x) => x.name == n).startMonth;
      int endOf(String n) => st.firstWhere((x) => x.name == n).endMonth;
      expect(startOf('Dormancy'), 11);
      expect(endOf('Dormancy'), 2);
      expect(startOf('Bud break'), 3);
      expect(startOf('Shoot growth'), 4);
      expect(startOf('Flowering'), 5);
      expect(startOf('Fruit set and berry growth'), 6);
      expect(endOf('Fruit set and berry growth'), 6);
      expect(startOf('Ripening and early harvest'), 7);
      expect(endOf('Ripening and early harvest'), 8);
      expect(startOf('Main and late harvest'), 9);
      expect(endOf('Main and late harvest'), 10);
    });

    test('grapes lists Balochistan first', () {
      final p = profileFor('grapes')!;
      expect(p.provinces.first, Province.balochistan);
      expect(p.provinces.toSet(),
          {Province.balochistan, Province.kp, Province.punjab});
    });

    test('papaya has no sowing window', () {
      expect(profileFor('papaya')!.sowingWindows, isEmpty);
    });

    test('pomegranate drops Sindh and keeps Punjab and Balochistan', () {
      final p = profileFor('pomegranate')!;
      expect(p.provinces.toSet(), {Province.punjab, Province.balochistan});
      expect(p.provinces, isNot(contains(Province.sindh)));
      // Harvest still runs September to November.
      final harvest =
          p.monthStages.firstWhere((s) => s.name == 'Harvest');
      expect(harvest.startMonth, 9);
      expect(harvest.endMonth, 11);
    });

    test('apple note names both belts and flags the missing bloom date', () {
      final note = profileFor('apple')!.note!;
      for (final w in [
        'Quetta', 'Pishin', 'Killa Saifullah', 'Mastung', 'Ziarat',
        'Swat', 'Dir', 'Chitral',
      ]) {
        expect(note, contains(w), reason: w);
      }
      expect(note, contains('July to October'));
      expect(note, contains('bloom date was not found in a Pakistani source'));
      expect(note, isNot(contains('general guidance only')));
    });

    test('grapes note gives the Balochistan belt and the Swat season', () {
      final note = profileFor('grapes')!.note!;
      for (final w in ['Quetta', 'Mastung', 'Kalat', 'Pishin', 'Killa Abdullah']) {
        expect(note, contains(w), reason: w);
      }
      expect(note, contains('July to October'));
      expect(note, contains('Swat season is August to September'));
      expect(note, contains('varies widely by cultivar'));
      expect(note, contains('not found in a Pakistani source'));
    });

    test('papaya note records the planting disagreement and the fast end', () {
      final note = profileFor('papaya')!.note!;
      expect(note, contains('nursery sown in March'));
      expect(note, contains('February to March'));
      expect(note, contains('September to November'));
      expect(note, contains('eight months to eighteen months or more'));
      expect(note, contains('the fast end'));
    });

    test('grapes ripening irrigation is site dependent', () {
      final irr = profileFor('grapes')!.irrigation.values.join(' ').toLowerCase();
      expect(irr, contains('withhold water from veraison'));
      expect(irr, contains('cooler valley'));
    });

    // ── banana ────────────────────────────────────────────────────────
    test('banana stages are contiguous and end at four hundred', () {
      checkDasShape('banana', 400);
      final st = profileFor('banana')!.stages;
      int startOf(String n) => st.firstWhere((x) => x.name == n).startDay;
      int endOf(String n) => st.firstWhere((x) => x.name == n).endDay;
      expect(startOf('Sucker establishment'), 1);
      expect(endOf('Sucker establishment'), 45);
      expect(startOf('Vegetative growth'), 46);
      expect(endOf('Vegetative growth'), 270);
      expect(startOf('Flowering'), 271);
      expect(endOf('Flowering'), 300);
      expect(startOf('Fruit development'), 301);
      expect(endOf('Fruit development'), 375);
      expect(startOf('Harvest'), 376);
      expect(endOf('Harvest'), 400);
    });

    test('banana has Sindh planting windows and a yield note', () {
      final p = profileFor('banana')!;
      expect(p.sowingWindows.length, 2);
      final spring = p.sowingWindows.first;
      expect(spring.province, Province.sindh);
      expect([spring.startMonth, spring.startDay, spring.endMonth, spring.endDay],
          [2, 1, 3, 31]);
      final autumn = p.sowingWindows.last;
      expect(autumn.province, Province.sindh);
      expect([autumn.startMonth, autumn.startDay, autumn.endMonth, autumn.endDay],
          [8, 1, 9, 30]);
      expect(p.windowNotes.join(' '),
          contains('The spring planting gives higher yields.'));
    });

    test('banana now covers four provinces', () {
      final p = profileFor('banana')!;
      expect(p.provinces.toSet(), {
        Province.sindh,
        Province.balochistan,
        Province.kp,
        Province.punjab,
      });
    });

    test('banana note records the source disagreement', () {
      final note = profileFor('banana')!.note!;
      expect(note, contains('eleven to fourteen months'));
      expect(note, contains('two to three ratoon crops'));
      expect(note, contains('Sindh holds almost all of the crop'));
    });

    test('banana potassium advice points at bunch weight', () {
      final fert = profileFor('banana')!.fertilizer.values.join(' ').toLowerCase();
      expect(fert, contains('potassium'));
      expect(fert, contains('bunch weight'));
    });

    // ── papaya ────────────────────────────────────────────────────────
    test('papaya is counted from transplanting', () {
      final p = profileFor('papaya')!;
      expect(p.dateAnchor, DateAnchor.transplanting);
      expect(p.isTransplanted, isTrue);
      expect(p.dateFieldLabel, 'Transplanting date');
      expect(p.noDateLabel, 'Set transplanting date');
      expect(p.multiCut, isTrue);
      expect(p.typicalDuration, 300);
    });

    test('papaya stages are contiguous and end at three hundred', () {
      checkDasShape('papaya', 300);
      final st = profileFor('papaya')!.stages;
      int startOf(String n) => st.firstWhere((x) => x.name == n).startDay;
      int endOf(String n) => st.firstWhere((x) => x.name == n).endDay;
      expect(startOf('Establishment'), 1);
      expect(endOf('Establishment'), 30);
      expect(startOf('Vegetative growth'), 31);
      expect(endOf('Vegetative growth'), 150);
      expect(startOf('Flowering'), 151);
      expect(endOf('Flowering'), 180);
      expect(startOf('Fruit set and development'), 181);
      expect(endOf('Fruit set and development'), 270);
      expect(startOf('First harvest'), 271);
      expect(endOf('First harvest'), 300);
    });

    test('papaya keeps feeding after the first harvest', () {
      final fert = profileFor('papaya')!.fertilizer.values.join(' ').toLowerCase();
      expect(fert, contains('after the first harvest'));
      expect(fert, contains('boron'));
    });

    // ── the set ───────────────────────────────────────────────────────
    test('all five researched fruits stay low confidence and unverified', () {
      for (final c in ['apple', 'pomegranate', 'grapes', 'banana', 'papaya']) {
        final p = profileFor(c)!;
        expect(p.confidence, Confidence.low, reason: c);
        expect(p.verified, isFalse, reason: c);
        expect(p.note, isNotNull, reason: c);
      }
    });

    test('the temperate fruits are month-based, the tropical ones are not', () {
      for (final c in ['apple', 'pomegranate', 'grapes']) {
        expect(profileFor(c)!.isMonthBased, isTrue, reason: c);
        expect(profileFor(c)!.monthStages, isNotEmpty, reason: c);
      }
      for (final c in ['banana', 'papaya']) {
        expect(profileFor(c)!.isMonthBased, isFalse, reason: c);
        expect(profileFor(c)!.stages, isNotEmpty, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('N. tree crops after the note rewrite', () {
    const treeCrops = [
      'apple', 'mango', 'orange', 'pomegranate', 'grapes', 'banana', 'papaya',
    ];

    /// A note is at most three sentences, counting only full stops that are
    /// not part of an abbreviation.
    int sentenceCount(String text) {
      final stripped =
          text.replaceAll(RegExp(r'\b\w+\.\w+'), '').replaceAll('etc.', '');
      return stripped.split('.').where((s) => s.trim().isNotEmpty).length;
    }

    test('every tree-crop note is at most three sentences', () {
      for (final c in treeCrops) {
        final note = profileFor(c)!.note;
        expect(note, isNotNull, reason: c);
        expect(sentenceCount(note!), lessThanOrEqualTo(3),
            reason: '$c has ${sentenceCount(note)} sentences');
      }
    });

    test('the tree-crop notes are all digit free', () {
      for (final c in treeCrops) {
        expect(RegExp(r'\d').hasMatch(profileFor(c)!.note!), isFalse, reason: c);
      }
    });

    test('no tree-crop note names an unsupported variety or place', () {
      // Names that came from search results rather than a source we relied
      // on, and that no note is allowed to carry. District names the user
      // supplied are fine and are asserted by the per-crop tests instead.
      const banned = [
        'White Chaunsa', 'Barkhan', 'Duki', 'Khuzdar', 'Azad Kashmir',
        'Naseerabad', 'King', 'Willow Leaf',
      ];
      for (final c in treeCrops) {
        final note = profileFor(c)!.note!;
        for (final b in banned) {
          expect(note, isNot(contains(b)), reason: '$c mentions $b');
        }
      }
    });

    test('mango keeps only the supported calendar facts', () {
      final note = profileFor('mango')!.note!;
      expect(note, contains('mid-May'));
      expect(note, contains('June'));
      expect(note, contains('July'));
      expect(note, contains('August'));
      expect(note.toLowerCase(), contains('storms'));
      expect(note, isNot(contains('White Chaunsa')));
    });

    test('mango is medium confidence and the six-stage calendar', () {
      final p = profileFor('mango')!;
      expect(p.confidence, Confidence.medium);
      expect(p.monthStages.map((s) => s.name), [
        'Winter rest',
        'Flowering',
        'Fruit set',
        'Fruit development and early harvest',
        'Main harvest',
        'Post-harvest flush',
      ]);
      int m(String n) => p.monthStages.firstWhere((s) => s.name == n).startMonth;
      expect(m('Winter rest'), 11);
      expect(m('Flowering'), 1);
      expect(m('Fruit set'), 4);
      expect(m('Fruit development and early harvest'), 5);
      expect(m('Main harvest'), 7);
      expect(m('Post-harvest flush'), 9);
    });

    test('orange leads with harvest and runs to October', () {
      final p = profileFor('orange')!;
      expect(p.monthStages.map((s) => s.name), [
        'Harvest',
        'Late harvest and flowering',
        'Fruit set',
        'Fruit growth',
      ]);
      expect(p.monthStages.first.startMonth, 11);
      expect(p.monthStages.first.wrapsYear, isTrue,
          reason: 'harvest runs November into January');
      expect(p.monthStages.last.endMonth, 10);
      expect(p.confidence, Confidence.low);
    });

    test('pomegranate names the Balochistan belt and the Punjab varieties', () {
      final note = profileFor('pomegranate')!.note!;
      for (final w in [
        'Pishin', 'Killa Saifullah', 'Loralai', 'Mastung', 'Quetta', 'Harnai',
      ]) {
        expect(note, contains(w), reason: w);
      }
      expect(note, contains('Pearl'));
      expect(note, contains('Golden'));
      expect(note, contains('February to March'));
      expect(note, contains('southern and central Punjab'));
      // Dropped in this pass.
      expect(note, isNot(contains('Barkhan')));
      expect(note, isNot(contains('Duki')));
      expect(note, isNot(contains('Sindh')));
    });

    test('each note says plainly what is and is not sourced', () {
      // The four that still have no stage source say so; the ones that do
      // name the specific gap instead.
      expect(profileFor('banana')!.note!,
          isNot(contains('No Pakistani stage source was found')));
      expect(profileFor('papaya')!.note!,
          isNot(contains('No Pakistani stage source was found')));
      for (final c in ['apple', 'grapes']) {
        final note = profileFor(c)!.note!.toLowerCase();
        // Apple has no bloom date, grapes no bud-break or bloom month; both
        // must name the specific gap rather than complain in general terms.
        // The word order differs, so match on the two halves.
        expect(note, contains('pakistani'), reason: c);
        expect(note, contains('not found'), reason: '$c must name the gap');
        expect(note, contains('source'), reason: '$c must name the source');
      }
      expect(profileFor('apple')!.note!,
          contains('bloom date was not found in a Pakistani source'));
      expect(profileFor('grapes')!.note!,
          contains('not found in a Pakistani source'));
    });

    test('grapes now includes Balochistan', () {
      final p = profileFor('grapes')!;
      expect(p.provinces, contains(Province.balochistan));
      expect(p.provinces.toSet(),
          {Province.kp, Province.punjab, Province.balochistan});
      expect(p.note, contains('Balochistan'));
    });

    test('banana uses planting wording throughout', () {
      final p = profileFor('banana')!;
      expect(p.dateAnchor, DateAnchor.planting);
      expect(p.isTransplanted, isFalse, reason: 'planting is not transplanting');
      expect(p.anchorNoun, 'planting');
      expect(p.anchorNounTitle, 'Planting');
      expect(p.noDateLabel, 'Set planting date');
      expect(p.dateFieldLabel, 'Planting date');
      expect(p.dateHint, contains('no sowing date'),
          reason: 'the hint explains why sowing is the wrong word');
      expect(p.dateHint, isNot(contains('Sowing date')));
    });

    test('banana badge and note use the continuous wording', () {
      final p = profileFor('banana')!;
      expect(p.continuousNote, isNotNull);
      expect(p.pastFirstBadge, 'Harvest, then suckers continue');
      expect(p.pastFirstNote, isNot(contains('multi-cut')));
      expect(p.pastFirstNote, isNot(contains('cut early')));
      expect(p.pastFirstNote, contains('one bunch'));
      expect(p.pastFirstNote, contains('sucker'));
      expect(p.pastFirstBadge, isNot(contains('Cut early')));
    });

    test('papaya badge and note use the continuous wording', () {
      final p = profileFor('papaya')!;
      expect(p.continuousNote, isNotNull);
      expect(p.pastFirstBadge, 'Fruiting continues');
      expect(p.pastFirstNote, isNot(contains('multi-cut')));
      expect(p.pastFirstNote, isNot(contains('cut early')));
      expect(p.pastFirstNote, contains('first harvest'));
    });

    test('neither tropical fruit shows the fodder wording', () {
      for (final c in ['banana', 'papaya']) {
        final p = profileFor(c)!;
        for (final text in [
          p.pastFirstBadge,
          p.pastFirstNote,
          p.multiCutTitle,
          p.note!,
        ]) {
          expect(text.toLowerCase(), isNot(contains('multi-cut')), reason: c);
          expect(text.toLowerCase(), isNot(contains('regrows')), reason: c);
          expect(text.toLowerCase(), isNot(contains('cutting')), reason: c);
        }
      }
    });

    test('both tropical fruits still suppress the harvest prompt', () {
      for (final c in ['banana', 'papaya']) {
        final p = profileFor(c)!;
        expect(p.multiCut, isTrue, reason: c);
        expect(p.isMultiCut(), isTrue, reason: c);
        expect(p.isPastLastStage(p.typicalDuration + 10), isTrue,
            reason: '$c is past the end, so the prompt path is live');
        expect(p.multiCutBadge, 'Cut early \u00b7 regrows',
            reason: 'the fodder default, unused by these two');
        expect(p.pastFirstBadge, isNot(p.multiCutBadge), reason: c);
      }
    });

    test('fodder sorghum keeps the cut-and-regrow default', () {
      final p = profileFor('sorghum')!;
      expect(p.variantByName('Fodder')!.multiCut, isTrue);
      expect(p.continuousNote, isNull, reason: 'sorghum uses the default');
      expect(p.pastFirstBadge, p.multiCutBadge);
      expect(p.pastFirstNote, p.multiCutNote);
      expect(p.multiCutTitle, contains('regrowing'));
    });

    test('the tree crops are still the right tracking mode', () {
      for (final c in ['apple', 'mango', 'orange', 'pomegranate', 'grapes']) {
        expect(profileFor(c)!.isMonthBased, isTrue, reason: c);
      }
      for (final c in ['banana', 'papaya']) {
        expect(profileFor(c)!.isMonthBased, isFalse, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('O. the district names that came back', () {
    /// The seven names no note is allowed to carry.
    const banned = [
      'Barkhan', 'Duki', 'Khuzdar', 'Azad Kashmir', 'Naseerabad', 'King',
      'Willow Leaf',
    ];

    test('the banned list is exactly the seven kept names', () {
      expect(banned.length, 7);
      for (final b in [
        'Barkhan', 'Duki', 'Khuzdar', 'Azad Kashmir', 'Naseerabad', 'King',
        'Willow Leaf',
      ]) {
        expect(banned, contains(b), reason: b);
      }
    });

    test('no tree-crop note carries a kept-banned name', () {
      for (final c in const [
        'apple', 'mango', 'orange', 'pomegranate', 'grapes', 'banana',
        'papaya',
      ]) {
        final note = profileFor(c)!.note!;
        for (final b in banned) {
          expect(note, isNot(contains(b)), reason: '$c mentions $b');
        }
      }
    });

    test('the allowed district names are now usable', () {
      // These were banned in an earlier pass and are now permitted, so a
      // regression that re-bans them would fail here.
      const allowed = [
        'Kinnow', 'Thatta', 'Badin', 'Hyderabad', 'Mirpurkhas', 'Nawabshah',
        'Karachi', 'Malir', 'Multan', 'Rahim Yar Khan',
      ];
      for (final a in allowed) {
        expect(banned, isNot(contains(a)), reason: '$a must not be banned');
      }
    });

    test('orange note names Kinnow and the verified harvest window', () {
      final note = profileFor('orange')!.note!;
      expect(note, contains('Kinnow'));
      expect(note, contains('mandarin'));
      expect(note, contains('most of the citrus grown in Punjab'));
      expect(note, contains('December to February'));
      expect(note, contains('mid-January to mid-February'));
      expect(note, contains('depends on the variety'));
      expect(note, isNot(contains('shears')), reason: 'dropped this pass');
    });

    test('banana note names the lower Sindh belt', () {
      final note = profileFor('banana')!.note!;
      for (final w in [
        'Thatta', 'Badin', 'Hyderabad', 'Mirpurkhas', 'Nawabshah',
      ]) {
        expect(note, contains(w), reason: w);
      }
      expect(note, contains('lower Sindh'));
      // The source disagreement from the previous pass stays.
      expect(note, contains('eleven to fourteen months'));
      expect(note, contains('two to three ratoon crops'));
    });

    test('papaya note names the commercial orchards', () {
      final note = profileFor('papaya')!.note!;
      expect(note, contains('Commercial orchards'));
      expect(note, contains('Malir'));
      expect(note, contains('Karachi'));
      expect(note, contains('Thatta'));
      // The planting disagreement and the fast-end caveat stay.
      expect(note, contains('nursery sown in March'));
      expect(note, contains('eight months to eighteen months or more'));
      expect(note, contains('the fast end'));
    });

    test('the three rewritten notes are still three sentences or fewer', () {
      int sentences(String text) {
        final stripped = text
            .replaceAll(RegExp(r'\b\w+\.\w+'), '')
            .replaceAll('etc.', '');
        return stripped.split('.').where((s) => s.trim().isNotEmpty).length;
      }
      for (final c in ['orange', 'banana', 'papaya']) {
        final note = profileFor(c)!.note!;
        expect(sentences(note), lessThanOrEqualTo(3),
            reason: '$c has ${sentences(note)}');
        expect(RegExp(r'\d').hasMatch(note), isFalse, reason: c);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('CropTrackingService', () {
    test('stores, reads and clears the anchor date', () async {
      expect(await tracking.getSowingDate('wheat'), isNull);
      await tracking.setSowingDate('wheat', DateTime(2026, 11, 15));
      expect(await tracking.getSowingDate('wheat'), DateTime(2026, 11, 15));
      await tracking.clearSowingDate('wheat');
      expect(await tracking.getSowingDate('wheat'), isNull);
    });

    test('drops the time component', () async {
      await tracking.setSowingDate('rice', DateTime(2026, 5, 1, 22, 30));
      final read = await tracking.getSowingDate('rice');
      expect(read!.hour, 0);
      expect(read.minute, 0);
    });

    test('date keys are per crop and case-insensitive', () async {
      await tracking.setSowingDate('grapes', DateTime(2026, 11, 2));
      expect(await tracking.getSowingDate('GRAPES'), isNotNull);
      expect(CropTrackingService.keyFor('Coffee'), 'sowing_date_coffee');
    });

    test('stores and clears the season variant per crop', () async {
      expect(await tracking.getSeasonVariant('maize'), isNull);
      await tracking.setSeasonVariant('maize', 'Autumn');
      expect(await tracking.getSeasonVariant('maize'), 'Autumn');
      await tracking.setSeasonVariant('maize', null);
      expect(await tracking.getSeasonVariant('maize'), isNull);
    });

    test('stores and reads the province', () async {
      expect(await tracking.getProvince(), isNull);
      await tracking.setProvince(Province.kp);
      expect(await tracking.getProvince(), Province.kp);
      await tracking.setProvince(Province.sindh);
      expect(await tracking.getProvince(), Province.sindh);
    });

    test('a corrupt or wrongly-typed value reads as unset', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sowing_date_wheat', 'not-a-date');
      expect(await tracking.getSowingDate('wheat'), isNull);
      await prefs.setInt('sowing_date_rice', 7);
      expect(await tracking.getSowingDate('rice'), isNull);
      await prefs.setString(CropTrackingService.provinceKey, 'atlantis');
      expect(await tracking.getProvince(), isNull);
    });

    test('allSowingDates lists only valid sowing_date_ entries', () async {
      await tracking.setSowingDate('wheat', DateTime(2026, 11, 15));
      await tracking.setSowingDate('coconut', DateTime(2026, 1, 5));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notification_history_v1', '[]');
      await prefs.setString('sowing_date_broken', 'nope');
      await prefs.setString('season_variant_maize', 'Autumn');

      final all = await tracking.allSowingDates();
      expect(all.keys.toSet(), {'wheat', 'coconut'});
    });
  });
}
