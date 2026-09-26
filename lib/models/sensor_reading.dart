import 'sensor_data.dart';

/// A single sensor reading stored under
/// `sensor_history/{crop}/{yyyy-MM-dd}/{readingId}`.
class SensorReading {
  final String id;
  final DateTime recordedAt;
  final SensorData data;

  const SensorReading({
    required this.id,
    required this.recordedAt,
    required this.data,
  });

  /// Builds a reading from a `sensor_history` snapshot value.
  ///
  /// [fallbackTime] is used when the stored payload has no usable timestamp
  /// (it is derived from the `{date}` path segment).
  factory SensorReading.fromSnapshot(
    String id,
    Map<dynamic, dynamic> json, {
    DateTime? fallbackTime,
  }) {
    final raw = json['timestamp'];
    final parsed = DateTime.tryParse(raw is String ? raw : '${raw ?? ''}');
    final recordedAt = (parsed ?? fallbackTime ?? DateTime.now()).toLocal();
    return SensorReading(
      id: id,
      recordedAt: recordedAt,
      data: SensorData.fromJson(json),
    );
  }

  /// Shape persisted in `sensor_history`: the live reading fields plus the
  /// timestamp needed for month bucketing and backend history windowing.
  Map<String, dynamic> toHistoryJson() => {
    ...data.toJson(),
    'timestamp': recordedAt.toUtc().toIso8601String(),
  };

  /// Shape the monitoring backend expects for a `history` entry.
  Map<String, dynamic> toMonitorPayload() => {
    ...data.toMonitorValues(),
    'timestamp': recordedAt.toUtc().toIso8601String(),
  };
}
