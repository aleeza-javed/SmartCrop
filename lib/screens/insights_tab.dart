import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/crop_stage.dart';
import '../models/sensor_data.dart';
import '../models/weather_model.dart';
import '../services/crop_api_service.dart';
import '../services/crop_tracking_service.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';

import 'ai_crop_screen.dart';
import 'fertilizer_screen.dart';
import 'growth_stage_screen.dart';
import 'irrigation_screen.dart';

class InsightsTab extends StatefulWidget {
  final SensorData? sensorData;
  final String crop;

  const InsightsTab({
    super.key,
    this.sensorData,
    this.crop = 'wheat',
  });

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  int _alertCount = 0;
  bool _loadingAlerts = false;

  WeatherData? _weather;
  bool _loadingWeather = false;
  String? _weatherError;

  FieldLocation? _fieldLocation;

  // Growth Stage Tracker badge state, driven by CropTrackingService.
  String _growthStageBadge = 'Set sowing date';
  bool _growthHasStage = false;

  static const _badgeNoDate = 'Set sowing date';

  /// Badge text for a crop with no saved anchor date. Follows the crop's own
  /// anchor, so a transplanting crop says "Set transplanting date".
  String _noDateBadge(CropProfile profile) => profile.noDateLabel;
  static const _badgeCheckHarvest = 'Check harvest';

  @override
  void initState() {
    super.initState();

    _loadFieldLocation();
    _fetchAlertCount();
    _fetchWeather();
    _loadGrowthBadge();
  }

  /// Reads the saved anchor date for the active crop and derives the badge.
  ///
  /// Four shapes:
  ///  * month-based perennial - the current calendar stage, no date needed;
  ///  * days-after-anchor, inside the calendar - "Stage · Day N", or the stage
  ///    name alone for calendar-mode crops;
  ///  * days-after-anchor past the last stage - "Check harvest", or the
  ///    multi-cut badge for a crop that is cut early and regrows;
  ///  * no date, or a crop with no profile - "Set sowing date".
  ///
  /// For a two-season crop the season is read from storage, falling back to
  /// the season suggested by the date itself, so the badge never disagrees
  /// with the stage screen.
  Future<void> _loadGrowthBadge() async {
    final profile = profileFor(widget.crop);
    final today = DateTime.now();

    if (profile == null) {
      _setBadge(_badgeNoDate, live: false);
      return;
    }
    final noDate = _noDateBadge(profile);

    if (profile.isMonthBased) {
      final stage = profile.monthStageFor(today.month);
      _setBadge(stage?.name ?? _badgeCheckHarvest, live: stage != null);
      return;
    }

    final results = await Future.wait([
      CropTrackingService.instance.getSowingDate(widget.crop),
      CropTrackingService.instance.getSeasonVariant(widget.crop),
    ]);
    if (!mounted) return;

    final date = results[0] as DateTime?;
    final storedVariant = results[1] as String?;

    // Fall back to the season the date implies when the user has not chosen.
    final variant = storedVariant ??
        (date == null ? null : profile.suggestedVariantForDate(date)?.name);

    final day = date == null
        ? null
        : DateTime(today.year, today.month, today.day)
            .difference(DateTime(date.year, date.month, date.day))
            .inDays;

    if (day == null) {
      _setBadge(noDate, live: false);
      return;
    }
    if (profile.isPastLastStage(day, variantName: variant)) {
      // A cut-and-regrow crop is not waiting to be harvested, so it gets its
      // own badge rather than the harvest prompt.
      _setBadge(
        profile.isMultiCut(variantName: variant)
            ? profile.pastFirstBadge
            : _badgeCheckHarvest,
        live: false,
      );
      return;
    }

    final stage = profile.stageForDay(day, variantName: variant);
    if (stage == null) {
      _setBadge(noDate, live: false);
      return;
    }
    _setBadge(
      profile.calendarMode ? stage.name : '${stage.name} · Day $day',
      live: true,
    );
  }

