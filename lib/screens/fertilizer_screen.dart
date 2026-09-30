import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sensor_data.dart';
import '../models/sensor_reading.dart';
import '../services/crop_api_service.dart';
import '../services/sensor_service.dart';
import '../theme/app_colors.dart';

/// Signature of the fertilizer fetch, so tests can inject a fake instead of
/// reaching the network.
typedef FertilizerFetch = Future<FertilizerReport> Function({
  required String crop,
  required Map<String, double> npk,
  Map<String, double>? current,
  List<Map<String, dynamic>>? history,
  DateTime? readingAt,
});

/// Wording for a nutrient that reads inside its configured band.
const String _withinRangeLabel = 'Within configured range';

/// Wording for a nutrient the sensor is not reporting.
const String _noReadingLabel = 'Sensor not reporting';

/// Shown under the readings. The estimate is a rule of thumb, not a dose.
const String _footnote =
    'Estimated amounts use 1 ppm is about 2 kg/ha. Ranges are prototype values '
    'compared directly with sensor ppm. Confirm with a soil test.';

class FertilizerScreen extends StatefulWidget {
  final SensorData? sensorData;
  final String crop;

  /// Injected for tests. When null the real [SensorService] stream is used.
  final Stream<SensorData>? stream;

  /// Injected for tests. When null the real history archive is read.
  final Future<List<SensorReading>> Function(String crop)? historyLoader;

  /// Injected for tests. When null the real API call is used.
  final FertilizerFetch? fetch;

  const FertilizerScreen({
    super.key,
    this.sensorData,
    this.crop = 'wheat',
    this.stream,
    this.historyLoader,
    this.fetch,
  });

  @override
  State<FertilizerScreen> createState() => _FertilizerScreenState();
}

class _FertilizerScreenState extends State<FertilizerScreen> {
  /// Coalesces a burst of stream events into a single fetch.
  static const Duration _debounce = Duration(seconds: 2);

  /// How often the freshness of the displayed reading is re-evaluated, so a
  /// device that stops publishing still shows as stale rather than live.
  static const Duration _freshnessTick = Duration(seconds: 30);

  /// Used only when the backend does not report its own threshold.
  static const int _defaultStaleAfterSeconds = 600;

  StreamSubscription<SensorData>? _subscription;
  Timer? _debounceTimer;
  Timer? _freshnessTimer;

  FertilizerReport? _report;
  bool _loading = false;
  String? _error;

  /// The most recent reading the app observed.
  SensorData? _latest;

  /// The reading time sent to the backend for its staleness check.
  ///
  /// IMPORTANT: this is the app-side *arrival* time of the stream event, not a
  /// measurement time. The live Firebase node is written with
  /// `SensorData.toJson()`, which carries no timestamp, and `sensorDataStream()`
  /// discards everything that is not a SensorData - so no device-stamped
  /// measurement time exists anywhere in the app today.
  ///
  /// Consequence: the Live/Stale pill reflects app-side stream activity only. It
  /// can tell you the app is still receiving updates; it cannot tell you when the
  /// probe actually sampled the soil, and a device that froze mid-publish while
  /// Firebase kept replaying the last value would still look Live. Once the
  /// ESP32 publishes its own measurement timestamp, thread that through here
  /// instead of `DateTime.now()` and the pill becomes meaningful.
  DateTime? _readingAt;
  bool _locallyStale = true;

  @override
  void initState() {
    super.initState();

    _latest = widget.sensorData;
    if (_latest != null) _readingAt = DateTime.now();

    final initial = widget.sensorData;
    if (initial != null) {
      // Show something immediately; the stream refines it shortly.
      unawaited(_load(reading: initial, at: _readingAt));
    } else {
      setState(() => _locallyStale = true);
    }

    _subscribe();
    _freshnessTimer = Timer.periodic(_freshnessTick, (_) => _recheckFreshness());
  }

  void _subscribe() {
    final stream = widget.stream;
    if (stream == null) {
      // Only touch Firebase when nothing was injected.
      try {
        _subscription = SensorService().sensorDataStream().listen(
              _onReading,
              onError: (_) {},
            );
      } catch (_) {
        // No Firebase available (tests, or not yet initialised): stay static.
      }
      return;
    }
    _subscription = stream.listen(_onReading, onError: (_) {});
  }

