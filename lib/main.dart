import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'application/provider_registry.dart';
import 'application/session.dart';
import 'application/appearance.dart';
import 'data/credential_store.dart';
import 'presentation/home_screen.dart';
import 'presentation/focus_tooltips.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
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
      title: 'Streamora',
      builder: (context, child) =>
          FocusTooltips(child: child ?? const SizedBox.shrink()),
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
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
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const Color(0xff7959bd)
                  : null,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.focused) ? Colors.white : null,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: Colors.white, width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style:
              FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                side: const BorderSide(color: Colors.white54),
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const Color(0xff7959bd)
                      : null,
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const BorderSide(color: Colors.white, width: 3)
                      : const BorderSide(color: Colors.white24),
                ),
              ),
        ),
      ),
      home: HomeScreen(session: session, appearance: appearance),
    ),
  );
}
