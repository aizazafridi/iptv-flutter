import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'application/provider_registry.dart';
import 'application/session.dart';
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
  late final Session session = Session(
    ProviderRegistry(),
    const CredentialStore(),
  );
  @override
  void initState() {
    super.initState();
    session.initialize();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Streamlane',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff11101c),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff9970ed),
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff11101c),
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff1b1a2b),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
    ),
    home: HomeScreen(session: session),
  );
}
