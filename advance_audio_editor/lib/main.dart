import 'package:flutter/material.dart';
import 'services/voice_service.dart';
import 'services/settings_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdvanceAudioEditorApp());
}

/// Advance Audio Editor - 100% TalkBack accessible, offline,
/// built for blind Naat / Tilawat recording. Developer: Hafiz Qasim.
class AdvanceAudioEditorApp extends StatefulWidget {
  const AdvanceAudioEditorApp({super.key});

  @override
  State<AdvanceAudioEditorApp> createState() => _AdvanceAudioEditorAppState();
}

class _AdvanceAudioEditorAppState extends State<AdvanceAudioEditorApp> {
  ThemeMode _resolvedMode = ThemeMode.dark;
  double _textScale = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SettingsService.instance.init();
    await VoiceService.instance.init();
    await VoiceService.instance.setRate(
        SettingsService.instance.voiceSpeed.rate);
    if (!mounted) return;
    setState(() {
      _resolvedMode = SettingsService.instance.themeMode;
      _textScale = SettingsService.instance.textScale;
    });
    VoiceService.instance.speak(
        'Advance Audio Editor opened. Home screen. Double tap Settings, or '
        'Double tap Studio Recording.');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advance Audio Editor',
      debugShowCheckedModeBanner: false,
      themeMode: _resolvedMode,
      // High Contrast / Light / Dark themes. Default: Dark Black + White.
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      highContrastTheme: AppThemes.highContrast,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_textScale)),
        child: child!,
      ),
      home: HomeScreen(
        onThemeChanged: (m) => setState(() => _resolvedMode = m),
        onTextScaleChanged: (s) => setState(() => _textScale = s),
      ),
    );
  }
}

class AppThemes {
  static ThemeData get dark => _base(
        background: Colors.black,
        surface: const Color(0xFF101010),
        foreground: Colors.white,
        accent: Colors.yellow,
      );

  static ThemeData get highContrast => _base(
        background: Colors.black,
        surface: Colors.black,
        foreground: Colors.yellow,
        accent: Colors.yellow,
        border: Colors.white,
      );

  static ThemeData get light => _base(
        background: Colors.white,
        surface: const Color(0xFFF2F2F2),
        foreground: Colors.black,
        accent: const Color(0xFF0A5C00),
      );

  static ThemeData _base({
    required Color background,
    required Color surface,
    required Color foreground,
    required Color accent,
    Color? border,
  }) {
    final outline = border ?? foreground.withOpacity(0.4);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: background == Colors.white ? Brightness.light : Brightness.dark,
      ).copyWith(
        surface: surface,
        onSurface: foreground,
        primary: accent,
        onPrimary: background,
        surfaceContainerHighest: surface,
      ),
      scaffoldBackgroundColor: background,
      // Every outlined control is easy to see and easy for TalkBack to hit.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: outline, width: 2),
          foregroundColor: foreground,
        ),
      ),
    );
  }
}
