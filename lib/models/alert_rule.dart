import 'sensor_data.dart';

/// Severity band for a single monitored parameter.
///
/// The classification mirrors the backend monitoring engine
/// (`fertillizer Alerts/monitoring_engine.py`), so an alert raised on-device
/// and one raised by `POST /monitor` mean the same thing:
///
/// * [normal]   - inside `[min, max]`
/// * [warning]  - outside `[min, max]` but within [AlertRule.buffer] of it
/// * [critical] - farther than [AlertRule.buffer] from the range
enum AlertStatus { normal, warning, critical }

extension AlertStatusX on AlertStatus {
  bool get isAbnormal => this != AlertStatus.normal;

  /// Sort weight so the most severe band wins when several parameters trip
  /// on the same reading.
  int get weight => switch (this) {
        AlertStatus.normal => 0,
        AlertStatus.warning => 1,
        AlertStatus.critical => 2,
      };

  String get label => switch (this) {
        AlertStatus.normal => 'Normal',
        AlertStatus.warning => 'Warning',
        AlertStatus.critical => 'Critical',
      };
}

/// Parameters that map onto a nitrogen/phosphorus/potassium fertilizer, used
/// to pick the right advisory wording. Matches the `param in ("N", "P", "K")`
/// branch in the backend's `build_alerts_and_recommendations`.
const Set<String> _fertilizerParams = {'N', 'P', 'K'};

/// Reads a backend-named parameter out of a [SensorData].
///
/// The keys match `CROP_THRESHOLDS` in `crop_thresholds.py` and the `current`
/// contract of `POST /monitor`. Returns NaN for a parameter the ESP32 does
/// not report, so such a rule is skipped rather than compared.
double sensorValueFor(SensorData data, String key) => switch (key) {
      'N' => data.n,
      'P' => data.p,
      'K' => data.k,
      'temperature' => data.airTemp,
      'humidity' => data.airHumidity,
      'ph' => data.pH,
      'soil_moisture' => data.soilMoisturePercent,
      _ => double.nan,
    };

/// A threshold band for one sensor reading.
///
/// [min] and [max] are the acceptable range and [buffer] is how far outside it
/// a reading may drift before escalating from [AlertStatus.warning] to
/// [AlertStatus.critical].
///
/// Normally built by [AlertRule.fromThreshold] from the backend
/// `crop_thresholds.py` configuration, so on-device alerts and the Sensors
/// tab agree on what "too low" means. [defaultAlertRules] exists only as an
/// offline fallback for the case where the backend has never been reachable.
class AlertRule {
  final String key;
  final String label;
  final String unit;
  final double min;
  final double max;
  final double buffer;
  final double Function(SensorData data) read;

  /// Fertilizer descriptor from the backend config, e.g.
  /// `"nitrogen-based"`. Null for non-nutrient parameters.
  final String? fertilizer;

  AlertRule({
    required this.key,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.buffer,
    required this.read,
    this.fertilizer,
  });

  /// Builds a rule from one entry of `CROP_THRESHOLDS` as served by
  /// `GET /monitor/config`.
  ///
  /// The `fertilizer` field is absent on non-nutrient parameters, which is how
  /// the recommendation wording knows whether to suggest a fertilizer.
  factory AlertRule.fromThreshold(String key, Map<String, dynamic> cfg) {
    double read(SensorData d) => sensorValueFor(d, key);
    return AlertRule(
      key: key,
      label: cfg['label'] as String? ?? key,
      unit: cfg['unit'] as String? ?? '',
      min: (cfg['min'] as num).toDouble(),
      max: (cfg['max'] as num).toDouble(),
      buffer: (cfg['buffer'] as num?)?.toDouble() ?? 0,
      fertilizer: cfg['fertilizer'] as String?,
      read: read,
    );
  }

  AlertStatus classify(double value) {
    if (value < min - buffer || value > max + buffer) {
      return AlertStatus.critical;
    }
    if (value < min || value > max) {
      return AlertStatus.warning;
    }
    return AlertStatus.normal;
  }

