/// Growth-stage definitions for every crop the SmartCrop model supports,
/// across Pakistan.
///
/// SCOPE AND PROVENANCE - read before trusting any number here
/// ------------------------------------------------------------
/// The ML model and `crop_thresholds.py` contain no temporal information: no
/// sowing date, no days-after-sowing, no phenology, no region. This table is
/// therefore NOT derived from the training dataset. It is hand-authored from
/// Pakistani agronomy (Punjab, Sindh, Khyber Pakhtunkhwa, Balochistan).
///
/// EVERY PROFILE HAS `verified: false`. None of these timelines has been
/// checked by an agronomist, so the UI labels all of it "Draft guidance".
///
/// KNOWN CONFLICT WITH crop_thresholds.py
/// --------------------------------------
/// That backend derives temperature / humidity / soil-moisture from mean +/- 1
/// std of the ML training dataset, which describes the envelope in which the
/// MODEL CALLS A CROP SUITABLE. The `monitoring` targets below describe the
/// conditions to AIM FOR during a stage. These answer different questions and
/// will not agree - most visibly for rice, which is grown puddled and flooded
/// here. See the conflict report. `crop_thresholds.py` remains authoritative
/// for the alert/notification path; the two are deliberately not merged.
library;

// ═══════════════════════════════════════════════════════════════════════════
// REGION
// ═══════════════════════════════════════════════════════════════════════════

/// The four provinces. Used to scope a crop and to pick a sowing window.
enum Province {
  punjab('Punjab'),
  sindh('Sindh'),
  kp('Khyber Pakhtunkhwa'),
  balochistan('Balochistan');

  final String label;

  const Province(this.label);

