import 'dart:async';
import 'package:flutter/material.dart';

/// Reads the device clock on every tick, including timezone and date changes.
class SystemClock extends StatefulWidget {
  const SystemClock({super.key});
  @override
  State<SystemClock> createState() => _SystemClockState();
}

class _SystemClockState extends State<SystemClock> {
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final locale = MaterialLocalizations.of(context);
    return Semantics(
      label: 'System date and time',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              locale.formatTimeOfDay(
                TimeOfDay.fromDateTime(now),
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                  context,
                ),
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              locale.formatMediumDate(now),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
