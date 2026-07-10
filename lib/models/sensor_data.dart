class SensorData {
  final double airHumidity;
  final double airTemp;
  final double ec;
  final double k;
  final double n;
  final double p;
  final double rainPercent;
  final double soilHumidity;
  final double soilMoisturePercent;
  final double soilTemp;
  final double pH;

  const SensorData({
    required this.airHumidity,
    required this.airTemp,
    required this.ec,
    required this.k,
    required this.n,
    required this.p,
    required this.rainPercent,
    required this.soilHumidity,
    required this.soilMoisturePercent,
    required this.soilTemp,
    required this.pH,
  });

  factory SensorData.fromJson(Map<dynamic, dynamic> json) {
    return SensorData(
      airHumidity: (json['AirHumidity'] as num?)?.toDouble() ?? 0,
      airTemp: (json['AirTemp'] as num?)?.toDouble() ?? 0,
      ec: (json['EC'] as num?)?.toDouble() ?? 0,
      k: (json['K'] as num?)?.toDouble() ?? 0,
      n: (json['N'] as num?)?.toDouble() ?? 0,
      p: (json['P'] as num?)?.toDouble() ?? 0,
      rainPercent: (json['RainPercent'] as num?)?.toDouble() ?? 0,
      soilHumidity: (json['SoilHumidity'] as num?)?.toDouble() ?? 0,
      soilMoisturePercent: (json['SoilMoisturePercent'] as num?)?.toDouble() ?? 0,
      soilTemp: (json['SoilTemp'] as num?)?.toDouble() ?? 0,
      pH: (json['pH'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'AirHumidity': airHumidity,
    'AirTemp': airTemp,
    'EC': ec,
    'K': k,
    'N': n,
    'P': p,
    'RainPercent': rainPercent,
    'SoilHumidity': soilHumidity,
    'SoilMoisturePercent': soilMoisturePercent,
    'SoilTemp': soilTemp,
    'pH': pH,
  };
}

enum MoistureStatus { optimal, low, dry }
enum NutrientStatus { adequate, low, high }

extension MoistureStatusX on double {
  MoistureStatus toMoistureStatus() {
    if (this >= 40) return MoistureStatus.optimal;
    if (this >= 20) return MoistureStatus.low;
    return MoistureStatus.dry;
  }
}

extension NutrientLevelX on double {
  NutrientStatus toNutrientStatus() {
    if (this >= 20) return NutrientStatus.adequate;
    if (this >= 10) return NutrientStatus.low;
    return NutrientStatus.high;
  }
}
