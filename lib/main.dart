import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'application/provider_registry.dart';
import 'application/session.dart';
import 'application/appearance.dart';
import 'data/credential_store.dart';
import 'presentation/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const StreamlaneApp());
}

class StreamlaneApp extends StatefulWidget {
  const StreamlaneApp({super.key});
  @override
  State<StreamlaneApp> createState() => _StreamlaneAppState();
}

class _StreamlaneAppState extends State<StreamlaneApp> {
  final appearance = AppAppearance();
  late final Session session = Session(
    ProviderRegistry(),
    const CredentialStore(),
    appearance: appearance,
  );
  @override
  void initState() {
    super.initState();
    session.initialize();
  }

  @override
  void dispose() {
    session.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      title: 'Streamlane',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: appearance.brightness,
        scaffoldBackgroundColor: appearance.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff9970ed),
          brightness: appearance.brightness,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: appearance.background,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: appearance.brightness == Brightness.dark
              ? const Color(0xff1b1a2b)
              : const Color(0xffe6e3ef),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ),
      home: HomeScreen(session: session, appearance: appearance),
    ),
  );
}