  void _setBadge(String text, {required bool live}) {
    if (!mounted) return;
    setState(() {
      _growthStageBadge = text;
      _growthHasStage = live;
    });
  }

  /// Teal while a stage is live, so the badge reads as "tracking", not
  /// "needs setup".
  Color get _growthBadgeColour =>
      _growthHasStage ? const Color(0xFF00695C) : AppColors.primary;

  Future<void> _loadFieldLocation() async {
    final location =
        await LocationService.getSavedLocation();

    if (!mounted) return;

    setState(() {
      _fieldLocation = location;
    });
  }

  /// Badge count for the Fertilizer Advisor card.
  ///
  /// Reads `summary.required_count` from the fertilizer endpoint rather than
  /// counting `/monitor` alerts, so the badge and the screen it opens can never
  /// disagree: the badge is literally the number of nutrients that screen will
  /// offer advice for. Nutrients with no reading are excluded by the backend,
  /// because "sensor not reporting" is not an action item.
  Future<void> _fetchAlertCount() async {
    final data = widget.sensorData;

    if (data == null) return;

    setState(() {
      _loadingAlerts = true;
    });

    try {
      final report = await CropApiService.getFertilizerReport(
        crop: widget.crop,
        npk: {'N': data.n, 'P': data.p, 'K': data.k},
        current: data.toMonitorValues(),
      );

      if (!mounted) return;

      setState(() {
        _alertCount = report.summary.requiredCount;
        _loadingAlerts = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingAlerts = false;
      });
    }
  }

  Future<void> _fetchWeather() async {
    if (mounted) {
      setState(() {
        _loadingWeather = true;
        _weatherError = null;
      });
    }

    try {
      final location =
          await LocationService.getSavedLocation();

      if (mounted) {
        setState(() {
          _fieldLocation = location;
        });
      }

      final weather = await WeatherService.getWeather(
        latitude: location?.latitude,
        longitude: location?.longitude,
      );

      if (!mounted) return;

      setState(() {
        _weather = weather;
        _loadingWeather = false;
        _weatherError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingWeather = false;
        _weatherError =
            'Unable to load weather data';
      });
    }
  }

  @override
  void didUpdateWidget(
    covariant InsightsTab oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.crop != widget.crop) {
      _fetchAlertCount();
    }

