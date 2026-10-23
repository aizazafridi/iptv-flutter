import 'weather_scene_painter.dart';
import 'raincoat_weather_painter.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/weather_service.dart';

class WeatherPanel extends StatefulWidget {
  final WeatherService? service;
  const WeatherPanel({super.key, this.service});
  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends State<WeatherPanel>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final service = widget.service ?? WeatherService();
  late Future<CurrentWeather> weather = service.load();
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  void refresh() {
    if (mounted) {
      setState(() {
        weather = service.load();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 230,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xff191d24),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Current weather',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Refresh weather',
              onPressed: refresh,
              icon: const Icon(Icons.refresh, size: 17),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<CurrentWeather>(
            future: weather,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: refresh,
                    child: const Text('Weather unavailable. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              final w = snapshot.data!;
              if (!MediaQuery.disableAnimationsOf(context) &&
                  !motion.isAnimating) {
                motion.repeat();
              }
              final raining =
                  (w.code >= 51 && w.code <= 67) ||
                  (w.code >= 80 && w.code <= 82) ||
                  w.code >= 95;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          height: 90,
                          child: Semantics(
                            label: '${w.condition} weather illustration',
                            child: AnimatedBuilder(
                              animation: motion,
                              builder: (context, _) {
                                final phase =
                                    MediaQuery.disableAnimationsOf(context)
                                    ? 0.0
                                    : motion.value * 2 * math.pi;
                                return CustomPaint(
                                  painter: raining && w.code < 95
                                      ? RaincoatWeatherPainter(phase)
                                      : WeatherScenePainter(w.code, phase),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${w.temperature.round()}\u00b0C',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      w.condition,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Feels like ${w.feelsLike.round()}\u00b0C  |  Humidity ${w.humidity}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    Text(
                      'Wind ${w.wind.round()} km/h',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Updated ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(w.observedAt.toLocal()))} - IP location',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Text(
          'Weather: Open-Meteo | Location: IPWho.is',
          style: TextStyle(fontSize: 9, color: Colors.white38),
        ),
      ],
    ),
  );
}
