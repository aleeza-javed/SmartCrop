import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/crop_stage.dart';
import '../models/sensor_data.dart';
import '../services/crop_tracking_service.dart';
import '../theme/app_colors.dart';

/// Crop Growth Stage Tracker.
///
/// Shows, for the active crop and its saved sowing date, the current growth
/// stage, the next one, what to monitor, and fertilizer and irrigation advice.
///
/// The stage calendar lives in `models/crop_stage.dart`; the sowing date lives
/// in `CropTrackingService` (SharedPreferences). Live sensor values, when
/// available, are shown next to the target ranges so a reading can be compared
/// on the spot.
class GrowthStageScreen extends StatefulWidget {
  final String crop;
  final SensorData? sensorData;

  const GrowthStageScreen({
    super.key,
    this.crop = 'wheat',
    this.sensorData,
  });

  @override
  State<GrowthStageScreen> createState() => _GrowthStageScreenState();
}

class _GrowthStageScreenState extends State<GrowthStageScreen> {
  static final _tracking = CropTrackingService.instance;

  DateTime? _sowingDate;
  Province? _province;
  String? _variant;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _tracking.getSowingDate(widget.crop),
      _tracking.getProvince(),
      _tracking.getSeasonVariant(widget.crop),
    ]);
    if (!mounted) return;
    setState(() {
      _sowingDate = results[0] as DateTime?;
      _province = results[1] as Province?;
      _variant = results[2] as String?;
      _loading = false;
    });
  }

  /// Days since sowing, 1 on the day after sowing. Clamped at 0 so a date set
  /// in the future (a typo, or planning ahead) does not produce a negative
  /// stage lookup.
  int? get _daysSince {
    final sown = _sowingDate;
    if (sown == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(sown).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final profile = profileFor(widget.crop);
    final day = _daysSince;
    // Month-based perennials need no date; they resolve from the clock.
    final isPerennial = profile?.isMonthBased ?? false;
    final now = DateTime.now();
    // A future anchor date is a planned sowing, not an error.
    final cycleStatus = profile == null || day == null
        ? null
        : profile.cycleStatus(day, variantName: _variant);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(topPad: MediaQuery.of(context).padding.top, crop: widget.crop),
          Expanded(
            child: _loading && !isPerennial
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isPerennial)
                          _PerennialSummaryCard(
                            profile: profile!,
                            month: now.month,
                          )
                        else
                          _CropAndDateCard(
                            crop: widget.crop,
                            profile: profile,
                            sowingDate: _sowingDate,
                            daysSince: day,
                            variant: _variant,
                            onEditDate: _pickSowingDate,
                            onClearSowingDate: _clearSowingDate,
                          ),
                        if (profile != null) ...[
                          const SizedBox(height: 14),
                          _ProvinceCard(
                            provinces: profile.provincesFor(_variant),
                            selected: _province,
                            onChanged: _pickProvince,
                          ),
                        ],
                        if (profile != null && profile.hasVariants) ...[
                          const SizedBox(height: 14),
                          _SeasonCard(
                            profile: profile,
                            selected: _variant,
                            suggested:
                                _sowingDate == null ? null : _suggestedVariant(),
                            onChanged: _pickVariant,
                          ),
                        ],
                        if (profile != null &&
                            _sowingDate != null &&
                            _province != null &&
                            _isOutsideWindow(profile)) ...[
                          const SizedBox(height: 14),
                          _WindowWarningCard(
                            province: _province!,
                            profile: profile,
                            variant: _variant,
                          ),
                        ],
                        if (profile != null &&
                            profile.lateSowingWarning != null &&
                            _isAfterWindow(profile)) ...[
                          const SizedBox(height: 14),
                          _LateSowingCard(
                            message: profile.lateSowingWarning!,
                          ),
                        ],
                        if (profile != null && !profile.verified) ...[
                          const SizedBox(height: 14),
                          const _DraftGuidanceCard(),
                        ],
                        if (profile != null && profile.note != null) ...[
                          const SizedBox(height: 14),
                          _RegionNoteCard(note: profile.note!),
                        ],
                        for (final note in profile?.windowNotes ?? const <String>[])
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _RegionNoteCard(note: note),
                          ),
                        const SizedBox(height: 20),
                        if (profile == null)
                          _UntrackableCropNotice(crop: widget.crop)
                        else if (isPerennial)
                          _MonthStageBody(
                            profile: profile,
                            month: now.month,
                            sensorData: widget.sensorData,
                          )
                        else if (_sowingDate == null)
                          _NoSowingDateNotice(anchor: profile.dateAnchor)
                        else if (cycleStatus == CycleStatus.upcoming)
                          _UpcomingBody(
                            profile: profile,
                            anchorDate: _sowingDate!,
                            daysUntil: -day!,
                            variant: _variant,
                          )
                        else
                          _StageBody(
                            profile: profile,
                            day: day ?? 0,
                            variant: _variant,
                            anchorDate: _sowingDate,
                            sensorData: widget.sensorData,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Suggest a season from the anchor date's month, used only as a hint before
  /// the user picks explicitly.
  String? _suggestedVariant() {
    final profile = profileFor(widget.crop);
    final date = _sowingDate;
    if (profile == null || date == null) return null;
    return profile.suggestedVariantForDate(date)?.name;
  }

  /// The late-sowing warning fires only for a date past the END of the
  /// window. A date before the window opens is early, not late.
  bool _isAfterWindow(CropProfile profile) {
    final date = _sowingDate;
    final province = _province;
    if (date == null || province == null) return false;
    return profile.isAfterWindow(date, province, variantName: _variant);
  }

  bool _isOutsideWindow(CropProfile profile) {
    final date = _sowingDate;
    final province = _province;
    if (date == null || province == null) return false;
    return profile.isOutsideWindow(date, province, variantName: _variant);
  }

  Future<void> _pickProvince(Province province) async {
    await _tracking.setProvince(province);
    if (!mounted) return;
    setState(() => _province = province);
  }

  Future<void> _pickVariant(String? variant) async {
    await _tracking.setSeasonVariant(widget.crop, variant);
    if (!mounted) return;
    setState(() => _variant = variant);
  }

  Future<void> _pickSowingDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final profile = profileFor(widget.crop);
    // Use the longest season, not the selected one, so switching to a longer
    // season (sugarcane autumn at 540 days) never needs a wider range than the
    // picker already allows.
    final range = sowingPickerRange(
      today: today,
      cycleDays: profile?.maxDurationAcrossVariants ?? 120,
    );

    // The saved date is clamped into the range. `showDatePicker` asserts when
    // initialDate sits outside [firstDate, lastDate], so an unclamped saved
    // date - a planned sowing, a date from a previous install, or a device
    // clock that moved - would make the picker unusable.
    final initial = range.clamp(_sowingDate ?? today);

    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: range.first,
        lastDate: range.last,
        helpText: 'Select ${profile?.anchorNoun ?? 'sowing'} date',
      );
      if (picked == null || !mounted) return;

      try {
        await _tracking.setSowingDate(widget.crop, picked);
        await _load();
      } catch (e) {
        _toast('Could not save that date. Please try again.');
        debugPrint('GrowthStageScreen: save failed: $e');
      }
    } catch (e) {
      // Never fail silently - say what went wrong instead of doing nothing.
      _toast('Could not open the date picker. Please try again.');
      debugPrint('GrowthStageScreen: showDatePicker failed: $e');
    }
  }

  Future<void> _clearSowingDate() async {
    try {
      await _tracking.clearSowingDate(widget.crop);
      await _load();
    } catch (e) {
      _toast('Could not clear that date. Please try again.');
      debugPrint('GrowthStageScreen: clear failed: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLANNED SOWING
// ═══════════════════════════════════════════════════════════════════════════

/// Shown when the anchor date is in the future. The date is kept, not
/// rejected, and every milestone is reported as upcoming.
class _UpcomingBody extends StatelessWidget {
  final CropProfile profile;
  final DateTime anchorDate;
  final int daysUntil;
  final String? variant;

  const _UpcomingBody({
    required this.profile,
    required this.anchorDate,
    required this.daysUntil,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final milestones = profile.milestonesFrom(
      anchorDate: anchorDate,
      daysSince: -daysUntil,
      variantName: variant,
    );
    final total = profile.durationForVariant(variant);
    final anchorLabel = profile.isTransplanted ? 'transplanting' : 'sowing';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          accent: const Color(0xFF0D47A1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available_rounded,
                      size: 16, color: Color(0xFF0D47A1)),
                  const SizedBox(width: 6),
                  Text(
                    'PLANNED',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sowing planned in $daysUntil '
                'day${daysUntil == 1 ? '' : 's'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$anchorLabel on ${_formatDate(anchorDate)}. The expected '
                '$anchorLabel-to-harvest cycle is about $total days, so the '
                'first stage is expected on '
                '${_formatDate(milestones.first.date)}.',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Expected milestones',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'All dates are calculated from the planned $anchorLabel date and will '
          'be marked upcoming until the day arrives.',
          style: GoogleFonts.manrope(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final m in milestones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MilestoneRow(milestone: m),
          ),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final Milestone milestone;

  const _MilestoneRow({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final upcoming = !milestone.reached;
    final colour =
        upcoming ? const Color(0xFF0D47A1) : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.stage,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'around ${_formatDate(milestone.date)}',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              upcoming ? 'Upcoming' : 'Reached',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MONTH-BASED BODY (perennials)
// ═══════════════════════════════════════════════════════════════════════════

/// Summary card for a standing perennial. No sowing date, no day count.
class _PerennialSummaryCard extends StatelessWidget {
  final CropProfile profile;
  final int month;

  const _PerennialSummaryCard({required this.profile, required this.month});

  @override
  Widget build(BuildContext context) {
    final stage = profile.monthStageFor(month);

    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00695C).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.park_rounded,
                color: Color(0xFF00695C), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracked by month',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _titleCase(profile.name),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
              ],
            ),
          ),
          if (stage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                stage.name,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthStageBody extends StatelessWidget {
  final CropProfile profile;
  final int month;
  final SensorData? sensorData;

  const _MonthStageBody({
    required this.profile,
    required this.month,
    required this.sensorData,
  });

  @override
  Widget build(BuildContext context) {
    final stage = profile.monthStageFor(month);
    if (stage == null) {
      return const _NoSowingDateNotice();
    }
    final next = profile.nextMonthStageAfter(month);
    final target = profile.monitoring[stage.band];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          accent: _bandColor(stage.band),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THIS MONTH: ${stage.name.toUpperCase()}',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stage.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stage.focus,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(label: monthName(month)),
                  _Tag(label: '${stage.startMonth}-${stage.endMonth}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (next != null) ...[
          _Card(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.skip_next_rounded,
                      color: AppColors.onSurfaceVariant, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${next.name} ${nextMonthStagePhrase(next, currentMonth: month)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onBackground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        next.focus,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (target != null) ...[
          _MonitoringCard(
            target: target,
            sensorData: sensorData,
            band: stage.band,
            profile: profile,
          ),
          const SizedBox(height: 14),
          _AdviceCard(
            icon: Icons.science_rounded,
            iconColor: const Color(0xFF6A1B9A),
            title: 'Fertilizer advice',
            body: profile.fertilizer[stage.band] ?? '',
          ),
          const SizedBox(height: 10),
          _AdviceCard(
            icon: Icons.water_drop_rounded,
            iconColor: const Color(0xFF0D47A1),
            title: 'Irrigation advice',
            body: profile.irrigation[stage.band] ?? '',
          ),
        ],
        const SizedBox(height: 14),
        _MonthTrack(profile: profile, month: month),
        const SizedBox(height: 18),
        const _PrototypeNote(),
      ],
    );
  }
}

/// Calendar strip of every month stage with the current one highlighted.
class _MonthTrack extends StatelessWidget {
  final CropProfile? profile;
  final int month;

  const _MonthTrack({required this.profile, required this.month});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const SizedBox.shrink();
    final current = p.monthStageFor(month);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YEAR ROUND',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in p.monthStages)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: s == current
                        ? AppColors.primary
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: s == current
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Text(
                    s.name,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: s == current ? Colors.white : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE BODY
// ═══════════════════════════════════════════════════════════════════════════

class _StageBody extends StatelessWidget {
  final CropProfile profile;
  final int day;
  final String? variant;
  final DateTime? anchorDate;
  final SensorData? sensorData;

  const _StageBody({
    required this.profile,
    required this.day,
    required this.variant,
    required this.anchorDate,
    required this.sensorData,
  });

  @override
  Widget build(BuildContext context) {
    final stage = profile.stageForDay(day, variantName: variant);
    if (stage == null) {
      return _PastHarvestNotice(
        crop: profile.name,
        day: day,
        typical: profile.durationForVariant(variant),
        anchorNoun: profile.anchorNoun,
        multiCut: profile.isMultiCut(variantName: variant),
        multiCutNote: profile.pastFirstNote,
        multiCutTitle: profile.multiCutTitle,
      );
    }

    final next = profile.nextStageAfter(day, variantName: variant);
    final dayInStage = day - stage.startDay + 1;
    final target = profile.monitoring[stage.band];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressCard(
          profile: profile,
          day: day,
          stage: stage,
          dayInStage: dayInStage,
          variant: variant,
        ),
        const SizedBox(height: 14),
        _CurrentStageCard(
          stage: stage,
          dayInStage: dayInStage,
          day: day,
        ),
        const SizedBox(height: 14),
        if (next != null) ...[
          _NextStageCard(stage: next, daysSince: day, anchorDate: anchorDate),
          const SizedBox(height: 14),
        ],
        if (target != null) ...[
          _MonitoringCard(
            target: target,
            sensorData: sensorData,
            band: stage.band,
            profile: profile,
          ),
          const SizedBox(height: 14),
          _AdviceCard(
            icon: Icons.science_rounded,
            iconColor: const Color(0xFF6A1B9A),
            title: 'Fertilizer advice',
            body: profile.fertilizer[stage.band] ?? '',
          ),
          const SizedBox(height: 10),
          _AdviceCard(
            icon: Icons.water_drop_rounded,
            iconColor: const Color(0xFF0D47A1),
            title: 'Irrigation advice',
            body: profile.irrigation[stage.band] ?? '',
          ),
        ],
        const SizedBox(height: 18),
        const _PrototypeNote(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROP + DATE CARD
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// PROVINCE, SEASON, WINDOW
// ═══════════════════════════════════════════════════════════════════════════

/// Province picker. The seed is app-wide rather than per crop.
class _ProvinceCard extends StatelessWidget {
  final List<Province> provinces;
  final Province? selected;
  final ValueChanged<Province> onChanged;

  const _ProvinceCard({
    required this.provinces,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final all = Province.values;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'PROVINCE',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            provinces.isEmpty
                ? 'Not commonly grown in any of the four provinces. Guidance '
                    'below is general.'
                : 'Recommended sowing windows follow the selected province.',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in all)
                GestureDetector(
                  onTap: () => onChanged(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected == p
                          ? AppColors.primary
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected == p
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (provinces.contains(p)) ...[
                          Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: selected == p
                                ? Colors.white
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          p.label,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected == p
                                ? Colors.white
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Season selector for two-season crops such as maize.
class _SeasonCard extends StatelessWidget {
  final CropProfile profile;
  final String? selected;
  final String? suggested;
  final ValueChanged<String?> onChanged;

  const _SeasonCard({
    required this.profile,
    required this.selected,
    required this.suggested,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = profile.variantByName(selected) ??
        (suggested == null ? null : profile.variantByName(suggested));
    final usingSuggestion = selected == null && active != null;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'SEASON',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final v in profile.variants)
                GestureDetector(
                  onTap: () => onChanged(v.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active?.name == v.name
                          ? AppColors.primary
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active?.name == v.name
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                      ),
                    ),
                    child: Text(
                      v.name,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active?.name == v.name
                            ? Colors.white
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (usingSuggestion) ...[
            const SizedBox(height: 10),
            Text(
              'Guessed from the date you entered. Tap a season to set it '
              'explicitly.',
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (active?.regionNote != null) ...[
            const SizedBox(height: 10),
            Text(
              active!.regionNote!,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Non-blocking warning when the anchor date falls outside the recommended
/// window for the selected province.
class _WindowWarningCard extends StatelessWidget {
  final Province province;
  final CropProfile profile;
  final String? variant;

  const _WindowWarningCard({
    required this.province,
    required this.profile,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final w = profile.effectiveWindow(province, variantName: variant);
    if (w == null) return const SizedBox.shrink();
    final label = profile.windowLabel(province, variantName: variant);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: Color(0xFFE65100)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Outside the recommended window for ${province.label} '
              '($label). Stage timing may differ.',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown only when the anchor date is past the END of the recommended window.
class _LateSowingCard extends StatelessWidget {
  final String message;

  const _LateSowingCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.running_with_errors_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropAndDateCard extends StatelessWidget {
  final String crop;
  final CropProfile? profile;
  final DateTime? sowingDate;
  final int? daysSince;
  final String? variant;
  final VoidCallback onEditDate;
  final VoidCallback onClearSowingDate;

  const _CropAndDateCard({
    required this.crop,
    required this.profile,
    required this.sowingDate,
    required this.daysSince,
    required this.variant,
    required this.onEditDate,
    required this.onClearSowingDate,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate = sowingDate != null;
    final p = profile;
    final stage = hasDate && p != null
        ? p.stageForDay(daysSince!, variantName: variant)
        : null;
    final dateLabel = p?.dateFieldLabel ?? 'Sowing date';

    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00695C).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.grass_rounded,
                    color: Color(0xFF00695C), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tracking',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _titleCase(crop),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBackground,
                      ),
                    ),
                  ],
                ),
              ),
              _StagePill(
                stage: stage,
                hasDate: hasDate,
                isPlanned: hasDate && (daysSince ?? 1) < 1,
                noDateLabel: p?.noDateLabel ?? 'Set sowing date',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDate ? _formatDate(sowingDate!) : 'Not set',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: hasDate
                            ? AppColors.onBackground
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onEditDate,
                icon: const Icon(Icons.event_rounded, size: 16),
                label: Text(hasDate ? 'Change' : 'Set date'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasDate)
                IconButton(
                  onPressed: onClearSowingDate,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.onSurfaceVariant),
                  tooltip: 'Clear $dateLabel',
                ),
            ],
          ),
          if (p?.dateHint != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    p!.dateHint!,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  final CropStage? stage;
  final bool hasDate;
  final bool isPlanned;

  /// Already anchor-aware, e.g. "Set transplanting date".
  final String noDateLabel;

  const _StagePill({
    required this.stage,
    required this.hasDate,
    required this.noDateLabel,
    this.isPlanned = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isPlanned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Planned',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0D47A1),
          ),
        ),
      );
    }
    if (!hasDate || stage == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Text(
          noDateLabel,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stage!.name,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROGRESS
// ═══════════════════════════════════════════════════════════════════════════

class _ProgressCard extends StatelessWidget {
  final CropProfile profile;
  final int day;
  final CropStage stage;
  final int dayInStage;
  final String? variant;

  const _ProgressCard({
    required this.profile,
    required this.day,
    required this.stage,
    required this.dayInStage,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final total = profile.durationForVariant(variant);
    final fraction = (day / total).clamp(0.0, 1.0);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day $day of ~$total',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              Text(
                '${(fraction * 100).round()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          _StageTrack(
            stages: profile.stagesForVariant(variant),
            currentStage: stage,
          ),
        ],
      ),
    );
  }
}

/// A horizontal strip of every stage with the current one highlighted, so the
/// farmer can see where they sit in the season at a glance.
class _StageTrack extends StatelessWidget {
  final List<CropStage> stages;
  final CropStage currentStage;

  const _StageTrack({required this.stages, required this.currentStage});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in stages)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: s.name == currentStage.name
                      ? AppColors.primary
                      : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: s.name == currentStage.name
                        ? AppColors.primary
                        : AppColors.outlineVariant,
                  ),
                ),
                child: Text(
                  s.name,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: s.name == currentStage.name
                        ? Colors.white
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CURRENT / NEXT STAGE
// ═══════════════════════════════════════════════════════════════════════════

class _CurrentStageCard extends StatelessWidget {
  final CropStage stage;
  final int dayInStage;
  final int day;

  const _CurrentStageCard({
    required this.stage,
    required this.dayInStage,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      accent: _bandColor(stage.band),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_bandIcon(stage.band), size: 16, color: _bandColor(stage.band)),
              const SizedBox(width: 6),
              Text(
                'CURRENT STAGE',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stage.name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stage.focus,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Tag(label: 'Day $dayInStage of ${stage.lengthDays}'),
              _Tag(label: '${stage.startDay}-${stage.endDay} DAS'),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextStageCard extends StatelessWidget {
  final CropStage stage;
  final int daysSince;
  final DateTime? anchorDate;

  const _NextStageCard({
    required this.stage,
    required this.daysSince,
    required this.anchorDate,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.skip_next_rounded,
                color: AppColors.onSurfaceVariant, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT STAGE',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stage.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nextStagePhrase(stage,
                      daysSince: daysSince, anchorDate: anchorDate),
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MONITORING
// ═══════════════════════════════════════════════════════════════════════════

class _MonitoringCard extends StatelessWidget {
  final MonitoringTarget target;
  final SensorData? sensorData;
  final StageBand band;
  final CropProfile profile;

  const _MonitoringCard({
    required this.target,
    required this.sensorData,
    required this.band,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final s = sensorData;
    // Flooded crops (rice) have no meaningful soil-moisture target, so that
    // row is replaced with the standing-water guidance instead of a number.
    final rows = <(String, String, double?)>[
      if (!profile.floodedField)
        ('Soil moisture', target.soilMoisture, s?.soilMoisturePercent),
      ('Soil temperature', '$target.tempMin-${target.tempMax} °C', s?.soilTemp),
      ('Air humidity', target.humidity, s?.airHumidity),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'WHAT TO MONITOR',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _MonitorRow(
              label: row.$1,
              target: row.$2,
              reading: (row.$3 == null || row.$3 == 0) ? null : row.$3,
            ),
            const SizedBox(height: 8),
          ],
          if (profile.floodedField && profile.moistureNote != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.water_rounded,
                    size: 14, color: Color(0xFF0D47A1)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    profile.moistureNote!,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (s == null)
            Text(
              'No live sensor reading - showing target ranges only.',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class _MonitorRow extends StatelessWidget {
  final String label;
  final String target;
  final double? reading;

  const _MonitorRow({
    required this.label,
    required this.target,
    required this.reading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          target,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppColors.onBackground,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (reading != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'now ${reading!.toStringAsFixed(0)}',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ADVICE
// ═══════════════════════════════════════════════════════════════════════════

class _AdviceCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _AdviceCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NOTICES
// ═══════════════════════════════════════════════════════════════════════════

class _DraftGuidanceCard extends StatelessWidget {
  const _DraftGuidanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF856404).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF856404),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Draft guidance',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These stage boundaries have not been checked by an '
              'agronomist. Treat them as a starting point.',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionNoteCard extends StatelessWidget {
  final String note;

  const _RegionNoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public_rounded,
              size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSowingDateNotice extends StatelessWidget {
  final DateAnchor anchor;

  const _NoSowingDateNotice({this.anchor = DateAnchor.sowing});

  @override
  Widget build(BuildContext context) {
    final label =
        anchor == DateAnchor.transplanting ? 'transplanting' : 'sowing';
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF00695C).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.event_rounded,
              color: Color(0xFF00695C), size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          'Set a $label date',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Growth stage tracking works from the day you $label. Set the date '
          'to see the current stage, the next one, and what to watch for.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _UntrackableCropNotice extends StatelessWidget {
  final String crop;

  const _UntrackableCropNotice({required this.crop});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.help_outline_rounded,
              color: AppColors.onSurfaceVariant, size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          'No stage calendar for ${_titleCase(crop)}',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stage tracking covers the main Khyber Pakhtunkhwa and irrigated '
          'Punjab crops. Crop suitability and nutrient alerts still work for '
          'this crop.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _PastHarvestNotice extends StatelessWidget {
  final String crop;
  final int day;
  final int typical;
  final String anchorNoun;
  final bool multiCut;
  final String multiCutNote;
  final String multiCutTitle;

  const _PastHarvestNotice({
    required this.crop,
    required this.day,
    required this.typical,
    required this.anchorNoun,
    required this.multiCut,
    required this.multiCutNote,
    required this.multiCutTitle,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            multiCut
                ? multiCutTitle
                : 'Expected harvest window has ended',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            multiCut
                ? multiCutNote
                : 'Day $day is past the expected $typical-day cycle for '
                    '${_titleCase(crop)}. Check the field and harvest, or set a '
                    'new $anchorNoun date to start the next season.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrototypeNote extends StatelessWidget {
  const _PrototypeNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Stage boundaries and advice are indicative for local varieties '
            'and sowing dates. Confirm against a field advisory before '
            'applying fertilizer.',
            style: GoogleFonts.manrope(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED BITS
// ═══════════════════════════════════════════════════════════════════════════

/// White card with the app's standard radius and shadow.
class _Card extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const _Card({required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: accent == null
            ? null
            : Border.all(color: accent!.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

Color _bandColor(StageBand band) => switch (band) {
      StageBand.vegetative => AppColors.primary,
      StageBand.reproductive => const Color(0xFF856404),
      StageBand.maturity => const Color(0xFF1565C0),
    };

IconData _bandIcon(StageBand band) => switch (band) {
      StageBand.vegetative => Icons.eco_rounded,
      StageBand.reproductive => Icons.local_florist_rounded,
      StageBand.maturity => Icons.inventory_2_rounded,
    };

/// Matches the capitalisation the rest of the app uses for crop names.
String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Full month name for 1-12, guarded against an out-of-range value.
String monthName(int month) =>
    (month >= 1 && month <= 12) ? _monthNames[month - 1] : 'Unknown month';

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

// ─── Header (skeleton unchanged) ─────────────────────────────────────────

class _Header extends StatelessWidget {
  final double topPad;
  final String crop;

  const _Header({required this.topPad, required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, topPad + 8, 16, 12),
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
                  'Growth Stage Tracker',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  _titleCase(crop),
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
