import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';

class SensorService {
  final DatabaseReference _ref;

  SensorService({String? path})
      : _ref = FirebaseDatabase.instance.ref(path ?? '/');

  Stream<SensorData> sensorDataStream() {
    return _ref.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        return SensorData(
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
      }
      return SensorData.fromJson(data);
    });
  }

  Future<SensorData> getLatestData() async {
    final snapshot = await _ref.get();
    final data = snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) {
      return SensorData(
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
    }
    return SensorData.fromJson(data);
  }
}