    if (oldWidget.sensorData != widget.sensorData) {
      _fetchAlertCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'AI Insights',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ML-powered predictions for your field',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 24),

          // ─────────────────────────────────────────────
          // WEATHER + IRRIGATION INTELLIGENCE
          // ─────────────────────────────────────────────

          _SectionTitle(
            title: 'Weather & Irrigation',
            subtitle:
                'Weather forecast combined with live soil conditions',
          ),

          const SizedBox(height: 14),

          _WeatherIntelligenceCard(
            weather: _weather,
            sensorData: widget.sensorData,
            loading: _loadingWeather,
            error: _weatherError,
            locationName:
                _fieldLocation?.name ??
                    'Field Location Not Set',
            onRefresh: _fetchWeather,
          ),

          const SizedBox(height: 28),

          // ─────────────────────────────────────────────
          // AI CROP PREDICTION
          // ─────────────────────────────────────────────

          _InsightEntryCard(
            title: 'AI Crop Prediction',
            subtitle:
                'Find the best crop for your current soil conditions',
            icon: Icons.eco_rounded,
            iconBg: const Color(0xFF1B5E20),
            badge: 'Wheat · 92% Match',
            badgeColor: AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiCropScreen(
                  sensorData: widget.sensorData,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ─────────────────────────────────────────────
          // FERTILIZER
          // ─────────────────────────────────────────────

          _InsightEntryCard(
            title: 'Fertilizer Advisor',
            subtitle:
                'Get fertilizer advice when soil nutrients are out of range',
            icon: Icons.science_rounded,
            iconBg: const Color(0xFF6A1B9A),
            badge: _loadingAlerts
                ? '...'
                // Verb agreement flips at 1 ("1 Needs action" / "2 Need
                // action"), the inverse of the usual plural pattern.
                : '$_alertCount ${_alertCount == 1 ? 'Needs' : 'Need'} action',
            badgeColor: _alertCount > 0
                ? const Color(0xFF856404)
                : AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FertilizerScreen(
                  sensorData: widget.sensorData,
                  crop: widget.crop,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ─────────────────────────────────────────────
          // IRRIGATION SCREEN
          // ─────────────────────────────────────────────

          _InsightEntryCard(
            title: 'Irrigation Scheduler',
            subtitle:
                'Auto-schedule irrigation based on soil moisture & weather',
            icon: Icons.water_drop_rounded,
            iconBg: const Color(0xFF0D47A1),
            badge: 'Open Scheduler',
            badgeColor: const Color(0xFF1565C0),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const IrrigationScreen(),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ─────────────────────────────────────────────
          // GROWTH STAGE TRACKER
          // ─────────────────────────────────────────────

          _InsightEntryCard(
            title: 'Growth Stage Tracker',
            subtitle:
                'Follow your crop from sowing to harvest',
            icon: Icons.timeline_rounded,
            iconBg: const Color(0xFF00695C),
            badge: _growthStageBadge,
            badgeColor: _growthBadgeColour,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GrowthStageScreen(
                    crop: widget.crop,
                    sensorData: widget.sensorData,
                  ),
                ),
              );
              // The date may have been set or cleared on that screen.
              await _loadGrowthBadge();
            },
          ),

          const SizedBox(height: 32),

          // ─────────────────────────────────────────────
          // COMING SOON
          // ─────────────────────────────────────────────

          Text(
            'Coming Soon',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
          ),

          const SizedBox(height: 12),

          _ComingSoonCard(
            icon: Icons.pest_control_rounded,
            title: 'Pest & Disease Predictor',
            subtitle:
                'Early warning system trained on regional outbreak data',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION TITLE
// ═══════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEATHER INTELLIGENCE CARD
// ═══════════════════════════════════════════════════════════════════════════

class _WeatherIntelligenceCard extends StatelessWidget {
  final WeatherData? weather;
  final SensorData? sensorData;
  final bool loading;
  final String? error;
  final String locationName;
  final VoidCallback onRefresh;

  const _WeatherIntelligenceCard({
    required this.weather,
    required this.sensorData,
    required this.loading,
    required this.error,
    required this.locationName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && weather == null) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (weather == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.outline,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error ??
                    'Weather data unavailable',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      AppColors.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
            ),
          ],
        ),
      );
    }

    final soilMoisture =
        sensorData?.soilMoisturePercent ?? 0;

    final rainSensor =
        sensorData?.rainPercent ?? 0;

    final next6hRainProbability =
        WeatherService.nextHoursRainProbability(
      weather!,
      hours: 6,
    );

    final next6hRain =
        WeatherService.nextHoursPrecipitation(
      weather!,
      hours: 6,
    );

    final recommendation =
        _getRecommendation(
      soilMoisture: soilMoisture,
      rainSensor: rainSensor,
      rainProbability:
          next6hRainProbability,
      expectedRain: next6hRain,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─────────────────────────────────────
          // WEATHER HEADER
          // ─────────────────────────────────────

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius:
                  const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Text(
                  weather!.weatherIcon,
                  style:
                      const TextStyle(fontSize: 36),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        locationName,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            GoogleFonts.manrope(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${weather!.temperature.toStringAsFixed(1)}°C',
                        style:
                            GoogleFonts.plusJakartaSans(
                          fontSize: 28,
                          fontWeight:
                              FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        weather!.condition,
                        style:
                            GoogleFonts.manrope(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight:
                              FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────
          // WEATHER METRICS
          // ─────────────────────────────────────

          Padding(
            padding:
                const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _WeatherMetric(
                    icon:
                        Icons.water_drop_outlined,
                    label: 'Humidity',
                    value:
                        '${weather!.humidity.toStringAsFixed(0)}%',
                  ),
                ),
                Expanded(
                  child: _WeatherMetric(
                    icon:
                        Icons.umbrella_outlined,
                    label: 'Rain Chance',
                    value:
                        '${next6hRainProbability.toStringAsFixed(0)}%',
                  ),
                ),
                Expanded(
                  child: _WeatherMetric(
                    icon: Icons.air_rounded,
                    label: 'Wind',
                    value:
                        '${weather!.windSpeed.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────────────
          // FIELD CONDITIONS
          // ─────────────────────────────────────

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              14,
              16,
              14,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _FieldMetric(
                        icon:
                            Icons.grass_rounded,
                        title: 'Soil Moisture',
                        value:
                            '${soilMoisture.toStringAsFixed(0)}%',
                        status:
                            _soilStatus(
                          soilMoisture,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FieldMetric(
                        icon:
                            Icons.umbrella_rounded,
                        title: 'Rain Sensor',
                        value:
                            '${rainSensor.toStringAsFixed(0)}%',
                        status:
                            _rainSensorStatus(
                          rainSensor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    const Icon(
                      Icons.water_drop_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Expected rain next 6 hours',
                      style:
                          GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w600,
                        color:
                            AppColors
                                .onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${next6hRain.toStringAsFixed(1)} mm',
                      style:
                          GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w700,
                        color:
                            AppColors.onBackground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────────────
          // IRRIGATION RECOMMENDATION
          // ─────────────────────────────────────

          Padding(
            padding:
                const EdgeInsets.all(16),
            child:
                _IrrigationRecommendationCard(
              recommendation:
                  recommendation,
            ),
          ),
        ],
      ),
    );
  }

  _IrrigationRecommendation _getRecommendation({
    required double soilMoisture,
    required double rainSensor,
    required double rainProbability,
    required double expectedRain,
  }) {
    if (soilMoisture < 20 &&
        rainProbability < 50 &&
        expectedRain < 2) {
      return const _IrrigationRecommendation(
        title: 'Irrigation Recommended',
        description:
            'Soil moisture is very low and significant rainfall is not expected in the next 6 hours.',
        icon:
            Icons.water_drop_rounded,
        type:
            _RecommendationType.irrigate,
      );
    }

    if (soilMoisture < 40 &&
        (rainProbability >= 50 ||
            expectedRain >= 2)) {
      return const _IrrigationRecommendation(
        title: 'Delay Irrigation',
        description:
            'Soil moisture is low, but rainfall is expected. Monitor the field before watering.',
        icon:
            Icons.cloudy_snowing,
        type:
            _RecommendationType.wait,
      );
    }

    if (soilMoisture >= 40) {
      if (rainProbability >= 50 ||
          expectedRain >= 2) {
        return const _IrrigationRecommendation(
          title: 'No Irrigation Needed',
          description:
              'Soil moisture is adequate and rainfall is also expected.',
          icon:
              Icons.check_circle_rounded,
          type:
              _RecommendationType.normal,
        );
      }

      return const _IrrigationRecommendation(
        title: 'No Irrigation Needed',
        description:
            'Current soil moisture is within the acceptable range.',
        icon:
            Icons.check_circle_rounded,
        type:
            _RecommendationType.normal,
      );
    }

    if (rainSensor >= 70) {
      return const _IrrigationRecommendation(
        title: 'Delay Irrigation',
        description:
            'The field rain sensor indicates wet conditions. Avoid unnecessary irrigation.',
        icon:
            Icons.umbrella_rounded,
        type:
            _RecommendationType.wait,
      );
    }

    return const _IrrigationRecommendation(
      title: 'Monitor Soil Moisture',
      description:
          'Soil moisture is below the optimal range. Continue monitoring before starting irrigation.',
      icon:
          Icons.visibility_rounded,
      type:
          _RecommendationType.monitor,
    );
  }

  String _soilStatus(double value) {
    if (value >= 40) return 'Optimal';
    if (value >= 20) return 'Low';
    return 'Dry';
  }

  String _rainSensorStatus(double value) {
    if (value >= 70) return 'Rain detected';
    if (value >= 30) return 'Possible rain';
    return 'Dry';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEATHER METRIC
// ═══════════════════════════════════════════════════════════════════════════

class _WeatherMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style:
              GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color:
                AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FIELD METRIC
// ═══════════════════════════════════════════════════════════════════════════

class _FieldMetric extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String status;

  const _FieldMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            AppColors.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        AppColors
                            .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style:
                      GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        AppColors.onBackground,
                  ),
                ),
                Text(
                  status,
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        AppColors.primary,
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
// IRRIGATION RECOMMENDATION
// ═══════════════════════════════════════════════════════════════════════════

enum _RecommendationType {
  irrigate,
  wait,
  normal,
  monitor,
}

class _IrrigationRecommendation {
  final String title;
  final String description;
  final IconData icon;
  final _RecommendationType type;

  const _IrrigationRecommendation({
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
  });
}

class _IrrigationRecommendationCard
    extends StatelessWidget {
  final _IrrigationRecommendation recommendation;

  const _IrrigationRecommendationCard({
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color background;

    switch (recommendation.type) {
      case _RecommendationType.irrigate:
        color = const Color(0xFF0D47A1);
        background =
            const Color(0xFFE3F2FD);
        break;

      case _RecommendationType.wait:
        color = const Color(0xFFE65100);
        background =
            const Color(0xFFFFF3E0);
        break;

      case _RecommendationType.normal:
        color = AppColors.primary;
        background =
            const Color(0xFFE8F5E9);
        break;

      case _RecommendationType.monitor:
        color = const Color(0xFF6A1B9A);
        background =
            const Color(0xFFF3E5F5);
        break;
    }

    return Container(
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color:
                  color.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(11),
            ),
            child: Icon(
              recommendation.icon,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.title,
                  style:
                      GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recommendation.description,
                  style:
                      GoogleFonts.manrope(
                    fontSize: 10.5,
                    height: 1.45,
                    fontWeight:
                        FontWeight.w500,
                    color:
                        AppColors
                            .onSurfaceVariant,
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
// INSIGHT ENTRY CARD
// ═══════════════════════════════════════════════════════════════════════════

class _InsightEntryCard
    extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _InsightEntryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(
                alpha: 0.06,
              ),
              blurRadius: 12,
              offset:
                  const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w700,
                      color:
                          AppColors.onBackground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style:
                        GoogleFonts.manrope(
                      fontSize: 11,
                      color:
                          AppColors
                              .onSurfaceVariant,
                      fontWeight:
                          FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration:
                        BoxDecoration(
                      color: badgeColor
                          .withValues(
                        alpha: 0.1,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),
                    child: Text(
                      badge,
                      style:
                          GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w700,
                        color:
                            badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons
                  .arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMING SOON CARD
// ═══════════════════════════════════════════════════════════════════════════

class _ComingSoonCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            AppColors.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color:
              AppColors.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(
              color:
                  AppColors.outlineVariant
                      .withValues(
                alpha: 0.5,
              ),
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
            child: Icon(
              icon,
              color: AppColors.outline,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight:
                              FontWeight.w700,
                          color:
                              AppColors
                                  .onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors
                                .outlineVariant,
                        borderRadius:
                            BorderRadius.circular(
                          999,
                        ),
                      ),
                      child: Text(
                        'Soon',
                        style:
                            GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight:
                              FontWeight.w700,
                          color:
                              AppColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style:
                      GoogleFonts.manrope(
                    fontSize: 11,
                    color:
                        AppColors.outline,
                    fontWeight:
                        FontWeight.w500,
                    height: 1.4,
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