  void _onReading(SensorData data) {
    if (!mounted) return;
    setState(() {
      _latest = data;
      _readingAt = DateTime.now();
      _locallyStale = false;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      unawaited(_load(reading: data, at: _readingAt));
    });
  }

  /// Marks the displayed reading stale once it ages past the backend's own
  /// threshold, without needing a new reading to arrive.
  void _recheckFreshness() {
    if (!mounted) return;
    final at = _readingAt;
    if (at == null || _report == null) return;
    final limit = Duration(
      seconds: _report?.staleAfterSeconds ?? _defaultStaleAfterSeconds,
    );
    final stale = DateTime.now().difference(at) > limit;
    if (stale != _locallyStale) setState(() => _locallyStale = stale);
  }

  Future<void> _load({required SensorData reading, DateTime? at}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // The live node carries no device timestamp, so the arrival time of the
    // stream event is the best available reading time. The backend uses it
    // only to decide whether to flag the reading stale.
    final history = await _loadHistory();
    if (!mounted) return;

    final fetch = widget.fetch ??
        ({
          required crop,
          required npk,
          current,
          history,
          readingAt,
        }) =>
            CropApiService.getFertilizerReport(
              crop: crop,
              npk: npk,
              current: current,
              history: history,
              readingAt: readingAt,
            );

    try {
      final report = await fetch(
        crop: widget.crop,
        npk: {'N': reading.n, 'P': reading.p, 'K': reading.k},
        current: reading.toMonitorValues(),
        history: history,
        readingAt: at,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _locallyStale = report.stale;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Real archived readings when the service can supply them. Returns null when
  /// there is nothing to send - never fabricated, so the backend honestly
  /// answers `persistence: "unavailable"`.
  Future<List<Map<String, dynamic>>?> _loadHistory() async {
    final loader = widget.historyLoader;
    final readings = await (loader != null
        ? loader(widget.crop)
        : _safeHistory(widget.crop));
    if (readings.isEmpty) return null;
    return readings.map((r) => r.toMonitorPayload()).toList();
  }

  Future<List<SensorReading>> _safeHistory(String crop) async {
    try {
      return await SensorService().fetchHistory(crop);
    } catch (_) {
      return const [];
    }
  }

  static String _friendlyError(Object e) {
    if (e is CropApiException) return e.message;
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('TimeoutException')) {
      return 'Server unavailable. Make sure the SmartCrop backend is running.';
    }
    return 'Failed to load fertilizer advice: $text';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _freshnessTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(topPad: MediaQuery.of(context).padding.top),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final reading = _latest;
                if (reading != null) {
                  await _load(reading: reading, at: _readingAt);
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusOverviewCard(
                      health: _report?.health,
                      hasReading: _report != null && _readingAt != null,
                      stale: _locallyStale,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Nutrient Readings'),
                    const SizedBox(height: 12),
                    _buildNutrients(),
                    const SizedBox(height: 18),
                    _Footnote(text: _footnote),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrients() {
    if (_loading && _report == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _report == null) {
      return _ErrorWidget(message: _error!);
    }
    if (_report == null) {
      return _ErrorWidget(message: _loading ? '' : 'Waiting for sensor data.');
    }

    final report = _report!;
    if (report.order.isEmpty) {
      return _ErrorWidget(message: 'No nutrient data returned.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in report.order) ...[
          _NutrientCard(nutrient: report.nutrients[key]!),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          const SizedBox(height: 4),
          _InlineWarning(message: _error!),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.onBackground,
        ),
      );
}

class _ErrorWidget extends StatelessWidget {
  final String message;
  const _ErrorWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFBA1A1A), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: const Color(0xFF4A3000),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  final String message;
  const _InlineWarning({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: GoogleFonts.manrope(
        fontSize: 11,
        color: const Color(0xFF856404),
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final double topPad;
  const _Header({required this.topPad});

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
                  'Fertilizer Advisor',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Rule-based advice from your soil readings',
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

/// Progress + freshness. The bar is driven entirely by the backend's health
/// score; there is no placeholder value.
class _StatusOverviewCard extends StatelessWidget {
  final FertilizerHealth? health;
  final bool hasReading;
  final bool stale;

  const _StatusOverviewCard({
    required this.health,
    required this.hasReading,
    required this.stale,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = !hasReading
        ? (const Color(0xFFF2F4EF), AppColors.onSurfaceVariant, 'No data')
        : stale
            ? (const Color(0xFFFFF8E1), const Color(0xFF856404), 'Stale')
            : (const Color(0xFFE8F5E9), AppColors.primary, 'Live');

    final partial = health?.partial ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  health?.label.isNotEmpty == true
                      ? health!.label
                      : 'Soil Health',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                  ),
                ),
              ),
              if (partial)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Partial',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF856404),
                    ),
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: health?.fraction ?? 0,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E4D9),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            health == null
                ? 'Waiting for the first reading'
                : '${health!.score} of ${health!.scoreOutOf}'
                    '${partial ? ' · some nutrients had no reading' : ''}',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One nutrient. Every state is rendered from the API response - the screen
/// holds no product names, units or amounts of its own.
class _NutrientCard extends StatelessWidget {
  final FertilizerRecommendation nutrient;
  const _NutrientCard({required this.nutrient});

  @override
  Widget build(BuildContext context) {
    if (nutrient.isNoReading) {
      return _tone(
        bg: const Color(0xFFF2F4EF),
        fg: AppColors.onSurfaceVariant,
        border: AppColors.outlineVariant,
        icon: Icons.sensors_off_rounded,
        title: '${nutrient.label}: $_noReadingLabel',
        detail: 'No reading was received, so this nutrient was not assessed.',
      );
    }

    if (nutrient.isWithinRange) {
      return _tone(
        bg: const Color(0xFFE8F5E9),
        fg: AppColors.primary,
        border: AppColors.primary.withValues(alpha: 0.25),
        icon: Icons.check_circle_outline_rounded,
        title: '${nutrient.label}: $_withinRangeLabel',
        detail: _bandDetail(),
      );
    }

    final excess = nutrient.isExcess;
    return _tone(
      bg: excess ? const Color(0xFFFFEBEE) : const Color(0xFFFFF8E1),
      fg: excess ? const Color(0xFFBA1A1A) : const Color(0xFF856404),
      border: excess ? const Color(0xFFFFCDD2) : const Color(0xFFFFE082),
      icon: excess ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      title: excess
          ? '${nutrient.label} above the configured range'
          : '${nutrient.label} below the configured range',
      detail: nutrient.advice,
      chips: _chips(),
    );
  }

  /// "100 ppm · band 107-131 ppm". Units always come from the response.
  String _bandDetail() {
    final current = nutrient.current;
    if (current == null || nutrient.band.length < 2) {
      return 'Within the configured range.';
    }
    return '${_num(current)} ${nutrient.unit} · configured range '
        '${_num(nutrient.band[0])}-${_num(nutrient.band[1])} ${nutrient.unit}';
  }

  List<Widget> _chips() {
    final chips = <Widget>[];
    final gap = nutrient.gap;
    if (gap != null) {
      final verb = nutrient.isExcess ? 'above' : 'below';
      chips.add(_InfoChip(
        icon: Icons.straighten_rounded,
        label: '${_num(gap)} ${nutrient.unit} $verb range',
      ));
    }
    // An amount is offered only for a confirmed deficiency, and only when the
    // backend actually computed one.
    final amount = nutrient.productKgHa;
    if (nutrient.isDeficient && amount != null && nutrient.product != null) {
      chips.add(_InfoChip(
        icon: Icons.scale_outlined,
        label: 'About ${amount.toStringAsFixed(0)} kg/ha '
            '${nutrient.product!.name}',
      ));
    }
    if (nutrient.confidenceKnown) {
      chips.add(_InfoChip(
        icon: Icons.schedule_rounded,
        label: nutrient.confidence == 'persistent'
            ? 'Confirmed over recent readings'
            : 'From the latest reading',
      ));
    }
    return chips;
  }

  Widget _tone({
    required Color bg,
    required Color fg,
    required Color border,
    required IconData icon,
    required String title,
    required String detail,
    List<Widget> chips = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  final String text;
  const _Footnote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trims a trailing ".0" so "7.0" reads as "7" but "30.4" is left alone.
String _num(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}
