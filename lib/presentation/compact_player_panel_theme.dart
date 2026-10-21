import 'package:flutter/material.dart';

ThemeData compactPlayerPanelTheme() => ThemeData.dark().copyWith(
  visualDensity: VisualDensity.compact,
  textTheme: ThemeData.dark().textTheme.copyWith(
    bodyLarge: const TextStyle(fontSize: 13, color: Colors.white),
    bodyMedium: const TextStyle(fontSize: 12, color: Colors.white),
    bodySmall: const TextStyle(fontSize: 11, color: Colors.white70),
    titleMedium: const TextStyle(fontSize: 14, color: Colors.white),
  ),
  listTileTheme: const ListTileThemeData(
    dense: true,
    minVerticalPadding: 2,
    contentPadding: EdgeInsets.symmetric(horizontal: 8),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      iconSize: 18,
      minimumSize: const Size(32, 32),
      padding: const EdgeInsets.all(4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  ),
);
