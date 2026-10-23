import 'dart:convert';
import 'dart:io';

class CurrentWeather {
  final String city, condition;
  final double temperature, feelsLike, wind;
  final int humidity, code;
  final DateTime observedAt;
  const CurrentWeather(
    this.city,
    this.condition,
    this.temperature,
    this.feelsLike,
    this.wind,
    this.humidity,
    this.code,
    this.observedAt,
  );
}

class WeatherService {
  final Future<Map<String, dynamic>> Function(Uri)? fetch;
  WeatherService({this.fetch});
  Future<Map<String, dynamic>> get(Uri uri) async {
    if (fetch != null) return fetch!(uri);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      return await (() async {
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != 200) {
          throw const FormatException('Weather unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1000000) {
            throw const FormatException('Weather response too large');
          }
          bytes.addAll(chunk);
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }

  Future<CurrentWeather> load() async {
    final location = await get(
      Uri.https('ipwho.is', '/', {
        'fields': 'success,city,region,latitude,longitude',
      }),
    );
    final lat = location['latitude'], lon = location['longitude'];
    if (location['success'] != true ||
        lat is! num ||
        lon is! num ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Location unavailable');
    }
    final data = await get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$lat',
        'longitude': '$lon',
        'current':
            'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
        'timezone': 'auto',
        'timeformat': 'unixtime',
      }),
    );
    final current = data['current'] as Map<String, dynamic>;
    final code = (current['weather_code'] as num).toInt();
    return CurrentWeather(
      '${location['city'] ?? location['region'] ?? 'Your location'}',
      condition(code),
      (current['temperature_2m'] as num).toDouble(),
      (current['apparent_temperature'] as num).toDouble(),
      (current['wind_speed_10m'] as num).toDouble(),
      (current['relative_humidity_2m'] as num).toInt(),
      code,
      DateTime.fromMillisecondsSinceEpoch(
        (current['time'] as num).toInt() * 1000,
        isUtc: true,
      ),
    );
  }

  static String condition(int code) => switch (code) {
    0 => 'Clear sky',
    1 => 'Mostly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 || 63 || 65 => 'Rain',
    66 || 67 => 'Freezing rain',
    71 || 73 || 75 || 77 => 'Snow',
    80 || 81 || 82 => 'Rain showers',
    85 || 86 => 'Snow showers',
    95 || 96 || 99 => 'Thunderstorm',
    _ => 'Conditions unavailable',
  };
}
