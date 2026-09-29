import '../models/alert_rule.dart';
import '../models/sensor_data.dart';

/// Turns a stream of [SensorData] readings into [AlertEvent]s, firing only
/// when a parameter *changes* severity band.
///
/// Rationale: the ESP32 republishes continuously and a field can sit outside
/// its band for days. Alerting on every sample would bury the user, so this
/// keeps the last band per parameter and emits on the transition only. The
/// user therefore hears about a problem when it starts and again when it
/// recovers, and not in between.
///
/// This is intentionally on-device: it does not depend on the Flask backend
/// being reachable, so alerts still work on a farm with no LAN to the
/// developer machine. The trade-off is that these bands are the generic
/// [defaultAlertRules] rather than the crop-specific thresholds the backend
/// uses - pass a different [rules] list to align them.
class AlertMonitorService {
  /// Band definitions in force. Swapped for the active crop's backend
  /// thresholds via [setRules].
  List<AlertRule> rules;
  final Map<String, AlertStatus> _lastStatus = {};
  final Map<String, double> _lastValue = {};
  final DateTime Function() _now;

  AlertMonitorService({
    List<AlertRule>? rules,
    DateTime Function()? now,
  })  : rules = rules ?? defaultAlertRules,
        _now = now ?? DateTime.now;

  /// Swaps in a new band table and re-baselines, so the next reading is
  /// compared against the new ranges rather than the old ones.
  void setRules(List<AlertRule> next) {
    rules = next;
    reset();
  }

  /// Severity band currently held for [key], or `null` if the parameter has
  /// not been evaluated yet.
  AlertStatus? statusOf(String key) => _lastStatus[key];

  /// Every parameter currently in an abnormal band, with the value that put
  /// it there.
  List<AlertEvent> get activeIssues => [
        for (final rule in rules)
          if (_lastStatus[rule.key]?.isAbnormal ?? false)
            AlertEvent(
              rule: rule,
              value: _lastValue[rule.key] ?? 0,
              status: _lastStatus[rule.key]!,
              previous: _lastStatus[rule.key],
              at: _now(),
            ),
      ];

  /// Classifies [data] against every rule and returns only the transitions
  /// worth alerting on.
  ///
  /// The first reading for a parameter establishes a baseline and returns
  /// nothing, so opening the app does not fire a burst of notifications for
  /// conditions that predate it. The one exception is a parameter that is
  /// [AlertStatus.critical] on that first reading: a field at 12% soil
  /// moisture should be reported even if the app was not open to see it
  /// happen.
  List<AlertEvent> evaluate(SensorData data) {
    if (data.isEmpty) return const [];

    final events = <AlertEvent>[];

    for (final rule in rules) {
      final value = rule.read(data);
      // A parameter the device does not report reads as NaN. Never classify
      // it, and never let a stale band linger for it.
      if (value.isNaN) continue;

      final status = rule.classify(value);
      final previous = _lastStatus[rule.key];

      if (previous == null) {
        _lastStatus[rule.key] = status;
        _lastValue[rule.key] = value;
        if (status == AlertStatus.critical) {
          events.add(AlertEvent(
            rule: rule,
            value: value,
            status: status,
            previous: null,
            at: _now(),
          ));
        }
        continue;
      }

      if (status == previous) continue;

      _lastStatus[rule.key] = status;
      _lastValue[rule.key] = value;
      events.add(AlertEvent(
        rule: rule,
        value: value,
        status: status,
        previous: previous,
        at: _now(),
      ));
    }

    return events;
  }

  /// Forgets all tracked bands, so the next [evaluate] re-baselines. Call
  /// when the active crop changes and the rules are swapped.
  void reset() {
    _lastStatus.clear();
    _lastValue.clear();
  }
}
