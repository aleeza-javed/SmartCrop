class WeatherData {
  final double temperature;
  final double humidity;
  final double precipitation;
  final double rain;
  final double precipitationProbability;
  final int weatherCode;
  final double windSpeed;
  final List<HourlyWeather> hourly;

  const WeatherData({
    required this.temperature,
    required this.humidity,
    required this.precipitation,
    required this.rain,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.windSpeed,
    required this.hourly,
  });

  String get condition {
    switch (weatherCode) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 56:
      case 57:
        return 'Freezing drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Unknown';
    }
  }

  String get weatherIcon {
    switch (weatherCode) {
      case 0:
      case 1:
        return '☀️';
      case 2:
        return '⛅';
      case 3:
        return '☁️';
      case 45:
      case 48:
        return '🌫️';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return '🌦️';
      case 61:
      case 63:
      case 65:
      case 80:
      case 81:
      case 82:
        return '🌧️';
      case 95:
      case 96:
      case 99:
        return '⛈️';
      default:
        return '🌤️';
    }
  }
}

class HourlyWeather {
  final DateTime time;
  final double temperature;
  final double precipitation;
  final double rain;
  final double precipitationProbability;
  final double humidity;

  const HourlyWeather({
    required this.time,
    required this.temperature,
    required this.precipitation,
    required this.rain,
    required this.precipitationProbability,
    required this.humidity,
  });
}