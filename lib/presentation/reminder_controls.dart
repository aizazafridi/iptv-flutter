import 'package:flutter/material.dart';
import '../application/trailer_reminders.dart';
import '../domain/trailer_movie.dart';

ButtonStyle reminderButtonStyle() => TextButton.styleFrom(
  foregroundColor: Colors.white,
  backgroundColor: const Color(0xb32a2e36),
  minimumSize: const Size(0, 42),
  padding: const EdgeInsets.symmetric(horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
);

Future<void> editTrailerReminder(
  BuildContext context,
  TrailerReminders reminders,
  TrailerMovie movie,
) async {
  if (!reminders.contains(movie.id)) {
    await reminders.toggle(movie);
    return;
  }
  final prefs = reminders.preferences(movie.id);
  var release = prefs.release, availability = prefs.availability;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(movie.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              autofocus: true,
              title: const Text('Release-date reminder'),
              value: release,
              onChanged: (v) => update(() => release = v!),
            ),
            CheckboxListTile(
              title: const Text('Available in my library'),
              value: availability,
              onChanged: (v) => update(() => availability = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('Remove Reminder'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save Preferences'),
          ),
        ],
      ),
    ),
  );
  if (action == 'remove') {
    await reminders.toggle(movie);
  }
  if (action == 'save') {
    await reminders.setPreferences(
      movie.id,
      release: release,
      availability: availability,
    );
  }
}
