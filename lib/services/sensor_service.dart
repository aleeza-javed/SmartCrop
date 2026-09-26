import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';
import '../models/sensor_reading.dart';

class SensorService {
  /// Root of the historical reading archive.
  static const String historyRoot = 'sensor_history';

  final DatabaseReference _ref;
  final DatabaseReference _historyRef;
  String? _lastRecordedSignature;

  SensorService({String? path})
      : _ref = FirebaseDatabase.instance.ref(path ?? '/'),
        _historyRef = FirebaseDatabase.instance.ref(historyRoot);

  Stream<SensorData> sensorDataStream() {
    return _ref.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        return _empty();
      }
      return SensorData.fromJson(data);
    });
  }

  Future<SensorData> getLatestData() async {
    final snapshot = await _ref.get();
    final data = snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) {
      return _empty();
    }
    return SensorData.fromJson(data);
  }

  /// Persists [data] to the current/latest sensor location and archives the
  /// same reading under `sensor_history/{crop}/{date}/{readingId}`.
  ///
  /// Repeated calls with an identical reading are ignored, so this can safely
  /// be invoked from the live sensor stream without feedback loops.
  Future<String?> recordReading(
    SensorData data, {
    required String crop,
    bool writeLatest = true,
    DateTime? recordedAt,
  }) async {
    final signature = _signatureOf(data);
    if (signature == _lastRecordedSignature) return null;
    _lastRecordedSignature = signature;

    final when = (recordedAt ?? DateTime.now()).toLocal();

    final dayRef = _historyRef
        .child(_normalizeCrop(crop))
        .child(_dateKey(when));
    final id = dayRef.push().key;
    if (id == null) return null;

    await dayRef.child(id).set({
      ...data.toJson(),
      'crop': _normalizeCrop(crop),
      'timestamp': when.toUtc().toIso8601String(),
    });

    if (writeLatest) {
      // update() (not set()) so any extra fields the device writes alongside
      // the readings are preserved.
      await _ref.update(data.toJson());
    }
    return id;
  }

  /// All archived readings for [crop], oldest first. Returns an empty list when
  /// the crop has no history yet.
  Future<List<SensorReading>> fetchHistory(String crop) async {
    final snapshot = await _historyRef.child(_normalizeCrop(crop)).get();
    final value = snapshot.value;
    if (value is! Map) return const [];

    final readings = <SensorReading>[];
    value.forEach((dateKey, dateValue) {
      if (dateValue is! Map) return;
      final fallback = DateTime.tryParse('$dateKey');
      dateValue.forEach((readingId, readingValue) {
        if (readingValue is! Map) return;
        readings.add(
          SensorReading.fromSnapshot(
            '$readingId',
            readingValue,
            fallbackTime: fallback,
          ),
        );
      });
    });

    readings.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return readings;
  }

  static SensorData _empty() => const SensorData(
        airHumidity: 0,
        airTemp: 0,
        ec: 0,
        k: 0,
        n: 0,
        p: 0,
        rainPercent: 0,
        soilHumidity: 0,
        soilMoisturePercent: 0,
        soilTemp: 0,
        pH: 0,
      );

  static String _signatureOf(SensorData data) => [
        data.n,
        data.p,
        data.k,
        data.airTemp,
        data.airHumidity,
        data.pH,
        data.soilMoisturePercent,
        data.soilTemp,
        data.soilHumidity,
        data.rainPercent,
        data.ec,
      ].join('|');

  static String _normalizeCrop(String crop) {
    final cleaned = crop.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  static String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
