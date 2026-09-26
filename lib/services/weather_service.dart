import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_model.dart';
import 'location_service.dart';

class WeatherService {
  WeatherService._();

  static const String _baseUrl =
      'https://api.open-meteo.com/v1/forecast';

  static Future<WeatherData> getWeather({
    double? latitude,
    double? longitude,
  }) async {
    // If coordinates are not provided manually,
    // use the location saved by the user.
    if (latitude == null || longitude == null) {
      final savedLocation =
          await LocationService.getSavedLocation();

      if (savedLocation == null) {
        throw Exception(
          'Please set your field location in Profile → Field Location.',
        );
      }

      latitude = savedLocation.latitude;
      longitude = savedLocation.longitude;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current':
            'temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m',
        'hourly':
            'temperature_2m,precipitation_probability,precipitation,rain,relative_humidity_2m',
        'forecast_days': '2',
        'timezone': 'auto',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Weather service returned status ${response.statusCode}',
      );
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;

    final current =
        json['current'] as Map<String, dynamic>;

    final hourly =
        json['hourly'] as Map<String, dynamic>;

    final List<dynamic> times =
        hourly['time'] ?? [];

    final List<dynamic> temperatures =
        hourly['temperature_2m'] ?? [];

    final List<dynamic> precipitationProbabilities =
        hourly['precipitation_probability'] ?? [];

    final List<dynamic> precipitation =
        hourly['precipitation'] ?? [];

    final List<dynamic> rain =
        hourly['rain'] ?? [];

    final List<dynamic> humidity =
        hourly['relative_humidity_2m'] ?? [];

    final List<HourlyWeather> hourlyWeather = [];

    final int count = [
      times.length,
      temperatures.length,
      precipitationProbabilities.length,
      precipitation.length,
      rain.length,
      humidity.length,
    ].reduce(
      (a, b) => a < b ? a : b,
    );

    for (int i = 0; i < count; i++) {
      final parsedTime =
          DateTime.tryParse(times[i].toString());

      if (parsedTime == null) {
        continue;
      }

      hourlyWeather.add(
        HourlyWeather(
          time: parsedTime,
          temperature:
              (temperatures[i] as num?)?.toDouble() ?? 0.0,
          precipitationProbability:
              (precipitationProbabilities[i] as num?)
                      ?.toDouble() ??
                  0.0,
          precipitation:
              (precipitation[i] as num?)?.toDouble() ?? 0.0,
          rain:
              (rain[i] as num?)?.toDouble() ?? 0.0,
          humidity:
              (humidity[i] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    return WeatherData(
      temperature:
          (current['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      humidity:
          (current['relative_humidity_2m'] as num?)?.toDouble() ?? 0.0,
      precipitation:
          (current['precipitation'] as num?)?.toDouble() ?? 0.0,
      rain:
          (current['rain'] as num?)?.toDouble() ?? 0.0,
      precipitationProbability:
          _currentRainProbability(hourlyWeather),
      weatherCode:
          (current['weather_code'] as num?)?.toInt() ?? 0,
      windSpeed:
          (current['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
      hourly: hourlyWeather,
    );
  }

  static double _currentRainProbability(
    List<HourlyWeather> hourly,
  ) {
    if (hourly.isEmpty) return 0;

    final now = DateTime.now();

    HourlyWeather closest = hourly.first;

    int closestDifference =
        (closest.time.difference(now).inSeconds).abs();

    for (final item in hourly.skip(1)) {
      final difference =
          (item.time.difference(now).inSeconds).abs();

      if (difference < closestDifference) {
        closest = item;
        closestDifference = difference;
      }
    }

    return closest.precipitationProbability;
  }

  static double nextHoursRainProbability(
    WeatherData weather, {
    int hours = 6,
  }) {
    if (weather.hourly.isEmpty) return 0;

    final now = DateTime.now();

    final upcoming = weather.hourly.where((item) {
      final difference = item.time.difference(now);

      return !difference.isNegative &&
          difference <= Duration(hours: hours);
    }).toList();

    if (upcoming.isEmpty) {
      return weather.precipitationProbability;
    }

    return upcoming
        .map((e) => e.precipitationProbability)
        .reduce((a, b) => a > b ? a : b);
  }

  static double nextHoursPrecipitation(
    WeatherData weather, {
    int hours = 6,
  }) {
    if (weather.hourly.isEmpty) return 0;

    final now = DateTime.now();

    final upcoming = weather.hourly.where((item) {
      final difference = item.time.difference(now);

      return !difference.isNegative &&
          difference <= Duration(hours: hours);
    }).toList();

    if (upcoming.isEmpty) {
      return weather.precipitation;
    }

    return upcoming
        .map((e) => e.precipitation)
        .fold<double>(
          0,
          (sum, value) => sum + value,
        );
  }
}