  /// `40-70 %`. Exposed for the in-app UI; deliberately not used in
  /// notification text.
  String get rangeLabel =>
      '${_trim(min)}-${_trim(max)}${unit.isEmpty ? '' : ' $unit'}';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Offline fallback bands, used only when `GET /monitor/config` has never
/// succeeded on this device.
///
/// PROTOTYPE: these are general agronomic placeholders. The authoritative
/// values are the per-crop ranges in the backend's `crop_thresholds.py`.
final List<AlertRule> defaultAlertRules = [
  AlertRule(
    key: 'soil_moisture',
    label: 'Soil moisture',
    unit: '%',
    min: 40,
    max: 70,
    buffer: 10,
    read: (d) => d.soilMoisturePercent,
  ),
  AlertRule(
    key: 'N',
    label: 'Nitrogen',
    unit: 'kg/ha',
    min: 20,
    max: 120,
    buffer: 12,
    fertilizer: 'nitrogen-based',
    read: (d) => d.n,
  ),
  AlertRule(
    key: 'P',
    label: 'Phosphorus',
    unit: 'kg/ha',
    min: 10,
    max: 60,
    buffer: 8,
    fertilizer: 'phosphorus-based',
    read: (d) => d.p,
  ),
  AlertRule(
    key: 'K',
    label: 'Potassium',
    unit: 'kg/ha',
    min: 20,
    max: 180,
    buffer: 10,
    fertilizer: 'potassium-based',
    read: (d) => d.k,
  ),
  AlertRule(
    key: 'ph',
    label: 'Soil pH',
    unit: '',
    min: 6.0,
    max: 7.5,
    buffer: 0.4,
    read: (d) => d.pH,
  ),
  AlertRule(
    key: 'temperature',
    label: 'Air temperature',
    unit: 'degC',
    min: 15,
    max: 35,
    buffer: 5,
    read: (d) => d.airTemp,
  ),
  AlertRule(
    key: 'humidity',
    label: 'Relative humidity',
    unit: '%',
    min: 40,
    max: 80,
    buffer: 10,
    read: (d) => d.airHumidity,
  ),
];

/// A single threshold crossing, produced by `AlertMonitorService`.
///
/// [previous] is `null` for the first reading of a parameter, i.e. when there
/// is no prior state to compare against.
class AlertEvent {
  final AlertRule rule;
  final double value;
  final AlertStatus status;
  final AlertStatus? previous;
  final DateTime at;

  const AlertEvent({
    required this.rule,
    required this.value,
    required this.status,
    required this.previous,
    required this.at,
  });

  /// The parameter came back inside its acceptable range.
  bool get isRecovery =>
      status == AlertStatus.normal && (previous?.isAbnormal ?? false);

  /// The parameter moved into a worse band, e.g. normal -> warning.
  bool get isEscalation =>
      status.isAbnormal && (previous == null || status.weight > previous!.weight);

  /// Notification body: the recommendation only.
  ///
  /// Deliberately states neither the measured reading nor the acceptable
  /// range, so the user is told what to do rather than what the sensor said.
  /// Wording follows the monitoring engine's decision-support tone and makes
  /// no dosage claim, because the project has no validated dosage model.
  String get recommendation {
    if (isRecovery) {
      return '${rule.label} is back within its acceptable range.';
    }
    if (!status.isAbnormal) {
      return '${rule.label} is within its acceptable range.';
    }

    final low = _isLow;
    if (_fertilizerParams.contains(rule.key)) {
      final nutrient = rule.fertilizer ?? 'nutrient';
      return low
          ? '${rule.label} is below its acceptable range. Inspect the soil and '
              'consider an appropriate $nutrient fertilizer after field '
              'assessment.'
          : '${rule.label} is above its acceptable range. Avoid applying more '
              'and inspect field conditions.';
    }

    return low
        ? '${rule.label} is below its acceptable range. Inspect field '
            'conditions and review water management / irrigation after field '
            'assessment.'
        : '${rule.label} is above its acceptable range. Inspect field '
            'conditions and review drainage / water management.';
  }

  /// Notification title: which parameter, and which way it went wrong.
  String get title {
    if (isRecovery) return '${rule.label} recovered';
    return '${rule.label} ${status.label.toLowerCase()}';
  }

  bool get _isLow => value < rule.min;
}
