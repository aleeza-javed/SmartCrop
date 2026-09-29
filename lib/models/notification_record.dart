import 'alert_rule.dart';

/// One raised notification, kept so the app can show a full history after the
/// fact rather than only what is active right now.
///
/// Immutable and JSON-serialisable: the list lives in SharedPreferences as a
/// single JSON array (see `NotificationHistoryService`).
class NotificationRecord {
  /// Unique and sortable. Microsecond timestamp plus the parameter key, so two
  /// alerts in the same millisecond for different parameters stay distinct.
  final String id;

  /// What the tray showed. Includes the crop when known.
  final String title;
  final String body;

  /// Active crop at the moment the alert fired. Empty when the notifier was
  /// called without one.
  final String crop;

  /// Backend parameter key, e.g. `N`, `soil_moisture`.
  final String parameter;

  /// Human label from the threshold config, e.g. `Nitrogen`.
  final String parameterLabel;

  /// `low`, `high`, or `recovered`.
  final String direction;

  /// Severity band: `critical`, `warning`, or `normal`.
  final String severity;

  /// Measured reading at the time. Null when not applicable.
  final double? measured;
  final String? unit;
  final double? idealMin;
  final double? idealMax;

  final DateTime timestamp;
  final bool isRead;

  /// Monotonic counter assigned by the history service on write.
  ///
  /// Timestamps can tie (two alerts in the same millisecond, or a clock
  /// adjustment), and [List.sort] is not stable, so ordering by timestamp
  /// alone would reshuffle the list on every write. This breaks ties
  /// deterministically and permanently. 0 means "not yet assigned".
  final int sequence;

  const NotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.crop,
    required this.parameter,
    required this.parameterLabel,
    required this.direction,
    required this.severity,
    required this.timestamp,
    this.measured,
    this.unit,
    this.idealMin,
    this.idealMax,
    this.isRead = false,
    this.sequence = 0,
  });

  /// Builds a record from the event that produced a tray notification.
  ///
  /// Direction is derived here rather than read off the event because
  /// `AlertEvent._isLow` is library-private; `rule.min` is public and is the
  /// same comparison.
  factory NotificationRecord.fromEvent(
    AlertEvent event, {
    String? crop,
  }) {
    final rule = event.rule;
    final isRecovery = event.isRecovery;
    final direction = isRecovery
        ? 'recovered'
        : (event.value < rule.min ? 'low' : 'high');

    final label = _capitalize(crop?.trim() ?? '');

    return NotificationRecord(
      id: '${event.at.microsecondsSinceEpoch}-${rule.key}',
      // Prefix the crop so a user with several fields can tell them apart.
      title: label.isEmpty ? event.title : '$label · ${event.title}',
      body: event.recommendation,
      crop: label,
      parameter: rule.key,
      parameterLabel: rule.label,
      direction: direction,
      severity: event.status.name,
      measured: event.value,
      unit: rule.unit.isEmpty ? null : rule.unit,
      idealMin: rule.min,
      idealMax: rule.max,
      timestamp: event.at,
    );
  }

  /// True for a parameter that went back inside its acceptable range.
  bool get isRecovery => direction == 'recovered';

  /// `42 kg/ha (ideal 40-70)`, or null when the numbers are unavailable.
  String? get measuredVsIdeal {
    final m = measured;
    if (m == null) return null;
    final value = '${_trim(m)}${unit == null ? '' : ' $unit'}';
    if (idealMin == null || idealMax == null) return value;
    return '$value (ideal ${_trim(idealMin!)}-${_trim(idealMax!)})';
  }

  NotificationRecord copyWith({bool? isRead, int? sequence}) =>
      NotificationRecord(
        id: id,
        title: title,
        body: body,
        crop: crop,
        parameter: parameter,
        parameterLabel: parameterLabel,
        direction: direction,
        severity: severity,
        measured: measured,
        unit: unit,
        idealMin: idealMin,
        idealMax: idealMax,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
        sequence: sequence ?? this.sequence,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'crop': crop,
        'parameter': parameter,
        'parameterLabel': parameterLabel,
        'direction': direction,
        'severity': severity,
        'measured': measured,
        'unit': unit,
        'idealMin': idealMin,
        'idealMax': idealMax,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'isRead': isRead,
        'sequence': sequence,
      };

  /// Tolerant of missing and malformed fields: a single bad field yields
  /// sensible defaults rather than throwing and losing the whole entry.
  factory NotificationRecord.fromJson(Map<String, dynamic> json) {
    return NotificationRecord(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      crop: '${json['crop'] ?? ''}',
      parameter: '${json['parameter'] ?? ''}',
      parameterLabel: '${json['parameterLabel'] ?? json['parameter'] ?? ''}',
      direction: '${json['direction'] ?? 'high'}',
      severity: '${json['severity'] ?? 'warning'}',
      measured: _toDouble(json['measured']),
      unit: json['unit'] == null ? null : '${json['unit']}',
      idealMin: _toDouble(json['idealMin']),
      idealMax: _toDouble(json['idealMax']),
      timestamp: DateTime.tryParse('${json['timestamp'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isRead: json['isRead'] == true,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