  static Province? fromName(String? name) {
    if (name == null) return null;
    for (final p in Province.values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// How a crop's season is expressed.
enum TrackingMode {
  /// Sown or planted, tracked in days after the anchor date. Needs a date.
  dasBased,

  /// A standing perennial, tracked by calendar month. No date needed.
  monthBased,
}

/// What the stored date represents. Rice is counted from transplanting, not
/// from sowing, because the nursery is raised separately.
enum DateAnchor { sowing, transplanting, planting }

/// A recommended sowing window for one province, optionally narrowed to a
/// sub-region (Punjab south vs Punjab north, KP plains vs KP hills).
class SowingWindow {
  final Province province;
  final String? region;
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;

  const SowingWindow({
    required this.province,
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
    this.region,
  });

  String get label =>
      region == null ? province.label : '${province.label} $region';

  int get startDayOfYear => _dayOfYear(startMonth, startDay);
  int get endDayOfYear => _dayOfYear(endMonth, endDay);

  /// True when the window crosses New Year, e.g. mid-October to mid-February.
  bool get wrapsYear => endDayOfYear < startDayOfYear;

  bool contains(DateTime date) {
    final doy = _dayOfYear(date.month, date.day);
    if (wrapsYear) return doy >= startDayOfYear || doy <= endDayOfYear;
    return doy >= startDayOfYear && doy <= endDayOfYear;
  }

  String get startLabel => shortDate(startMonth, startDay);
  String get endLabel => shortDate(endMonth, endDay);
}

/// A named season for a crop that is sown twice a year (maize), each with its
/// own stage table, total length and windows.
class SeasonVariant {
  final String name;
  final List<CropStage> stages;
  final int typicalDuration;
  final List<SowingWindow> windows;

  /// Provinces grown in THIS season. Sugarcane spring reaches KP, autumn does
  /// not, so the province list cannot live on the crop alone.
  final List<Province> provinces;

  /// A cut-and-regrow season such as fodder sorghum. The stage table ends at
  /// the first cut, not at harvest, so the normal "past the last stage"
  /// harvest prompt would be wrong for it.
  final bool multiCut;

  /// Season-specific caveat, e.g. the Peshawar valley late-sowing warning.
  final String? regionNote;

  const SeasonVariant({
    required this.name,
    required this.stages,
    required this.typicalDuration,
    required this.windows,
    this.provinces = const [],
    this.multiCut = false,
    this.regionNote,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGES
// ═══════════════════════════════════════════════════════════════════════════

/// Coarse phase a stage belongs to. Advice is written per band rather than per
/// stage so the wording stays consistent and defensible.
enum StageBand { vegetative, reproductive, maturity }

/// How much to trust this profile's timeline.
enum Confidence { low, medium, high }

/// A phenological stage in a days-after-anchor crop.
class CropStage {
  final String name;
  final int startDay;
  final int endDay;
  final StageBand band;
  final String focus;

  const CropStage({
    required this.name,
    required this.startDay,
    required this.endDay,
    required this.band,
    required this.focus,
  });

  int get lengthDays => endDay - startDay + 1;
  bool contains(int day) => day >= startDay && day <= endDay;
}

/// A phenological stage in a month-based perennial. [startMonth] and
/// [endMonth] are 1-12 and the range may wrap the year.
class MonthStage {
  final String name;
  final int startMonth;
  final int endMonth;
  final StageBand band;
  final String focus;

  const MonthStage({
    required this.name,
    required this.startMonth,
    required this.endMonth,
    required this.band,
    required this.focus,
  });

  List<int> get months {
    final out = <int>[];
    var m = startMonth;
    while (true) {
      out.add(m);
      if (m == endMonth) break;
      m = m == 12 ? 1 : m + 1;
      if (out.length > 12) break;
    }
    return out;
  }

  bool get wrapsYear => startMonth > endMonth;
  bool contains(int month) => months.contains(month);

  int monthsUntilStart(int month) {
    if (contains(month)) return 0;
    var n = month;
    for (var i = 0; i < 12; i++) {
      n = n == 12 ? 1 : n + 1;
      if (n == startMonth) return i + 1;
    }
    return 12;
  }
}

/// Conditions worth monitoring during a band.
class MonitoringTarget {
  final int soilMoistureMin;
  final int soilMoistureMax;
  final int tempMin;
  final int tempMax;
  final int humidityMin;
  final int humidityMax;

  const MonitoringTarget({
    required this.soilMoistureMin,
    required this.soilMoistureMax,
    required this.tempMin,
    required this.tempMax,
    required this.humidityMin,
    required this.humidityMax,
  });

  String get soilMoisture => '$soilMoistureMin-$soilMoistureMax %';
  String get temperature => '$tempMin-$tempMax °C';
  String get humidity => '$humidityMin-$humidityMax %';
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// A trackable crop.
///
/// Exactly one of [stages] / [monthStages] is populated, chosen by
/// [trackingMode]. When [variants] is non-empty (maize) the active
/// [stages] and [typicalDuration] are the defaults and callers should use
/// [stagesForVariant] with the season the user selected.
class CropProfile {
  final String name;
  final TrackingMode trackingMode;

  /// Days after the anchor, for [TrackingMode.dasBased] only.
  final List<CropStage> stages;
  final int typicalDuration;

  /// Calendar stages, for [TrackingMode.monthBased] only.
  final List<MonthStage> monthStages;

  /// Two-season crops. Empty for single-season crops.
  final List<SeasonVariant> variants;

  /// Whether Pakistani farmers think about this crop by stage name rather
  /// than by day count.
  final bool calendarMode;

  /// Always false today. Nothing here has been agronomist-checked.
  final bool verified;

  final Confidence confidence;

  /// Provinces where the crop is commonly grown. Empty means it is not a
  /// mainstream crop anywhere in the four provinces, and the UI says so.
  final List<Province> provinces;

  /// Recommended sowing / transplanting windows. Optional - a crop with none
  /// simply never shows the out-of-window warning.
  final List<SowingWindow> sowingWindows;

  /// Seasons that need a second sow to be split by province or zone.
  final List<String> windowNotes;

  /// Display-only override for a province's effective window, keyed by
  /// province.
  ///
  /// Some provinces genuinely have two sub-regions with different windows.
  /// [effectiveWindow] still collapses them into one comparable range for the
  /// `contains` check, but the app can be told to say so. Punjab wheat is
  /// 1 Nov-15 Dec in the central and north and to 30 Dec in the south, which
  /// is clearer as one sentence than as two disconnected ranges.
  final Map<Province, String> windowLabels;

  /// Warning shown only when the chosen anchor date falls AFTER the end of the
  /// recommended window. A date that is merely early does not trigger it - an
  /// early sowing is a different situation and deserves different wording.
  final String? lateSowingWarning;

  /// Whether the stored date is a sowing or a transplanting date.
  final DateAnchor dateAnchor;

  /// Label for the date field on the stage screen.
  final String dateFieldLabel;

  /// Extra guidance shown next to the date field, e.g. the rice nursery note.
  final String? dateHint;

  /// Flooded crops have no meaningful soil-moisture target; the UI shows
  /// [moistureNote] in its place.
  final bool floodedField;
  final String? moistureNote;

  /// General caveat that is not about a region, e.g. "grain crop, not fodder".
  final String? note;

  final Map<StageBand, MonitoringTarget> monitoring;
  final Map<StageBand, String> fertilizer;
  final Map<StageBand, String> irrigation;

  const CropProfile({
    required this.name,
    required this.trackingMode,
    required this.verified,
    required this.confidence,
    required this.provinces,
    required this.monitoring,
    required this.fertilizer,
    required this.irrigation,
    this.stages = const [],
    this.typicalDuration = 0,
    this.monthStages = const [],
    this.variants = const [],
    this.calendarMode = false,
    this.sowingWindows = const [],
    this.windowNotes = const [],
    this.windowLabels = const {},
    this.lateSowingWarning,
    this.multiCut = false,
    this.continuousNote,
    this.dateAnchor = DateAnchor.sowing,
    this.dateFieldLabel = 'Sowing date',
    this.dateHint,
    this.floodedField = false,
    this.moistureNote,
    this.note,
  });

  bool get isMonthBased => trackingMode == TrackingMode.monthBased;
  bool get isTransplanted => dateAnchor == DateAnchor.transplanting;

  /// "sowing", "transplanting" or "planting", so every user-facing string
  /// about the anchor date uses the crop's own wording rather than defaulting
  /// to sowing. Banana is propagated from a sucker, which is neither.
  String get anchorNoun => switch (dateAnchor) {
        DateAnchor.transplanting => 'transplanting',
        DateAnchor.planting => 'planting',
        DateAnchor.sowing => 'sowing',
      };

  /// The anchor noun with a leading capital, for sentence starts.
  String get anchorNounTitle =>
      '${anchorNoun[0].toUpperCase()}${anchorNoun.substring(1)}';

  /// Badge / pill text used when no anchor date has been saved.
  String get noDateLabel => 'Set $anchorNoun date';
  bool get hasVariants => variants.isNotEmpty;

  /// A crop that is cut and allowed to regrow rather than harvested once. Set
  /// on the profile, or per season when only one season is multi-cut.
  final bool multiCut;

  /// Copy for a multi-cut crop that keeps producing after its first harvest,
  /// as opposed to one that is cut and regrows between cuttings. Fodder
  /// sorghum uses the default cut-and-regrow wording; banana and papaya set
  /// this because their cycle is not a series of cuttings.
  final String? continuousNote;

  /// Badge shown once a multi-cut crop is past its first harvest or cut.
  /// Falls back to the cut-and-regrow wording when [continuousNote] is unset.
  String get pastFirstBadge =>
      continuousNote != null ? _continuousBadge : multiCutBadge;

  /// Body text for the multi-cut notice, honouring [continuousNote].
  String get pastFirstNote => continuousNote ?? multiCutNote;

  /// The per-crop badge, taken from [continuousNote] when it is set, so the
  /// badge and the note cannot drift apart.
  String get _continuousBadge =>
      (continuousNote ?? multiCutBadge).split('\n').first;

  /// Heading for the notice shown once a multi-cut crop is past its first
  /// harvest or cut.
  String get multiCutTitle =>
      continuousNote != null ? 'Still producing' : 'First cut done \u00b7 now regrowing';

  /// Whether the season being viewed is a cut-and-regrow one. Resolves to the
  /// variant's own flag when that season sets one, so fodder sorghum can be
  /// multi-cut while grain sorghum is not.
  bool isMultiCut({String? variantName}) {
    if (variantName != null) {
      final v = variantByName(variantName);
      if (v != null) return v.multiCut || multiCut;
    }
    return multiCut;
  }

  /// Badge shown instead of "Check harvest" once a multi-cut crop is past its
  /// first cut.
  String get multiCutBadge => 'Cut early \u00b7 regrows';

  /// Body text for the multi-cut notice.
  String get multiCutNote => 'This is a multi-cut crop. It is cut early and '
      'regrows, and later cuttings follow from the regrowth.';

  /// No province list means the crop is not mainstream in Pakistan.
  bool get isUncommonInPakistan => provinces.isEmpty;

  /// ── Season variants ────────────────────────────────────────────────────

  SeasonVariant? variantByName(String? name) {
    if (name == null || variants.isEmpty) return null;
    for (final v in variants) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// Guesses the season from the anchor date's month. Used to pre-select the
  /// season when a sowing date is set but no explicit choice was made.
  SeasonVariant? suggestedVariantForDate(DateTime date) {
    if (variants.isEmpty) return null;
    final m = date.month;
    for (final v in variants) {
      if (v.windows.any((w) => w.contains(date))) return v;
    }
    // Fall back to the nearest window by month distance.
    SeasonVariant? best;
    var bestDistance = 999;
    for (final v in variants) {
      for (final w in v.windows) {
        final d = _monthDistance(m, w.startMonth);
        if (d < bestDistance) {
          bestDistance = d;
          best = v;
        }
      }
    }
    return best;
  }

  /// Effective stage list for [variantName], falling back to the defaults.
  List<CropStage> stagesForVariant(String? variantName) {
    final v = variantByName(variantName);
    return v?.stages ?? stages;
  }

  int durationForVariant(String? variantName) {
    final v = variantByName(variantName);
    return v?.typicalDuration ?? typicalDuration;
  }

  /// Windows for [variantName], or the crop's own windows for a single-season
  /// crop.
  List<SowingWindow> windowsForVariant(String? variantName) {
    final v = variantByName(variantName);
    return v?.windows ?? sowingWindows;
  }

  /// Provinces for [variantName]. A season variant may narrow the crop's list,
  /// so it wins when present; otherwise the crop-level list applies.
  List<Province> provincesFor(String? variantName) {
    final v = variantByName(variantName);
    if (v != null && v.provinces.isNotEmpty) return v.provinces;
    return provinces;
  }

  // ── Days-after-anchor lookup ───────────────────────────────────────────

  CropStage? stageForDay(int day, {String? variantName}) {
    if (isMonthBased) return null;
    for (final s in stagesForVariant(variantName)) {
      if (s.contains(day)) return s;
    }
    return null;
  }

  CropStage? nextStageAfter(int day, {String? variantName}) {
    if (isMonthBased) return null;
    final list = stagesForVariant(variantName);
    final index = list.indexWhere((s) => s.contains(day));
    if (index == -1 || index + 1 >= list.length) return null;
    return list[index + 1];
  }

  /// True once [day] is past the final stage, so the season has run out and
  /// the farmer should be checking the harvest.
  bool isPastLastStage(int day, {String? variantName}) {
    if (isMonthBased) return false;
    final list = stagesForVariant(variantName);
    if (list.isEmpty) return false;
    return day > list.last.endDay;
  }

  /// Where [daysSince] falls in the cycle. A negative [daysSince] means the
  /// anchor date has not arrived yet, which is a planned sowing rather than an
  /// error.
  CycleStatus cycleStatus(int daysSince, {String? variantName}) {
    if (isMonthBased) return CycleStatus.active;
    if (daysSince < 1) return CycleStatus.upcoming;
    final list = stagesForVariant(variantName);
    if (list.isEmpty) return CycleStatus.upcoming;
    if (daysSince > list.last.endDay) return CycleStatus.complete;
    return CycleStatus.active;
  }

  /// Every stage with its calendar date, counted forward from [anchorDate].
  ///
  /// [daysSince] only marks which milestones have already been reached, so a
  /// planned sowing still produces the full forward schedule.
  List<Milestone> milestonesFrom({
    required DateTime anchorDate,
    required int daysSince,
    String? variantName,
  }) {
    if (isMonthBased) return const [];
    return [
      for (final s in stagesForVariant(variantName))
        Milestone(
          stage: s.name,
          startDay: s.startDay,
          date: stageStartDate(anchorDate: anchorDate, startDay: s.startDay),
          reached: daysSince >= s.startDay,
        ),
    ];
  }

  // ── Month-based lookup ─────────────────────────────────────────────────

  MonthStage? monthStageFor(int month) {
    if (!isMonthBased) return null;
    for (final s in monthStages) {
      if (s.contains(month)) return s;
    }
    return null;
  }

  /// The stage after the one covering [month], wrapping from December to
  /// January.
  MonthStage? nextMonthStageAfter(int month) {
    if (!isMonthBased) return null;
    final index = monthStages.indexWhere((s) => s.contains(month));
    if (index == -1) return null;
    if (index + 1 < monthStages.length) return monthStages[index + 1];
    return monthStages.isEmpty ? null : monthStages.first;
  }

  // ── Sowing window ──────────────────────────────────────────────────────

  /// Every window registered for [province] in the given variant.
  List<SowingWindow> windowsForProvince(Province province, {String? variantName}) {
    return windowsForVariant(variantName)
        .where((w) => w.province == province)
        .toList();
  }

  /// The effective window for [province], collapsing any sub-regions into
  /// one range. Null when the crop has no window for that province.
  SowingWindow? effectiveWindow(Province province, {String? variantName}) {
    final mine = windowsForProvince(province, variantName: variantName);
    if (mine.isEmpty) return null;

    var earliest = mine.first;
    var latest = mine.first;
    for (final w in mine) {
      if (w.startDayOfYear < earliest.startDayOfYear) earliest = w;
      if (w.endDayOfYear > latest.endDayOfYear) latest = w;
    }
    return SowingWindow(
      province: province,
      startMonth: earliest.startMonth,
      startDay: earliest.startDay,
      endMonth: latest.endMonth,
      endDay: latest.endDay,
    );
  }

  /// Whether [date] falls outside the recommended window for [province].
  /// False when no window is defined, so the warning stays silent by default.
  bool isOutsideWindow(DateTime date, Province province, {String? variantName}) {
    final w = effectiveWindow(province, variantName: variantName);
    if (w == null) return false;
    return !w.contains(date);
  }

  /// Text to show for [province]'s window, honouring any
  /// [windowLabels] override.
  String windowLabel(Province province, {String? variantName}) {
    final override = windowLabels[province];
    if (override != null) return override;
    final w = effectiveWindow(province, variantName: variantName);
    if (w == null) return province.label;
    return '${w.startLabel} to ${w.endLabel}';
  }

  /// True when [date] falls AFTER the end of the recommended window.
  ///
  /// The window is treated as an annual cycle rather than a span inside one
  /// calendar year, so this works across New Year without needing the target
  /// season to be known. A date outside the window is classified by whichever
  /// boundary is closer: if fewer days have passed since the window ended than
  /// remain until it opens again, the date is late; otherwise it is early.
  ///
  /// Deliberately not simply "not inside the window". A 20 January sowing of a
  /// November-to-December wheat crop is late, not early, and without the
  /// cyclic comparison those two are indistinguishable.
  ///
  /// The cycle length follows [date]'s year so a leap year does not skew the
  /// comparison by a day after 29 February.
  bool isAfterWindow(DateTime date, Province province, {String? variantName}) {
    final w = effectiveWindow(province, variantName: variantName);
    if (w == null) return false;
    // A date inside the window is neither late nor early.
    if (w.contains(date)) return false;

    final doy = _dayOfYear(date.month, date.day);
    final cycle = _isLeap(date.year) ? 366 : 365;
    final daysSinceEnd = (doy - w.endDayOfYear) % cycle;
    final daysUntilStart = (w.startDayOfYear - doy) % cycle;
    return daysSinceEnd < daysUntilStart;
  }

  /// Longest cycle across the season variants, or [typicalDuration] for a
  /// single-season crop.
  ///
  /// The date picker uses this so switching seasons never needs a wider range
  /// than the picker already allows - sugarcane autumn runs 540 days, which is
  /// what makes the 600-day lower bound necessary.
  int get maxDurationAcrossVariants {
    if (variants.isEmpty) return typicalDuration;
    var longest = typicalDuration;
    for (final v in variants) {
      if (v.typicalDuration > longest) longest = v.typicalDuration;
    }
    return longest;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Non-leap year day-of-year, so a window is stable across years.
int _dayOfYear(int month, int day) {
  const cumulative = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  return cumulative[month - 1] + day;
}

/// Gregorian leap year, used to size the annual cycle in the window
/// comparison so 29 February does not shift it by a day.
bool _isLeap(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int _monthDistance(int a, int b) {
  final d = (a - b).abs();
  return d > 6 ? 12 - d : d;
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Where a crop sits in its cycle relative to the anchor date.
enum CycleStatus {
  /// The anchor date has not arrived yet - a planned sowing.
  upcoming,

  /// Today falls inside the stage table.
  active,

  /// Today is past the final stage, so the harvest window has closed.
  complete,
}

/// One dated milestone in a crop's cycle.
class Milestone {
  final String stage;

  /// Days after the anchor when the stage begins.
  final int startDay;

  /// The calendar date that day falls on.
  final DateTime date;

  /// False while the milestone is still in the future.
  final bool reached;

  const Milestone({
    required this.stage,
    required this.startDay,
    required this.date,
    required this.reached,
  });
}

/// The allowed bounds of the anchor-date picker.
class PickerRange {
  final DateTime first;
  final DateTime last;

  const PickerRange(this.first, this.last);

  bool contains(DateTime d) => !d.isBefore(first) && !d.isAfter(last);

  /// Returns [d] moved inside [first]..[last].
  ///
  /// `showDatePicker` asserts when `initialDate` falls outside the range, so
  /// a saved date from a previous install, a planned sowing, or a device clock
  /// change can never be passed through unclamped.
  DateTime clamp(DateTime d) {
    if (d.isBefore(first)) return first;
    if (d.isAfter(last)) return last;
    return d;
  }
}

/// Range for the anchor-date picker.
///
/// [cycleDays] is the crop's total cycle length. The lower bound is that
/// length plus a buffer, floored at 400 days, so a long crop such as sugarcane
/// or banana can have a whole previous cycle entered. The upper bound allows
/// a sowing planned a little way ahead - a planned date is not an error, it
/// is a plan, and the UI labels it as upcoming.
PickerRange sowingPickerRange({required DateTime today, int cycleDays = 120}) {
  final day = DateTime(today.year, today.month, today.day);
  // Reach back just far enough to review a finished cycle, and forward far
  // enough to plan a sowing. The old back limit was four hundred days, which
  // put most of the previous year's same month on screen: asking for "the
  // twenty-first of October" could silently land a year earlier, and the crop
  // then read as finished. A year of reach-back is the widest this can go
  // without that trap, and only for long-cycle crops that need it.
  final back = cycleDays + 60;
  // Forward is deliberately generous: a date in the future can only ever read
  // as "planned", never as a finished crop, so there is no year-mix-up risk.
  // It has to be long enough to plan a whole season ahead, because a wheat
  // sowing window can run into late December.
  const forward = 120;
  return PickerRange(
    day.subtract(Duration(days: back)),
    day.add(Duration(days: forward)),
  );
}

String shortDate(int month, int day) =>
    (month >= 1 && month <= 12) ? '$day ${_shortMonths[month - 1]}' : '';

/// Full month name for 1-12, guarded against an out-of-range value.
String monthName(int month) =>
    (month >= 1 && month <= 12)
        ? const [
            'January', 'February', 'March', 'April', 'May', 'June', 'July',
            'August', 'September', 'October', 'November', 'December',
          ][month - 1]
        : 'Unknown month';

/// Calendar date on which [stage] begins, given the stored anchor date.
///
/// [anchorDate] is the sowing or transplanting date and [startDay] is
/// days-after-anchor, so the result is `anchorDate + (startDay - 1)` days.
/// Year rollover falls out of the arithmetic rather than being special-cased.
DateTime stageStartDate(
        {required DateTime anchorDate, required int startDay}) =>
    DateTime(anchorDate.year, anchorDate.month, anchorDate.day)
        .add(Duration(days: startDay - 1));

/// Describes when [stage] begins for a days-after-anchor crop.
///
/// Handles the three cases that matter: starting today, starting tomorrow, and
/// starting later. When [anchorDate] is known the phrase carries the actual
/// calendar date; without it, the day-after-anchor number is used instead.
String nextStagePhrase(
  CropStage stage, {
  required int daysSince,
  DateTime? anchorDate,
}) {
  final startsIn = stage.startDay - daysSince;
  if (startsIn <= 0) return 'starts today';
  if (startsIn == 1) return 'starts tomorrow';

  final days = 'starts in $startsIn day${startsIn == 1 ? '' : 's'}';
  if (anchorDate == null) return '$days (around day ${stage.startDay})';
  final on = stageStartDate(anchorDate: anchorDate, startDay: stage.startDay);
  return '$days (around ${shortDate(on.month, on.day)})';
}

/// Describes when [stage] begins for a month-based perennial.
///
/// [currentMonth] is 1-12. The target month can fall in the following year when
/// the stage's start month is earlier in the year than the current one, which
/// is the normal case for a stage that starts after a December stage.
String nextMonthStagePhrase(
  MonthStage stage, {
  required int currentMonth,
}) {
  final months = stage.monthsUntilStart(currentMonth);
  if (months <= 0) return 'starts this month';
  if (months == 1) return 'starts next month (around ${monthName(stage.startMonth)})';

  final rollsOver = stage.startMonth < currentMonth;
  final suffix = rollsOver ? ' next year' : '';
  return 'starts in $months months (around ${monthName(stage.startMonth)}$suffix)';
}

CropStage _d(String name, int a, int b, StageBand band, String focus) =>
    CropStage(name: name, startDay: a, endDay: b, band: band, focus: focus);

MonthStage _m(String name, int a, int b, StageBand band, String focus) =>
    MonthStage(
        name: name, startMonth: a, endMonth: b, band: band, focus: focus);

const _kp = Province.kp;
const _pun = Province.punjab;
const _sin = Province.sindh;
const _bal = Province.balochistan;

// ═══════════════════════════════════════════════════════════════════════════
// THE 30 MODEL CROPS
// ═══════════════════════════════════════════════════════════════════════════

// Not `const`: the _d / _m / _w builders are functions, which are not
// constant expressions.
final Map<String, CropProfile> cropProfiles = {

  // ─── Wheat ──────────────────────────────────────────────────────────────
  'wheat': CropProfile(
    name: 'wheat',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.high,
    calendarMode: true,
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 160,
    stages: [
      _d('Germination', 1, 19, StageBand.vegetative,
          'Stand and early leaf growth'),
      _d('Crown root initiation', 20, 39, StageBand.vegetative,
          'First irrigation must be timed to this stage'),
      _d('Tillering', 40, 59, StageBand.vegetative,
          'Tiller count; last practical point to add nitrogen'),
      _d('Jointing', 60, 84, StageBand.reproductive,
          'Stem elongation; water stress now cuts yield'),
      _d('Flowering', 85, 99, StageBand.reproductive,
          'Grain number is set; drought here is not recoverable'),
      _d('Milk', 100, 119, StageBand.maturity, 'Grain is milky and filling'),
      _d('Dough', 120, 140, StageBand.maturity, 'Kernel firming up'),
      _d('Maturity', 141, 160, StageBand.maturity, 'Ready to harvest'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          region: 'south',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 30),
      SowingWindow(
          province: _pun,
          region: 'central and north (irrigated)',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 15),
      SowingWindow(
          province: _sin,
          region: 'south',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 25),
      SowingWindow(
          province: _sin,
          region: 'north',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 31),
      SowingWindow(
          province: _kp,
          region: 'plains',
          startMonth: 10,
          startDay: 25,
          endMonth: 12,
          endDay: 15),
      SowingWindow(
          province: _kp,
          region: 'hills',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 15),
      SowingWindow(
          province: _bal,
          region: 'plains',
          startMonth: 11,
          startDay: 1,
          endMonth: 12,
          endDay: 15),
    ],
    windowLabels: const {
      Province.punjab:
          '1 Nov-15 Dec (central and north), to 30 Dec in the south',
    },
    lateSowingWarning:
        'Sown after the end of the recommended window. Late-sown wheat runs a '
            'shorter cycle, so the stage dates above run earlier than shown. '
            'Follow the actual field condition rather than the calendar.',
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 60,
          tempMin: 10,
          tempMax: 20,
          humidityMin: 50,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 65,
          tempMin: 12,
          tempMax: 22,
          humidityMin: 45,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 55,
          tempMin: 15,
          tempMax: 28,
          humidityMin: 40,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Apply the full basal dose at sowing, then top-dress nitrogen with '
              'the crown-root and tillering irrigations. Avoid late nitrogen.',
      StageBand.reproductive:
          'Stop nitrogen once jointing starts. A potassium or foliar-urea spray '
              'can help grain set if the crop has been under stress.',
      StageBand.maturity:
          'No further nitrogen. Only potash if a soil test shows a deficit.',
    },
    irrigation: {
      StageBand.vegetative:
          'Four to five irrigations are normal. The critical stages are crown '
              'root initiation, tillering and jointing.',
      StageBand.reproductive:
          'Critical: jointing, flowering and milk. Drought at flowering costs '
              'grain number that no later irrigation can recover.',
      StageBand.maturity:
          'If only three irrigations are possible, use roughly fifteen to '
              'twenty days after sowing, then booting, then milking. Reduce '
              'afterwards; watering after maturity is wasted.',
    },
  ),

  // ─── Rice ───────────────────────────────────────────────────────────────
  'rice': CropProfile(
    name: 'rice',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.high,
    calendarMode: true,
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 115,
    dateAnchor: DateAnchor.transplanting,
    dateFieldLabel: 'Transplanting date',
    dateHint:
        'Stage timing is counted from transplanting, not from sowing. The '
        'nursery is sown roughly thirty to thirty-five days beforehand.',
    floodedField: true,
    moistureNote:
        'Flooded (puddled) field: keep standing water. A soil-moisture target '
        'does not apply to rice - judge by whether the water is standing.',
    stages: [
      _d('Establishment', 1, 10, StageBand.vegetative,
          'Transplant recovery; keep the sheet flooded'),
      _d('Tillering', 11, 35, StageBand.vegetative, 'Active tiller growth'),
      _d('Panicle initiation', 36, 55, StageBand.reproductive,
          'Panicle forming; the main nitrogen split'),
      _d('Booting', 56, 70, StageBand.reproductive,
          'Flag leaf and neck emergence'),
      _d('Heading', 71, 85, StageBand.reproductive, 'Panicles fully out'),
      _d('Flowering', 86, 100, StageBand.reproductive,
          'Anthesis; heat and cold both blank spikelets'),
      _d('Grain filling', 101, 112, StageBand.maturity, 'Kernel weight'),
      _d('Maturity', 113, 115, StageBand.maturity, 'Drain before harvest'),
    ],
    // These are transplanting windows, not nursery windows: the app counts
    // from the day the seedling goes into the main field.
    sowingWindows: const [
      SowingWindow(
          province: _sin,
          startMonth: 5,
          startDay: 1,
          endMonth: 6,
          endDay: 15),
      SowingWindow(
          province: _bal,
          startMonth: 5,
          startDay: 1,
          endMonth: 6,
          endDay: 15),
      SowingWindow(
          province: _pun,
          startMonth: 6,
          startDay: 1,
          endMonth: 7,
          endDay: 31),
      SowingWindow(
          province: _kp,
          startMonth: 6,
          startDay: 15,
          endMonth: 7,
          endDay: 15),
    ],
    windowNotes: const [
      'These are transplanting dates. The nursery is sown well before: from '
          'mid-May in Punjab for coarse and hybrid types, and from late May or '
          'early June for the finer Basmati varieties.',
      'Sindh starts earliest, because the heat arrives there first, and it '
          'usually runs two to three weeks ahead of Punjab. Khyber Pakhtunkhwa '
          'runs a little later again on the cooler northern weather.',
      'Harvest timing follows the variety: IRRI types come off around '
          'October, Basmati in November to December.',
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 0,
          soilMoistureMax: 0,
          tempMin: 20,
          tempMax: 32,
          humidityMin: 60,
          humidityMax: 90),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 0,
          soilMoistureMax: 0,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 0,
          soilMoistureMax: 0,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 50,
          humidityMax: 80),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK at transplanting plus a nitrogen split at panicle '
              'initiation. Include zinc where the soil is alkaline.',
      StageBand.reproductive:
          'Final nitrogen split at panicle initiation only. Extra nitrogen at '
              'booting causes lodging.',
      StageBand.maturity:
          'No nitrogen. Drain the field in the last week before harvest.',
    },
    irrigation: {
      StageBand.vegetative:
          'Keep shallow standing water. Alternate wetting and drying saves '
              'water and pushes roots deeper, but stop it before panicle '
              'initiation.',
      StageBand.reproductive:
          'Continuous shallow flooding from panicle initiation onward. This is '
              'the most water-sensitive phase of the crop.',
      StageBand.maturity: 'Reduce water gradually, then drain before harvest.',
    },
  ),

  // ─── Maize (two seasons) ───────────────────────────────────────────────
  'maize': CropProfile(
    name: 'maize',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.high,
    provinces: const [_pun, _sin, _kp],
    // Defaults used when no season has been chosen yet.
    typicalDuration: 125,
    stages: [
      _d('Germination', 1, 10, StageBand.vegetative, 'Emergence and stand'),
      _d('Seedling', 11, 30, StageBand.vegetative,
          'Main side-dressed nitrogen goes on here'),
      _d('Tillering', 31, 55, StageBand.vegetative, 'Rapid canopy growth'),
      _d('Booting', 56, 75, StageBand.reproductive, 'Tassel pushing'),
      _d('Tasseling', 76, 88, StageBand.reproductive, 'Pollen shed begins'),
      _d('Silking', 89, 100, StageBand.reproductive,
          'Silk emerges; stress here costs kernels'),
      _d('Grain filling', 101, 118, StageBand.maturity, 'Kernel weight'),
      _d('Maturity', 119, 125, StageBand.maturity, 'Milk line; check moisture'),
    ],
    variants: [
      SeasonVariant(
        name: 'Spring',
        typicalDuration: 125,
        regionNote: 'Sown January to February, harvested June to July.',
        stages: [
          _d('Germination', 1, 10, StageBand.vegetative, 'Emergence and stand'),
          _d('Seedling', 11, 30, StageBand.vegetative,
              'Main side-dressed nitrogen goes on here'),
          _d('Tillering', 31, 55, StageBand.vegetative, 'Rapid canopy growth'),
          _d('Booting', 56, 75, StageBand.reproductive, 'Tassel pushing'),
          _d('Tasseling', 76, 88, StageBand.reproductive, 'Pollen shed begins'),
          _d('Silking', 89, 100, StageBand.reproductive,
              'Silk emerges; stress here costs kernels'),
          _d('Grain filling', 101, 118, StageBand.maturity, 'Kernel weight'),
          _d('Maturity', 119, 125, StageBand.maturity,
              'Milk line; check moisture'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 1,
              startDay: 21,
              endMonth: 2,
              endDay: 28),
          SowingWindow(
              province: _sin,
              startMonth: 1,
              startDay: 1,
              endMonth: 2,
              endDay: 10),
        ],
      ),
      SeasonVariant(
        name: 'Autumn',
        typicalDuration: 115,
        regionNote:
            'Sown late July to August, harvested October to November. In the '
            'Peshawar valley, sowing after mid-July costs yield.',
        stages: [
          _d('Germination', 1, 10, StageBand.vegetative, 'Emergence and stand'),
          _d('Seedling', 11, 28, StageBand.vegetative,
              'Main side-dressed nitrogen goes on here'),
          _d('Tillering', 29, 50, StageBand.vegetative, 'Rapid canopy growth'),
          _d('Booting', 51, 68, StageBand.reproductive, 'Tassel pushing'),
          _d('Tasseling', 69, 80, StageBand.reproductive, 'Pollen shed begins'),
          _d('Silking', 81, 92, StageBand.reproductive,
              'Silk emerges; stress here costs kernels'),
          _d('Grain filling', 93, 108, StageBand.maturity, 'Kernel weight'),
          _d('Maturity', 109, 115, StageBand.maturity,
              'Milk line; check moisture'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 7,
              startDay: 21,
              endMonth: 8,
              endDay: 20),
          SowingWindow(
              province: _kp,
              startMonth: 7,
              startDay: 21,
              endMonth: 8,
              endDay: 15),
          SowingWindow(
              province: _sin,
              startMonth: 8,
              startDay: 1,
              endMonth: 8,
              endDay: 30),
        ],
      ),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 18,
          tempMax: 32,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 55,
          soilMoistureMax: 75,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Full basal NPK at sowing, then the main urea side-dress at the '
              'six-leaf stage. Maize is a heavy feeder in both seasons.',
      StageBand.reproductive:
          'No more nitrogen. A potassium shortfall shows around tasselling as '
              'marginal leaf scorch.',
      StageBand.maturity: 'Stop nitrogen; nothing else is needed.',
    },
    irrigation: {
      StageBand.vegetative:
          'Critical at sowing and again at the six-leaf stage. Ridge the rows '
              'on flat land.',
      StageBand.reproductive:
          'Tasselling and silking are the critical stages; a few days of '
              'stress is visible in the final yield.',
      StageBand.maturity: 'Cut irrigation once the grain layer is set.',
    },
  ),

  // ─── Sorghum ───────────────────────────────────────────────────────────
  'sorghum': CropProfile(
    name: 'sorghum',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    // Union of the season province lists.
    provinces: const [_pun, _sin, _kp],
    typicalDuration: 105,
    note: 'Pick the season before reading the stages. The grain crop runs to '
        'maturity, so the normal harvest prompt applies to it. Fodder sorghum '
        'is cut early and regrows, and later cuttings follow from the '
        'regrowth. The grain sowing window comes from a single research '
        'trial, so treat it as a starting point rather than a settled local '
        'figure.',
    variants: [
      SeasonVariant(
        name: 'Grain',
        typicalDuration: 105,
        regionNote: 'The kharif grain crop, sown around May and June. The '
            'window comes from a single research trial.',
        provinces: const [_pun],
        multiCut: false,
        stages: [
          _d('Establishment', 1, 10, StageBand.vegetative, 'Stand check'),
          _d('Vegetative growth', 11, 40, StageBand.vegetative, 'Canopy build'),
          _d('Grand growth', 41, 70, StageBand.reproductive,
              'Stalk and head development'),
          _d('Heading and flowering', 71, 85, StageBand.reproductive,
              'Bloom and pollination'),
          _d('Grain filling', 86, 100, StageBand.maturity, 'Kernel weight'),
          _d('Maturity', 101, 105, StageBand.maturity, 'Crop dry and ready'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 5,
              startDay: 1,
              endMonth: 6,
              endDay: 30),
        ],
      ),
      SeasonVariant(
        name: 'Fodder',
        typicalDuration: 60,
        regionNote: 'A multi-cut crop. The first cut comes at about fifty '
            'percent heading, around sixty days after sowing, and later '
            'cuttings follow from the regrowth.',
        provinces: const [_pun, _sin, _kp],
        // Cut early, then regrown: the table ends at the first cut.
        multiCut: true,
        stages: [
          _d('Establishment', 1, 10, StageBand.vegetative, 'Stand check'),
          _d('Vegetative growth', 11, 40, StageBand.vegetative,
              'Canopy build'),
          _d('Heading and first cut', 41, 60, StageBand.maturity,
              'Cut at about fifty percent heading; regrowth follows'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 2,
              startDay: 15,
              endMonth: 3,
              endDay: 15),
        ],
      ),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 34,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 22,
          tempMax: 38,
          humidityMin: 30,
          humidityMax: 60),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 20,
          tempMax: 36,
          humidityMin: 25,
          humidityMax: 55),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK at sowing. Sorghum is efficient with nitrogen and '
              'responds well to a split dose.',
      StageBand.reproductive:
          'Keep nitrogen light; potassium matters more than nitrogen from '
              'heading onwards.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'On irrigated land, three to four irrigations across the season, '
              'starting at establishment. Rainfed sorghum relies on the '
              'monsoon and is not irrigated at all.',
      StageBand.reproductive:
          'Irrigate at grand growth and at heading. Sorghum tolerates short '
              'dry spells better than maize, but heading stress still costs '
              'grain.',
      StageBand.maturity:
          'Stop irrigation to let the grain dry down. For the fodder season, '
              'irrigate again after each cut to get the regrowth going.',
    },
  ),
  'sugarcane': CropProfile(
    name: 'sugarcane',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.medium,
    calendarMode: true,
    // The longest season, so the date picker always allows enough room even
    // before a season has been chosen.
    typicalDuration: 540,
    // Union of the season province lists; each variant narrows this.
    provinces: const [_pun, _sin, _kp],
    stages: [
      _d('Germination', 1, 45, StageBand.vegetative,
          'Bud and root establishment'),
      _d('Tillering', 46, 120, StageBand.vegetative, 'Shoot production'),
      _d('Grand growth', 121, 270, StageBand.reproductive,
          'Stalk elongation; peak nitrogen demand'),
      _d('Ripening', 271, 540, StageBand.maturity,
          'Sucrose accumulation; stop nitrogen'),
    ],
    variants: [
      SeasonVariant(
        name: 'Spring',
        typicalDuration: 450,
        regionNote: 'Planted February to March.',
        provinces: const [_pun, _sin, _kp],
        stages: [
          _d('Germination', 1, 45, StageBand.vegetative,
              'Bud and root establishment'),
          _d('Tillering', 46, 120, StageBand.vegetative, 'Shoot production'),
          _d('Grand growth', 121, 270, StageBand.reproductive,
              'Stalk elongation; peak nitrogen demand'),
          _d('Ripening', 271, 450, StageBand.maturity,
              'Sucrose accumulation; stop nitrogen'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 2,
              startDay: 10,
              endMonth: 3,
              endDay: 31),
          SowingWindow(
              province: _sin,
              startMonth: 2,
              startDay: 10,
              endMonth: 3,
              endDay: 31),
          SowingWindow(
              province: _kp,
              startMonth: 2,
              startDay: 10,
              endMonth: 3,
              endDay: 31),
        ],
      ),
      SeasonVariant(
        name: 'Autumn',
        typicalDuration: 540,
        regionNote:
            'Planted September to October. Growth slows through the winter, so '
            'this season runs longer than spring.',
        provinces: const [_pun, _sin],
        stages: [
          _d('Germination', 1, 45, StageBand.vegetative,
              'Bud and root establishment'),
          _d('Tillering', 46, 120, StageBand.vegetative, 'Shoot production'),
          _d('Grand growth', 121, 270, StageBand.reproductive,
              'Stalk elongation; peak nitrogen demand'),
          _d('Ripening', 271, 540, StageBand.maturity,
              'Sucrose accumulation; stop nitrogen'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 9,
              startDay: 1,
              endMonth: 10,
              endDay: 15),
          SowingWindow(
              province: _sin,
              startMonth: 9,
              startDay: 1,
              endMonth: 10,
              endDay: 15),
        ],
      ),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 50,
          humidityMax: 80),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 55,
          soilMoistureMax: 75,
          tempMin: 22,
          tempMax: 38,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 40,
          humidityMax: 70),
    },
    fertilizer: {
      StageBand.vegetative:
          'Heavy basal NPK plus split urea through tillering.',
      StageBand.reproductive:
          'Split nitrogen through grand growth. This is the highest '
              'nitrogen-demand stage of the whole crop list.',
      StageBand.maturity:
          'Stop nitrogen completely. Late nitrogen keeps the crop green and '
              'dilutes the sucrose.',
    },
    irrigation: {
      StageBand.vegetative:
          'The first hundred and twenty days are the most critical part of the '
              'season. Sugarcane needs many irrigations right across the cycle, '
              'but establishment decides how many you can afford later.',
      StageBand.reproductive:
          'Grand growth is the thirstiest stage. Drainage matters as much as '
              'supply, especially where the monsoon is reliable.',
      StageBand.maturity:
          'Withhold irrigation with the rains to raise the sucrose content '
              'before harvest.',
    },
  ),
  'cotton': CropProfile(
    name: 'cotton',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.medium,
    calendarMode: true,
    provinces: const [_pun, _sin],
    typicalDuration: 165,
    note: 'Boll opening is picked in several rounds, roughly fifteen to '
        'twenty days apart, once about forty to fifty percent of the bolls on '
        'a plant have opened. Do not wait for the whole crop to finish.',
    stages: [
      _d('Emergence', 1, 10, StageBand.vegetative, 'Stand check; thin early'),
      _d('Seedling', 11, 35, StageBand.vegetative,
          'Root and canopy build; first irrigation lands here'),
      _d('Squaring', 36, 55, StageBand.vegetative,
          'First flower buds forming'),
      _d('Flowering', 56, 100, StageBand.reproductive,
          'Bloom and boll setting; peak water and nitrogen need'),
      _d('Boll development', 101, 140, StageBand.reproductive, 'Bolls filling'),
      _d('Boll opening and picking', 141, 165, StageBand.maturity,
          'Bolls crack; pick in several rounds'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          startMonth: 4,
          startDay: 1,
          endMonth: 5,
          endDay: 31),
      SowingWindow(
          province: _sin,
          startMonth: 3,
          startDay: 25,
          endMonth: 4,
          endDay: 30),
    ],
    lateSowingWarning:
        'Sown after the end of the recommended window. Cotton sown late loses '
            'yield.',
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 40,
          humidityMax: 65),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 22,
          tempMax: 38,
          humidityMin: 35,
          humidityMax: 60),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 22,
          tempMax: 38,
          humidityMin: 30,
          humidityMax: 55),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK, then split nitrogen across squaring and flowering. '
              'Cotton is the heaviest nitrogen feeder in this list.',
      StageBand.reproductive:
          'Spread the remaining nitrogen across flowering and boll '
              'development. Excess late nitrogen delays opening.',
      StageBand.maturity:
          'Stop nitrogen and withhold irrigation to encourage boll opening.',
    },
    irrigation: {
      StageBand.vegetative:
          'The first irrigation is about thirty to thirty-five days after '
              'sowing, then roughly every twelve to fifteen days. The period '
              'from about forty to one hundred and twenty days is the critical '
              'water window: drought through flowering and boll development '
              'causes square and boll shed.',
      StageBand.reproductive:
          'Critical water period. Keep the moisture steady through flowering '
              'and boll development - cotton is shallow-rooted and reacts '
              'badly to a dry-then-wet swing.',
      StageBand.maturity:
          'Reduce sharply and stop once most bolls have opened. Stopping water '
              'here helps the bolls crack evenly for picking.',
    },
  ),
  'jute': CropProfile(
    name: 'jute',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [],
    typicalDuration: 105,
    note: 'Jute is no longer a mainstream crop anywhere in Pakistan. This '
        'timeline is kept for reference only. No Pakistani stage source was found; this is general guidance and timing varies widely by variety.',
    stages: [
      _d('Germination', 1, 10, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 11, 45, StageBand.vegetative,
          'Rapid stem and leaf growth; fibre quality forming'),
      _d('Flowering', 46, 70, StageBand.reproductive, 'Bloom'),
      _d('Pod development', 71, 95, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 96, 105, StageBand.maturity,
          'Retting follows harvest; fibre quality peaks before over-ripeness'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 55,
          soilMoistureMax: 75,
          tempMin: 20,
          tempMax: 33,
          humidityMin: 60,
          humidityMax: 90),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 22,
          tempMax: 34,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 22,
          tempMax: 34,
          humidityMin: 50,
          humidityMax: 80),
    },
    fertilizer: {
      StageBand.vegetative:
          'Full basal NPK at sowing. Jute is a heavy feeder on a short '
              'duration, and fibre quality responds to potassium.',
      StageBand.reproductive:
          'No further nitrogen. Potassium during pod filling affects fibre '
              'strength.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Needs near-continuous moisture; jute grows through the monsoon.',
      StageBand.reproductive:
          'Keep moisture even through flowering and pod fill.',
      StageBand.maturity:
          'Reduce irrigation near harvest so the fibre retting is clean.',
    },
  ),
  'tobacco': CropProfile(
    name: 'tobacco',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_kp],
    typicalDuration: 175,
    dateAnchor: DateAnchor.transplanting,
    dateFieldLabel: 'Transplanting date',
    dateHint: 'The time in the field is counted from transplanting. The '
        'nursery is sown from October, and the seedlings go out from December '
        'to January.',
    note: 'A licensed crop. It is grown under company supervision, not by '
        'the open market, and it needs a buyer before a single plant is sown. '
        'Leaves are harvested in several rounds from April to June, and the '
        'harvest continues in several rounds until about June. Curing then '
        'takes a few days in barns.',
    stages: [
      _d('Establishment', 1, 20, StageBand.vegetative,
          'Transplant recovery and root set'),
      _d('Vegetative growth', 21, 70, StageBand.vegetative, 'Main canopy build'),
      _d('Topping and flowering', 71, 100, StageBand.reproductive,
          'Top removed to force uniform flowering'),
      _d('Leaf ripening and harvest', 101, 175, StageBand.maturity,
          'Pick in rounds, then cure in the barn'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _kp,
          startMonth: 12,
          startDay: 1,
          endMonth: 1,
          endDay: 31),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 20,
          tempMax: 33,
          humidityMin: 50,
          humidityMax: 80),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 20,
          tempMax: 33,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 20,
          tempMax: 33,
          humidityMin: 40,
          humidityMax: 70),
    },
    fertilizer: {
      StageBand.vegetative:
          'Split nitrogen across several doses with irrigation. Excess '
              'nitrogen gives dark, harsh leaf that cures badly.',
      StageBand.reproductive:
          'Stop nitrogen at topping. Potassium and a balanced micronutrient '
              'set matter more for leaf quality.',
      StageBand.maturity:
          'No further fertilizer. Withhold water to help the leaves yellow '
              'evenly.',
    },
    irrigation: {
      StageBand.vegetative:
          'Light frequent irrigation; tobacco wilts visibly before it '
              'recovers, so do not let it get that far.',
      StageBand.reproductive:
          'Keep moisture even at topping, then reduce as the leaves mature.',
      StageBand.maturity:
          'Withhold irrigation before the rounds of picking so the leaf cures '
              'well in the field.',
    },
  ),
  'sunflower': CropProfile(
    name: 'sunflower',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    // The scale is low / medium / high, so a mid-confidence value is not
    // available here. Low is the honest choice.
    confidence: Confidence.low,
    // Union of the season province lists.
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 110,
    note: 'Two crops a year. The autumn crop is sown later and therefore runs '
        'shorter, and it generally yields less than the spring crop. In south '
        'Punjab, finish sowing by the end of January.',
    variants: [
      SeasonVariant(
        name: 'Spring',
        typicalDuration: 110,
        regionNote: 'The higher-yielding season.',
        provinces: const [_pun, _sin, _kp, _bal],
        stages: [
          _d('Germination', 1, 8, StageBand.vegetative, 'Stand check'),
          _d('Vegetative', 9, 30, StageBand.vegetative, 'Canopy and root build'),
          _d('Bud initiation', 31, 45, StageBand.reproductive,
              'Bud formed; water need starts rising'),
          _d('Flowering', 46, 60, StageBand.reproductive,
              'Pollination; bees matter'),
          _d('Seed filling', 61, 100, StageBand.maturity, 'Kernel weight and oil'),
          _d('Maturity', 101, 110, StageBand.maturity,
              'Bracts dry; check moisture before harvest'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              region: 'central',
              startMonth: 1,
              startDay: 1,
              endMonth: 1,
              endDay: 31),
          SowingWindow(
              province: _pun,
              region: 'north',
              startMonth: 1,
              startDay: 1,
              endMonth: 2,
              endDay: 15),
          SowingWindow(
              province: _pun,
              region: 'south',
              startMonth: 1,
              startDay: 1,
              endMonth: 1,
              endDay: 31),
          SowingWindow(
              province: _sin,
              region: 'lower',
              startMonth: 11,
              startDay: 25,
              endMonth: 1,
              endDay: 31),
          SowingWindow(
              province: _sin,
              region: 'upper',
              startMonth: 12,
              startDay: 1,
              endMonth: 2,
              endDay: 28),
          SowingWindow(
              province: _bal,
              startMonth: 1,
              startDay: 1,
              endMonth: 2,
              endDay: 28),
          SowingWindow(
              province: _kp,
              startMonth: 2,
              startDay: 1,
              endMonth: 2,
              endDay: 28),
        ],
      ),
      SeasonVariant(
        name: 'Autumn',
        // A later sowing gives less time, so the tail is trimmed.
        typicalDuration: 100,
        regionNote: 'Later sowing shortens the crop, and it generally yields '
            'less than the spring crop.',
        provinces: const [_pun, _sin, _kp, _bal],
        stages: [
          _d('Germination', 1, 8, StageBand.vegetative, 'Stand check'),
          _d('Vegetative', 9, 30, StageBand.vegetative, 'Canopy and root build'),
          _d('Bud initiation', 31, 45, StageBand.reproductive,
              'Bud formed; water need starts rising'),
          _d('Flowering', 46, 60, StageBand.reproductive,
              'Pollination; bees matter'),
          _d('Seed filling', 61, 90, StageBand.maturity, 'Kernel weight and oil'),
          _d('Maturity', 91, 100, StageBand.maturity,
              'Bracts dry; check moisture before harvest'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 7,
              startDay: 1,
              endMonth: 9,
              endDay: 15),
          SowingWindow(
              province: _sin,
              startMonth: 7,
              startDay: 1,
              endMonth: 9,
              endDay: 15),
          SowingWindow(
              province: _bal,
              startMonth: 7,
              startDay: 1,
              endMonth: 8,
              endDay: 31),
          SowingWindow(
              province: _kp,
              startMonth: 7,
              startDay: 1,
              endMonth: 8,
              endDay: 31),
        ],
      ),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 18,
          tempMax: 32,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 20,
          tempMax: 36,
          humidityMin: 30,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK at sowing. Sunflower responds to a full basal dose more '
              'than to later splits.',
      StageBand.reproductive:
          'No further nitrogen. Boron and sulphur both affect seed set and '
              'oil content.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Establishment irrigation, then one around bud initiation. Sunflower '
              'tolerates short dry spells early.',
      StageBand.reproductive:
          'Critical at flowering. Drought now cuts both head size and kernel '
              'fill.',
      StageBand.maturity:
          'Stop irrigation once the head is filled to avoid late leaf disease.',
    },
  ),
  'lentil': CropProfile(
    name: 'lentil',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    // The scale is low / medium / high, so a mid-confidence value is not
    // available here. Low is the honest choice until the timeline is sourced.
    confidence: Confidence.low,
    provinces: const [_pun, _sin, _kp],
    typicalDuration: 140,
    note: 'Sown from October to November and harvested from March to April. '
        'It is mostly rainfed in the north; growers in the plains usually add '
        'one or two supplemental irrigations.',
    stages: [
      _d('Emergence', 1, 12, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 13, 60, StageBand.vegetative,
          'Branch and leaflet growth'),
      _d('Flowering', 61, 100, StageBand.reproductive, 'Full bloom'),
      _d('Pod filling', 101, 125, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 126, 140, StageBand.maturity, 'Pods dry, leaves shed'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 8,
          tempMax: 22,
          humidityMin: 45,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 10,
          tempMax: 25,
          humidityMin: 40,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 12,
          tempMax: 28,
          humidityMin: 35,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus at sowing with a rhizobium seed treatment. '
              'Lentil fixes its own nitrogen; do not over-apply it.',
      StageBand.reproductive:
          'Nothing required. A foliar micronutrient helps when pod set is '
              'poor.',
      StageBand.maturity: 'No fertilizer.',
    },
    irrigation: {
      StageBand.vegetative:
          'Mostly grown on residual moisture in the north and rarely '
          'irrigated there. In the plains, one or two supplemental '
          'irrigations are typical.',
      StageBand.reproductive:
          'If the profile is drying out, irrigate at flowering. Excess water '
              'here causes rank growth and disease instead of pods.',
      StageBand.maturity:
          'Stop irrigation so the crop dries for harvest.',
    },
  ),
  'chickpea': CropProfile(
    name: 'chickpea',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.medium,
    provinces: const [_pun, _sin, _kp],
    typicalDuration: 130,
    note: 'Rainfed in most of its area. Irrigated chickpea is a different '
        'management problem: the timing of the first irrigation moves the '
        'whole schedule, and kabuli types need it later than the desi types.',
    stages: [
      _d('Emergence', 1, 10, StageBand.vegetative, 'Stand check'),
      _d('Branching', 11, 45, StageBand.vegetative,
          'Branch build; the main nitrogen demand'),
      _d('Flowering', 46, 75, StageBand.reproductive, 'Full bloom'),
      _d('Pod filling', 76, 110, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 111, 130, StageBand.maturity, 'Leaves senesce, pods dry'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          region: 'rainfed',
          startMonth: 10,
          startDay: 20,
          endMonth: 11,
          endDay: 10),
      SowingWindow(
          province: _pun,
          region: 'irrigated',
          startMonth: 11,
          startDay: 1,
          endMonth: 11,
          endDay: 15),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 8,
          tempMax: 24,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 10,
          tempMax: 26,
          humidityMin: 35,
          humidityMax: 60),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 12,
          tempMax: 28,
          humidityMin: 30,
          humidityMax: 55),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus with rhizobium inoculation. Chickpea fixes its '
              'own nitrogen and hates over-fertilising.',
      StageBand.reproductive:
          'No nitrogen. Water at flowering causes rank growth and disease '
              'rather than yield.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Rainfed chickpea needs none. Where it is irrigated, give two '
              'irrigations: one at branching and one at pod filling.',
      StageBand.reproductive:
          'The pod-filling irrigation is the one that pays. Avoid a heavy '
              'irrigation at flowering, which pushes growth into leaves.',
      StageBand.maturity:
          'Stop irrigation so the crop dries for harvest. Kabuli types are '
              'sown later and are given their first irrigation much later, '
              'around fifty to sixty days after sowing.',
    },
  ),
  'mungbean': CropProfile(
    name: 'mungbean',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 70,
    note: 'Short-duration varieties finish in about sixty to seventy days. '
        'Older varieties take considerably longer, around ninety to a hundred '
        'and ten days, so the stages below fit the short types. It is sown '
        'both in spring and in kharif.',
    stages: [
      _d('Emergence', 1, 7, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 8, 30, StageBand.vegetative,
          'Branch and trifoliate growth'),
      _d('Flowering', 31, 45, StageBand.reproductive,
          'Full bloom; scout pod borer'),
      _d('Pod filling', 46, 60, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 61, 70, StageBand.maturity, 'Pods and leaves dry'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 20,
          tempMax: 33,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus and rhizobium inoculation. It is a short crop, so '
              'most nitrogen must come from fixation.',
      StageBand.reproductive:
          'No nitrogen. Scout for pod borer from flowering onward.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Two to three irrigations, at establishment, at flowering and at pod '
              'fill. A short crop is unforgiving of dry spells.',
      StageBand.reproductive:
          'Irrigate at flowering if the profile is drying out.',
      StageBand.maturity:
          'Stop irrigation to dry the crop evenly. Pod fill is the most '
              'critical of the three irrigations.',
    },
  ),
  'blackgram': CropProfile(
    name: 'blackgram',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _kp],
    typicalDuration: 90,
    note: 'Sown from July to August and harvested from October to November. '
        'In barani areas the crop depends entirely on the rain.',
    stages: [
      _d('Emergence', 1, 7, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 8, 35, StageBand.vegetative, 'Branch and leaf growth'),
      _d('Flowering', 36, 55, StageBand.reproductive,
          'Full bloom; pod borer risk'),
      _d('Pod filling', 56, 80, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 81, 90, StageBand.maturity, 'Pods and leaves dry'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 22,
          tempMax: 34,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 24,
          tempMax: 36,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus with rhizobium. Blackgram fixes its own nitrogen '
              'and responds poorly to nitrogen top-dressing.',
      StageBand.reproductive:
          'No nitrogen. Sulphur at sowing improves pod filling.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Two to three irrigations in irrigated zones. In barani areas there '
              'is no irrigation and the crop runs on the rain.',
      StageBand.reproductive:
          'Irrigate at flowering if the season turns dry. Waterlogging at this '
              'stage causes rank growth and disease.',
      StageBand.maturity: 'Stop irrigation to dry the crop for harvest.',
    },
  ),
  'mothbeans': CropProfile(
    name: 'mothbeans',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_sin],
    typicalDuration: 60,
    note: 'A desert pulse from Rajasthan. Only grown on the margins in Sindh; '
        'not a mainstream Pakistani crop. No Pakistani stage source was found; this is general guidance and timing varies widely by variety.',
    stages: [
      _d('Germination', 1, 7, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 8, 22, StageBand.vegetative, 'Low spreading growth'),
      _d('Flowering', 23, 40, StageBand.reproductive, 'Small yellow flowers'),
      _d('Pod development', 41, 55, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 56, 60, StageBand.maturity,
          'Very short season; pods shatter if left'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 25,
          humidityMax: 55),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 25,
          soilMoistureMax: 45,
          tempMin: 25,
          tempMax: 38,
          humidityMin: 20,
          humidityMax: 50),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 15,
          soilMoistureMax: 35,
          tempMin: 25,
          tempMax: 38,
          humidityMin: 15,
          humidityMax: 45),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus only. Mothbean fixes its own nitrogen and is '
              'adapted to poor soil.',
      StageBand.reproductive: 'No nitrogen or phosphorus.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'One sowing irrigation; the crop is designed to run on very little '
              'water.',
      StageBand.reproductive:
          'Usually none. Extra water at flowering encourages vegetative growth '
              'and reduces pods.',
      StageBand.maturity: 'None. Harvest promptly, as the pods shatter.',
    },
  ),
  'pigeonpeas': CropProfile(
    name: 'pigeonpeas',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _sin, _kp],
    typicalDuration: 170,
    note: 'Duration ranges from about one hundred and ten to two hundred days '
        'or more depending on the variety. No Pakistani stage source was found; this is general guidance and timing varies widely by variety.',
    stages: [
      _d('Germination', 1, 12, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 13, 55, StageBand.vegetative, 'Branch and canopy build'),
      _d('Flowering', 56, 100, StageBand.reproductive, 'Very long flowering period'),
      _d('Pod development', 101, 150, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 151, 170, StageBand.maturity, 'Pods dry'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 18,
          tempMax: 33,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter phosphorus with rhizobium. A long season means it fixes '
              'most of its own nitrogen.',
      StageBand.reproductive:
          'No nitrogen; potassium matters more for pod fill here.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Establishment irrigation, then rely on the monsoon.',
      StageBand.reproductive:
          'One or two irrigations across the long flowering period in a dry '
              'autumn.',
      StageBand.maturity: 'Stop irrigation before maturity.',
    },
  ),
  'kidneybeans': CropProfile(
    name: 'kidneybeans',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _kp],
    typicalDuration: 80,
    note: 'This is the export kidney bean, not the rajma grown for the local '
        'market. No Pakistani stage source was found; this is general guidance and timing varies widely by variety.',
    stages: [
      _d('Germination', 1, 8, StageBand.vegetative, 'Stand check'),
      _d('Vegetative', 9, 28, StageBand.vegetative, 'Trifoliate and branch growth'),
      _d('Flowering', 29, 50, StageBand.reproductive, 'Full bloom'),
      _d('Pod development', 51, 72, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 73, 80, StageBand.maturity, 'Pods and leaves dry'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 18,
          tempMax: 30,
          humidityMin: 45,
          humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 32,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 20,
          tempMax: 32,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Starter NPK with rhizobium. This bean responds to nitrogen better '
              'than the desi pulses, but fixation still does most of the work.',
      StageBand.reproductive: 'No further nitrogen; potassium aids pod fill.',
      StageBand.maturity: 'Nothing required.',
    },
    irrigation: {
      StageBand.vegetative:
          'Sowing irrigation, then rely on the monsoon once established.',
      StageBand.reproductive:
          'One irrigation at flowering if the season turns dry. Waterlogging '
              'reduces nodulation and yield.',
      StageBand.maturity: 'Stop irrigation before harvest.',
    },
  ),

  // ─── Oilseeds ───────────────────────────────────────────────────────────
  'mustard': CropProfile(
    name: 'mustard',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.medium,
    calendarMode: true,
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 150,
    note: 'Sown at the end of the monsoon in the north and a little later in '
        'the south, which is why the recommended windows differ by province.',
    stages: [
      _d('Emergence', 1, 10, StageBand.vegetative, 'Stand and establishment'),
      _d('Rosette', 11, 60, StageBand.vegetative,
          'Leaf rosette; the first irrigation falls here'),
      _d('Flowering', 61, 95, StageBand.reproductive, 'Full bloom; scout aphids'),
      _d('Pod and seed fill', 96, 130, StageBand.maturity, 'Pods filling'),
      _d('Maturity', 131, 150, StageBand.maturity,
          'Pods yellow; harvest before they shatter'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _kp,
          startMonth: 9,
          startDay: 15,
          endMonth: 10,
          endDay: 15),
      SowingWindow(
          province: _pun,
          region: 'general',
          startMonth: 10,
          startDay: 1,
          endMonth: 11,
          endDay: 30),
      SowingWindow(
          province: _pun,
          region: 'south',
          startMonth: 10,
          startDay: 15,
          endMonth: 11,
          endDay: 15),
      SowingWindow(
          province: _sin,
          startMonth: 10,
          startDay: 15,
          endMonth: 11,
          endDay: 15),
      SowingWindow(
          province: _bal,
          startMonth: 10,
          startDay: 15,
          endMonth: 11,
          endDay: 15),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 8,
          tempMax: 22,
          humidityMin: 45,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 10,
          tempMax: 25,
          humidityMin: 40,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 12,
          tempMax: 28,
          humidityMin: 35,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK with a nitrogen split at the first irrigation. Mustard '
              'responds strongly to sulphur, so include it in the basal dose.',
      StageBand.reproductive: 'Stop nitrogen once the rosette stage ends.',
      StageBand.maturity: 'No nitrogen; sulphur only if the soil test is low.',
    },
    irrigation: {
      StageBand.vegetative:
          'Three to four irrigations across the season. The rosette stage, '
              'around thirty to forty days after sowing, takes the first of '
              'them.',
      StageBand.reproductive:
          'The flowering irrigation, around sixty to seventy days, is the most '
              'critical of the season; drought then cuts pod number directly.',
      StageBand.maturity:
          'Continue into pod fill, then stop well before maturity so the pods '
              'dry down for harvest.',
    },
  ),
  'onion': CropProfile(
    name: 'onion',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.medium,
    provinces: const [_pun, _sin, _kp, _bal],
    typicalDuration: 120,
    dateAnchor: DateAnchor.transplanting,
    dateFieldLabel: 'Transplanting date',
    dateHint: 'The time in the field is counted from transplanting, not from '
        'sowing. The nursery is sown about forty-five to sixty days before '
        'the seedlings go out.',
    note: 'Very early transplanting makes the crop run longer and makes early '
        'bolting more likely. The KP window is the safest for avoiding it.',
    stages: [
      _d('Recovery and leaf growth', 1, 30, StageBand.vegetative,
          'Transplant recovery, then leaf and root build'),
      _d('Bulb enlargement', 31, 90, StageBand.reproductive,
          'Bulb sizing; the heaviest demand on the crop'),
      _d('Ripening and neck fall', 91, 120, StageBand.maturity,
          'Neck flattens; harvest before the tops go over'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _kp,
          startMonth: 12,
          startDay: 15,
          endMonth: 1,
          endDay: 15),
      SowingWindow(
          province: _pun,
          startMonth: 12,
          startDay: 1,
          endMonth: 1,
          endDay: 31),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 15,
          tempMax: 30,
          humidityMin: 45,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 18,
          tempMax: 32,
          humidityMin: 40,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 18,
          tempMax: 32,
          humidityMin: 35,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Split nitrogen across several doses with irrigation. Onion is '
              'shallow-rooted and cannot take the whole dose at once.',
      StageBand.reproductive:
          'Final split as the bulb starts to form. Stop nitrogen once bulbs are '
              'sizing, or they stay soft and rot.',
      StageBand.maturity:
          'No nitrogen. Withhold water to firm the bulbs.',
    },
    irrigation: {
      StageBand.vegetative:
          'Six to eight irrigations across the season, light and frequent. '
              'Bulbs rot in waterlogged soil, so never let the field stand '
              'wet.',
      StageBand.reproductive:
          'The most water-sensitive period is rapid bulb growth, around sixty '
              'days after transplanting. A check here decides the bulb size.',
      StageBand.maturity:
          'Stop irrigating about three weeks before harvest so the skin sets '
              'and the storage life improves.',
    },
  ),
  'tomato': CropProfile(
    name: 'tomato',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _sin, _kp, _bal],
    // The longest season, so the date picker always allows enough room.
    typicalDuration: 130,
    dateAnchor: DateAnchor.transplanting,
    dateFieldLabel: 'Transplanting date',
    dateHint: 'The time in the field is counted from transplanting. The '
        'nursery is sown in July and August for the autumn crop, and about '
        'thirty to forty days before transplanting for the winter-spring crop.',
    note: 'Swat and the upper parts of KP grow a summer crop instead, '
        'harvested from July to September. That crop is not covered by the '
        'two seasons below.',
    variants: [
      SeasonVariant(
        name: 'Autumn',
        typicalDuration: 130,
        regionNote: 'Nursery sown in July and August, transplanted in August '
            'and September, harvested from November.',
        provinces: const [_pun, _sin, _kp, _bal],
        stages: [
          _d('Establishment', 1, 14, StageBand.vegetative,
              'Transplant recovery'),
          _d('Vegetative', 15, 35, StageBand.vegetative,
              'Canopy build; stake and train'),
          _d('Flowering and fruit set', 36, 60, StageBand.reproductive,
              'Trusses setting'),
          _d('Fruit development', 61, 75, StageBand.maturity, 'Fruit sizing'),
          _d('Harvest period', 76, 130, StageBand.maturity,
              'Picking rounds; potassium and calcium still matter'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 8,
              startDay: 1,
              endMonth: 9,
              endDay: 30),
          SowingWindow(
              province: _sin,
              startMonth: 8,
              startDay: 1,
              endMonth: 9,
              endDay: 30),
          SowingWindow(
              province: _kp,
              startMonth: 8,
              startDay: 1,
              endMonth: 9,
              endDay: 30),
          SowingWindow(
              province: _bal,
              startMonth: 8,
              startDay: 1,
              endMonth: 9,
              endDay: 30),
        ],
      ),
      SeasonVariant(
        name: 'Winter-spring',
        typicalDuration: 120,
        regionNote: 'Transplanted from November to February.',
        provinces: const [_pun, _sin],
        stages: [
          _d('Establishment', 1, 14, StageBand.vegetative,
              'Transplant recovery'),
          _d('Vegetative', 15, 35, StageBand.vegetative,
              'Canopy build; stake and train'),
          _d('Flowering and fruit set', 36, 60, StageBand.reproductive,
              'Trusses setting'),
          _d('Fruit development', 61, 75, StageBand.maturity, 'Fruit sizing'),
          _d('Harvest period', 76, 120, StageBand.maturity,
              'Picking rounds; potassium and calcium still matter'),
        ],
        windows: const [
          SowingWindow(
              province: _pun,
              startMonth: 11,
              startDay: 15,
              endMonth: 2,
              endDay: 10),
        ],
      ),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 15,
          tempMax: 30,
          humidityMin: 45,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 18,
          tempMax: 33,
          humidityMin: 40,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 18,
          tempMax: 33,
          humidityMin: 40,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK plus a light nitrogen split once established. Too much '
              'early nitrogen gives leaves instead of fruit.',
      StageBand.reproductive:
          'Switch to potassium. Calcium through the fruit-setting window '
              'prevents blossom-end rot.',
      StageBand.maturity:
          'Keep potassium and calcium going; stop nitrogen.',
    },
    irrigation: {
      StageBand.vegetative:
          'Water regularly and evenly. Drip is strongly preferred, and the '
              'schedule matters more than the volume.',
      StageBand.reproductive:
          'Keep the root zone uniformly moist through fruit set. Swings '
              'between dry and wet split the fruit and invite disease.',
      StageBand.maturity:
          'Let it dry slightly between pickings to lift flavour, but never '
              'let the plant wilt.',
    },
  ),
  'watermelon': CropProfile(
    name: 'watermelon',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _sin, _kp],
    typicalDuration: 95,
    note: 'Direct sown, so the sowing date is the real sowing date. It is '
        'grown twice a year in places: an early spring crop and a midsummer '
        'one.',
    stages: [
      _d('Establishment', 1, 12, StageBand.vegetative, 'Stand check'),
      _d('Vine growth', 13, 35, StageBand.vegetative, 'Runner growth'),
      _d('Flowering', 36, 53, StageBand.reproductive,
          'Male then female flowers'),
      _d('Fruit filling', 54, 78, StageBand.maturity,
          'Fruit sizing; heaviest water need'),
      _d('Ripening', 79, 95, StageBand.maturity,
          'Sugar builds; watch for cracking'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          startMonth: 2,
          startDay: 1,
          endMonth: 3,
          endDay: 31),
      SowingWindow(
          province: _pun,
          region: 'central',
          startMonth: 7,
          startDay: 1,
          endMonth: 7,
          endDay: 31),
      SowingWindow(
          province: _kp,
          startMonth: 7,
          startDay: 1,
          endMonth: 7,
          endDay: 31),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 34,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 30,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK. Watermelon is sensitive to fresh manure, which splits '
              'the fruit.',
      StageBand.reproductive:
          'Stop nitrogen at fruit set. Potassium and boron both affect fruit '
              'quality and sugar.',
      StageBand.maturity: 'No further fertilizer; withhold water to sweeten.',
    },
    irrigation: {
      StageBand.vegetative:
          'One heavy irrigation at the start to carry the crop through '
              'establishment, then regular light irrigation.',
      StageBand.reproductive:
          'Keep it regular through vine growth and fruit filling. Uneven '
              'water causes cracking and misshapen fruit.',
      StageBand.maturity:
          'Reduce at ripening to lift the sugar. Stopping too late or '
              'cutting too fast both cost quality.',
    },
  ),
  'muskmelon': CropProfile(
    name: 'muskmelon',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _sin],
    typicalDuration: 90,
    note: 'Direct sown. Some sources also sow it in April and May for a June '
        'to August harvest, which is later than the window below; check the '
        'local practice before using this calendar.',
    stages: [
      _d('Establishment', 1, 12, StageBand.vegetative, 'Stand check'),
      _d('Vine growth', 13, 35, StageBand.vegetative, 'Runner growth'),
      _d('Flowering', 36, 50, StageBand.reproductive,
          'Male then female flowers'),
      _d('Fruit development', 51, 75, StageBand.maturity, 'Fruit sizing'),
      _d('Ripening', 76, 90, StageBand.maturity,
          'Netted fruit; check for cracking and sweetness'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          startMonth: 2,
          startDay: 1,
          endMonth: 3,
          endDay: 31),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 20,
          tempMax: 34,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 30,
          humidityMax: 60),
    },
    fertilizer: {
      StageBand.vegetative:
          'Basal NPK with light splits. Avoid fresh manure, which causes vine '
              'burn and poor fruit set.',
      StageBand.reproductive:
          'Stop nitrogen at fruit set; potassium improves sweetness and '
              'disease resistance.',
      StageBand.maturity: 'No further fertilizer; reduce water before harvest.',
    },
    irrigation: {
      StageBand.vegetative:
          'Four to five irrigations across the season. Melons dislike dry-then-'
              'wet swings.',
      StageBand.reproductive:
          'Keep it even through flowering and fruit set; stress here shows up '
              'as small, poorly netted fruit.',
      StageBand.maturity:
          'Stop irrigating about two weeks before harvest so the flavour and '
              'the flesh keep their firmness.',
    },
  ),
  'apple': CropProfile(
    name: 'apple',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_kp, _bal],
    note: 'Apple is grown in the highlands of Balochistan, in Quetta, '
        'Pishin, Killa Saifullah, Mastung and Ziarat, and in the KP valleys of '
        'Swat, Dir and Chitral, because it needs real winter cold. Market supply '
        'runs July to October. A bloom date was not found in a Pakistani source, '
        'so treat the timing as approximate.',
    monthStages: [
      _m('Dormancy', 11, 2, StageBand.maturity,
          'Rest; pruning and orchard sanitation happen now'),
      _m('Bud break', 3, 3, StageBand.vegetative,
          'Silver tip through green tip; frost risk is highest'),
      _m('Flowering', 4, 4, StageBand.reproductive,
          'Full bloom; pollination decides the crop size'),
      _m('Fruit set', 5, 5, StageBand.reproductive,
          'Petal fall; expect the June drop'),
      _m('Fruit development', 6, 7, StageBand.reproductive,
          'Cell division ends and the fruit starts to size'),
      _m('Ripening and harvest', 8, 10, StageBand.maturity,
          'Starch turns to sugar; pick by variety'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 5,
          tempMax: 20,
          humidityMin: 40,
          humidityMax: 70),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 10,
          tempMax: 28,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 8,
          tempMax: 25,
          humidityMin: 35,
          humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'Apply organic matter and a balanced basal dressing as buds break. '
              'Split nitrogen through the season; excess causes soft growth.',
      StageBand.reproductive:
          'Potassium and boron through fruit set. Keep nitrogen low so shoots '
              'do not compete with the crop.',
      StageBand.maturity:
          'Stop nitrogen before harvest. Potassium through ripening improves '
              'storage life.',
    },
    irrigation: {
      StageBand.vegetative:
          'Critical during bloom and fruit set; drought then costs fruit '
              'number.',
      StageBand.reproductive: 'Keep the root zone moist through fruit sizing.',
      StageBand.maturity:
          'Reduce before harvest, but do not let the tree wilt.',
    },
  ),
  'mango': CropProfile(
    name: 'mango',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.medium,
    provinces: const [_sin, _pun, _kp],
    note: 'Sindh, Punjab and KP. Early Sindh varieties come in from mid-May, '
        'Punjab Langra and Dasehri in June, and Chaunsa and Ratol in July and '
        'August. Warm spells or storms in spring can damage the flowering, '
        'which is the one stage that decides the size of the crop.',
    monthStages: [
      _m('Winter rest', 11, 12, StageBand.maturity,
          'Bare limbs; the flower buds are already formed'),
      _m('Flowering', 1, 3, StageBand.reproductive,
          'Panicles emerge; wet weather at bloom causes flower drop'),
      _m('Fruit set', 4, 4, StageBand.reproductive, 'Peeling and fruit retention'),
      _m('Fruit development and early harvest', 5, 6, StageBand.maturity,
          'Kernel and pulp build; the earliest Sindh fruit comes in'),
      _m('Main harvest', 7, 8, StageBand.maturity,
          'Pick ripe; sap burn if handled wet'),
      _m('Post-harvest flush', 9, 10, StageBand.vegetative,
          'Shoot flush after harvest; this sets next year flower buds'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35, soilMoistureMax: 55, tempMin: 15, tempMax: 35, humidityMin: 40, humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40, soilMoistureMax: 60, tempMin: 20, tempMax: 38, humidityMin: 35, humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30, soilMoistureMax: 50, tempMin: 20, tempMax: 38, humidityMin: 30, humidityMax: 65),
    },
    fertilizer: {
      StageBand.vegetative:
          'After harvest is the main fertilizer window. Full organic matter plus '
              'a balanced dose as the new flush hardens.',
      StageBand.reproductive:
          'Potassium through fruit set. Avoid nitrogen at bloom; it pushes '
              'flowers and shoots at once and causes heavy drop.',
      StageBand.maturity: 'Potassium only; stop nitrogen before harvest.',
    },
    irrigation: {
      StageBand.vegetative: 'Withhold water before bloom to sharpen flowering, then irrigate.',
      StageBand.reproductive: 'Critical from fruit set; drought gives small fruit.',
      StageBand.maturity: 'Keep moisture steady right through ripening.',
    },
  ),
  'orange': CropProfile(
    name: 'orange',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _kp],
    note: 'Kinnow is a mandarin rather than a true sweet orange, and it makes '
        'up most of the citrus grown in Punjab. Harvest runs from December to '
        'February, with the best window from mid-January to mid-February once '
        'the fruit has coloured. Some varieties ripen earlier or later, so the '
        'timing depends on the variety.',
    monthStages: [
      _m('Harvest', 11, 1, StageBand.maturity,
          'Pick; the fruit does not ripen off the tree'),
      _m('Late harvest and flowering', 2, 3, StageBand.reproductive,
          'Bloom; citrus leafminer watch'),
      _m('Fruit set', 4, 4, StageBand.reproductive, 'Petal fall; fruit retention'),
      _m('Fruit growth', 5, 10, StageBand.maturity, 'Juice and colour build'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40, soilMoistureMax: 60, tempMin: 10, tempMax: 28, humidityMin: 45, humidityMax: 75),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40, soilMoistureMax: 60, tempMin: 15, tempMax: 35, humidityMin: 40, humidityMax: 70),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 35, soilMoistureMax: 55, tempMin: 12, tempMax: 32, humidityMin: 40, humidityMax: 70),
    },
    fertilizer: {
      StageBand.vegetative:
          'Split the annual dose across spring and summer. Nitrogen is best '
              'applied in small, frequent doses for citrus.',
      StageBand.reproductive:
          'Potassium through fruit sizing. A nutrition shortfall shows as '
              'small, coarse fruit.',
      StageBand.maturity: 'Reduce nitrogen; keep potassium for colour and keeping quality.',
    },
    irrigation: {
      StageBand.vegetative: 'Critical at bloom and fruit set.',
      StageBand.reproductive: 'Keep the root zone evenly moist through fruit development.',
      StageBand.maturity: 'Slight deficit before harvest raises soluble solids.',
    },
  ),
  'pomegranate': CropProfile(
    name: 'pomegranate',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_pun, _bal],
    note: 'The Balochistan belt is Pishin, Killa Saifullah, Loralai, Mastung, '
        'Quetta and Harnai. The Punjab varieties Pearl and Golden are planted '
        'from February to March, and suit southern and central Punjab.',
    monthStages: [
      _m('Dormancy and pruning', 12, 2, StageBand.maturity,
          'Rest; prune once the harvest is finished'),
      _m('Flowering', 3, 4, StageBand.reproductive,
          'Red flowers; pollination and fruit number are set here'),
      _m('Fruit set', 5, 5, StageBand.reproductive, 'Thin the clusters'),
      _m('Fruit development', 6, 8, StageBand.reproductive,
          'Skin colour and arils build; fruit cracking risk'),
      _m('Harvest', 9, 11, StageBand.maturity,
          'Cut, do not pull; fruit does not ripen off the tree'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _pun,
          startMonth: 2,
          startDay: 1,
          endMonth: 3,
          endDay: 31),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 10,
          tempMax: 28,
          humidityMin: 30,
          humidityMax: 60),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 35,
          soilMoistureMax: 55,
          tempMin: 15,
          tempMax: 35,
          humidityMin: 25,
          humidityMax: 55),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 12,
          tempMax: 32,
          humidityMin: 25,
          humidityMax: 50),
    },
    fertilizer: {
      StageBand.vegetative:
          'Organic matter with the winter pruning. The tree is a heavy feeder '
              'once it comes into bearing.',
      StageBand.reproductive:
          'Potassium dominates from fruit set onward, with boron to help the '
              'fruit set evenly.',
      StageBand.maturity:
          'Withhold nitrogen and keep potassium going through ripening.',
    },
    irrigation: {
      StageBand.vegetative:
          'Water is deliberately withheld here. That stress is what brings the '
              'tree into flower, so irrigating now undoes the plan.',
      StageBand.reproductive:
          'Resume gently once fruit set is done. Drying spells at fruit fill '
              'cause cracking.',
      StageBand.maturity:
          'Light and frequent through ripening; overwatering softens the '
              'rind and shortens storage life.',
    },
  ),
  'grapes': CropProfile(
    name: 'grapes',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [_bal, _kp, _pun],
    note: 'Balochistan supplies most of the crop, in Quetta, Mastung, Kalat, '
        'Pishin and Killa Abdullah. Fresh harvest runs July to October, and the '
        'Swat season is August to September, while time to maturity varies '
        'widely by cultivar. Bud break and bloom months were not found in a '
        'Pakistani source, so the calendar is approximate.',
    monthStages: [
      _m('Dormancy', 11, 2, StageBand.maturity,
          'Cane pruning; the vine is not working'),
      _m('Bud break', 3, 3, StageBand.vegetative,
          'Shoots appear; growth is slow at first'),
      _m('Shoot growth', 4, 4, StageBand.vegetative,
          'Rapid canopy build; the flower clusters emerge'),
      _m('Flowering', 5, 5, StageBand.reproductive,
          'Bloom; cool or hot weather now costs fruit set'),
      _m('Fruit set and berry growth', 6, 6, StageBand.reproductive,
          'Berries set and size; keep the canopy open'),
      _m('Ripening and early harvest', 7, 8, StageBand.maturity,
          'Veraison; sugar climbs as acid falls'),
      _m('Main and late harvest', 9, 10, StageBand.maturity,
          'Pick on sugar and acid, not on the date'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 8,
          tempMax: 26,
          humidityMin: 35,
          humidityMax: 65),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 40,
          soilMoistureMax: 60,
          tempMin: 15,
          tempMax: 32,
          humidityMin: 30,
          humidityMax: 60),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 30,
          soilMoistureMax: 50,
          tempMin: 15,
          tempMax: 34,
          humidityMin: 25,
          humidityMax: 55),
    },
    fertilizer: {
      StageBand.vegetative:
          'Apply as growth starts, because roots only resume feeding after '
              'bud break. Moderate nitrogen, split.',
      StageBand.reproductive:
          'Keep nitrogen down and potassium up from fruit set, or the vine '
              'puts its energy into shoots instead of fruit.',
      StageBand.maturity:
          'Stop nitrogen. Potassium through ripening improves sugar and '
              'colour.',
    },
    irrigation: {
      StageBand.vegetative:
          'Keep the root zone moist through shoot growth and bloom. Water '
              'stress now costs flower clusters.',
      StageBand.reproductive:
          'Even moisture at fruit set; swings here cause berry shrivel.',
      StageBand.maturity:
          'Withhold water from veraison to concentrate sugar, but only in a '
              'warm site. In a cooler valley, keep irrigating.',
    },
  ),
  'coffee': CropProfile(
    name: 'coffee',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [],
    note: 'Coffee is not grown commercially anywhere in Pakistan. This '
        'timeline is kept for reference only.',
    monthStages: [
      _m('Post-harvest recovery', 1, 2, StageBand.vegetative, 'Leaf flush after picking'),
      _m('Flowering', 3, 4, StageBand.reproductive, 'White blossom on laterals'),
      _m('Fruit development', 5, 8, StageBand.maturity, 'Bean filling'),
      _m('Harvest', 9, 12, StageBand.maturity, 'Picking rounds by maturity'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50, soilMoistureMax: 70, tempMin: 15, tempMax: 28, humidityMin: 55, humidityMax: 85),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50, soilMoistureMax: 70, tempMin: 18, tempMax: 30, humidityMin: 55, humidityMax: 85),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 45, soilMoistureMax: 65, tempMin: 18, tempMax: 30, humidityMin: 50, humidityMax: 80),
    },
    fertilizer: {
      StageBand.vegetative:
          'Split nitrogen and potassium through the year. Coffee is a heavy '
              'perennial feeder on a shallow root system.',
      StageBand.reproductive:
          'Potassium through bean filling; nitrogen affects leaf and next '
              'season\'s yield more than this one.',
      StageBand.maturity: 'No nitrogen during picking; keep potassium.',
    },
    irrigation: {
      StageBand.vegetative: 'Needs reliable moisture on a shallow root system; drought and heat together scorch leaves.',
      StageBand.reproductive: 'Even moisture through flowering and bean fill.',
      StageBand.maturity: 'Keep supplying through the picking rounds.',
    },
  ),
  'coconut': CropProfile(
    name: 'coconut',
    trackingMode: TrackingMode.monthBased,
    verified: false,
    confidence: Confidence.low,
    provinces: const [],
    note: 'Coconut is not grown in Pakistan. The two-stage split is a '
        'placeholder, not real phenology - coconut flowers and is harvested on '
        'a rolling cycle.',
    monthStages: [
      _m('Flowering and nut set', 1, 6, StageBand.reproductive,
          'Continuous inflorescences year-round'),
      _m('Nut development and harvest', 7, 12, StageBand.maturity,
          'Nuts mature and are cut on a rolling cycle'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50, soilMoistureMax: 75, tempMin: 22, tempMax: 34, humidityMin: 60, humidityMax: 90),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 55, soilMoistureMax: 80, tempMin: 24, tempMax: 36, humidityMin: 60, humidityMax: 90),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 45, soilMoistureMax: 70, tempMin: 22, tempMax: 35, humidityMin: 55, humidityMax: 85),
    },
    fertilizer: {
      StageBand.vegetative:
          'Split applications through the year around the palm. Potassium and '
              'chloride are commonly short; nitrogen drives frond production.',
      StageBand.reproductive:
          'Potassium through nut set and filling; deficiency causes few nuts '
              'and premature nut fall.',
      StageBand.maturity: 'Maintain potassium through the cutting cycle.',
    },
    irrigation: {
      StageBand.vegetative: 'Needs a regular supply; drought causes frond yellowing and nut drop.',
      StageBand.reproductive: 'Critical from nut set through filling.',
      StageBand.maturity: 'Keep supplying through the cutting rounds.',
    },
  ),

  // ─── Tropical fruit, days-after-planting ────────────────────────────────
  'banana': CropProfile(
    name: 'banana',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    multiCut: true,
    continuousNote: 'Harvest, then suckers continue\n'
        'One plant gives one bunch, and after that bunch is cut the pseudostem '
        'is cut down and the sucker beside it carries the next bunch, sooner '
        'than the first one did. A working plantation is therefore picking all '
        'year, with never more than a short gap between bunches.',
    provinces: const [_sin, _bal, _kp, _pun],
    typicalDuration: 400,
    dateAnchor: DateAnchor.planting,
    dateFieldLabel: 'Planting date',
    dateHint: 'Banana is propagated vegetatively from a sucker, so there is no '
        'sowing date. This is counted from the day the sucker goes into the '
        'ground, and the first bunch follows about a year later.',
    note: 'Sindh holds almost all of the crop, which is grown around Thatta, '
        'Badin, Hyderabad, Mirpurkhas and Nawabshah in lower Sindh. Sources '
        'disagree on the time to harvest, from about eleven to fourteen months '
        'after planting or longer, and two to three ratoon crops follow from the '
        'same clump before it is replanted.',
    stages: [
      _d('Sucker establishment', 1, 45, StageBand.vegetative,
          'Roots take hold; keep the soil wet and weed free'),
      _d('Vegetative growth', 46, 270, StageBand.vegetative,
          'Pseudostem builds and unfurls; this is the long stage'),
      _d('Flowering', 271, 300, StageBand.reproductive,
          'The inflorescence emerges and the hands start'),
      _d('Fruit development', 301, 375, StageBand.maturity,
          'Fingers fill out and curve upward'),
      _d('Harvest', 376, 400, StageBand.maturity,
          'Cut green at three quarters full, then cut the pseudostem down'),
    ],
    sowingWindows: const [
      SowingWindow(
          province: _sin,
          startMonth: 2,
          startDay: 1,
          endMonth: 3,
          endDay: 31),
      SowingWindow(
          province: _sin,
          startMonth: 8,
          startDay: 1,
          endMonth: 9,
          endDay: 30),
    ],
    windowNotes: const [
      'The spring planting gives higher yields.',
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 60,
          soilMoistureMax: 80,
          tempMin: 20,
          tempMax: 35,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 55,
          soilMoistureMax: 75,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 20,
          tempMax: 34,
          humidityMin: 50,
          humidityMax: 80),
    },
    fertilizer: {
      StageBand.vegetative:
          'Heavy feeder from the start. Split nitrogen through the vegetative '
              'months so it arrives with each irrigation.',
      StageBand.reproductive:
          'Potassium dominates once the bunch is filling. This is the single '
              'biggest lever on bunch weight.',
      StageBand.maturity: 'Nothing further; keep the potassium going until the '
          'bunch is cut.',
    },
    irrigation: {
      StageBand.vegetative:
          'Never let it dry. A banana wilts fast and does not recover well, '
              'and the roots are shallow.',
      StageBand.reproductive:
          'Keep moisture even through flowering and bunch fill; a dry spell '
              'now means small fingers and split fruit.',
      StageBand.maturity:
          'Keep watering until the bunch is off. Then ease off, because the '
              'next sucker is now carrying the crop.',
    },
  ),
  'papaya': CropProfile(
    name: 'papaya',
    trackingMode: TrackingMode.dasBased,
    verified: false,
    confidence: Confidence.low,
    multiCut: true,
    continuousNote: 'Fruiting continues\n'
        'Papaya is a short-lived tropical plant rather than a tree. It flowers '
        'once and then keeps fruiting for years without stopping, so this '
        'timeline covers the run up to the first harvest and the plant carries '
        'on producing afterwards.',
    provinces: const [_pun, _sin],
    typicalDuration: 300,
    dateAnchor: DateAnchor.transplanting,
    dateFieldLabel: 'Transplanting date',
    dateHint: 'This is counted from transplanting the seedling. A papaya '
        'flowers about five to six months after it goes in, and the first '
        'fruit follows about four to five months after that.',
    note: 'Commercial orchards sit near Karachi, around Malir, and at Thatta. '
        'One Pakistani source has the nursery sown in March and the seedlings '
        'transplanted in April, while others plant from February to March or '
        'from September to November, and the time to first fruit ranges from '
        'about eight months to eighteen months or more, so the timeline shown '
        'here is the fast end.',
    stages: [
      _d('Establishment', 1, 30, StageBand.vegetative,
          'Roots take hold; keep the soil moist and never waterlogged'),
      _d('Vegetative growth', 31, 150, StageBand.vegetative,
          'Trunk builds and the crown unfurls; it is very frost sensitive'),
      _d('Flowering', 151, 180, StageBand.reproductive,
          'Flowers open; this is when the sex becomes obvious'),
      _d('Fruit set and development', 181, 270, StageBand.maturity,
          'Thin to one fruit per node; size and sugar are set here'),
      _d('First harvest', 271, 300, StageBand.maturity,
          'Pick at light green with a yellow streak at the base'),
    ],
    monitoring: {
      StageBand.vegetative: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 22,
          tempMax: 35,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.reproductive: const MonitoringTarget(
          soilMoistureMin: 50,
          soilMoistureMax: 70,
          tempMin: 22,
          tempMax: 36,
          humidityMin: 55,
          humidityMax: 85),
      StageBand.maturity: const MonitoringTarget(
          soilMoistureMin: 45,
          soilMoistureMax: 65,
          tempMin: 20,
          tempMax: 34,
          humidityMin: 50,
          humidityMax: 80),
    },
    fertilizer: {
      StageBand.vegetative:
          'Generous organic matter at transplanting, then light split doses. '
              'Too much nitrogen gives a tall plant and a light crop.',
      StageBand.reproductive:
          'Potassium and boron through fruit set; boron is the one that most '
              'often runs short.',
      StageBand.maturity:
          'Keep feeding after the first harvest, because the plant carries on '
              'fruiting.',
    },
    irrigation: {
      StageBand.vegetative:
          'Steady and even. Papaya cannot stand waterlogging, so drainage '
              'matters more than the amount.',
      StageBand.reproductive:
          'Keep moisture even through flowering and fruit fill; swings cause '
              'splitting and poor filling.',
      StageBand.maturity:
          'Ease off slightly after the first harvest, and never let the root '
              'zone dry completely.',
    },
  ),

};

/// The profile for [crop], or null when the crop is unknown.
CropProfile? profileFor(String crop) {
  final key = crop.trim().toLowerCase();
  return cropProfiles[key];
}

/// How many crops have a stage calendar. All 30 model classes are covered.
int get trackableCropCount => cropProfiles.length;
