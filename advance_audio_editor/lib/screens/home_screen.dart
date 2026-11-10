import 'package:flutter/material.dart';
import '../services/voice_service.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';
import 'studio_screen.dart';

/// Home screen with ONLY 2 main toggles, exactly as required:
/// Settings and Studio Recording. Big buttons, English labels,
/// minimum 70 dp height, TalkBack speaks everything.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onThemeChanged,
    required this.onTextScaleChanged,
  });

  final void Function(ThemeMode) onThemeChanged;
  final void Function(String) onTextScaleChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Advance Audio Editor',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'For Naat and Tilawat recording.\nAccessibility first: TalkBack ready.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 40),
            // ---- TOGGLE 1: SETTINGS ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _HomeButton(
                label: 'SETTINGS',
                semantic: 'Settings button. Double tap to open all settings.',
                onPressed: () async {
                  await VoiceService.instance.speak('Opening Settings.');
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                            onThemeChanged: onThemeChanged,
                            onTextScaleChanged: onTextScaleChanged,
                          )));
                  if (context.mounted) {
                    VoiceService.instance.speak('Back on Home screen.');
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            // ---- TOGGLE 2: STUDIO RECORDING ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _HomeButton(
                label: 'STUDIO RECORDING',
                filled: true,
                semantic:
                    'Studio Recording button. Double tap to open the recording studio.',
                onPressed: () async {
                  await VoiceService.instance.speak('Opening Studio Recording.');
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const StudioScreen()));
                  if (context.mounted) {
                    VoiceService.instance.speak('Back on Home screen.');
                  }
                },
              ),
            ),
            const SizedBox(height: 40),
            Text('Developer: Hafiz Qasim',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton(
      {required this.label, required this.semantic, required this.onPressed,
       this.filled = false});

  final String label;
  final String semantic;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semantic,
      button: true,
      child: SizedBox(
        height: 90, // BIG button, well above the 70 dp minimum.
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: filled ? scheme.primary : scheme.surface,
            foregroundColor: filled ? scheme.onPrimary : scheme.onSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: scheme.primary, width: 2)),
          ),
          onPressed: onPressed,
          child: Text(label,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
