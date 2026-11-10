import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../services/logs_service.dart';

/// TOGGLE 1: SETTINGS. A single simple scrolling list, every item is a big
/// TalkBack-labelled row that speaks its action in English.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.onTextScaleChanged,
  });

  final void Function(ThemeMode) onThemeChanged;
  final void Function(String) onTextScaleChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    VoiceService.instance.speak('Settings screen. Scroll to choose an option.');
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    final scheme = Theme.of(context).colorScheme;

    Widget tile({
      required String title,
      required String semantic,
      VoidCallback? onTap,
      String? subtitle,
    }) =>
        Semantics(
          label: semantic,
          button: onTap != null,
          child: SizedBox(
            minHeight: 70, // Minimum 70 dp for every row.
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: scheme.surface,
              child: ListTile(
                title: Text(title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: subtitle == null ? null : Text(subtitle),
                onTap: onTap == null
                    ? null
                    : () async {
                        await VoiceService.instance.speak(title);
                        onTap();
                      },
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        // 1
        tile(
          title: 'Share App',
          semantic: 'Share App. Double tap to share this app with friends.',
          onTap: () => Share.share(
              'Advance Audio Editor by Hafiz Qasim - accessible Naat and Tilawat recording studio.'),
        ),
        // 2
        tile(
          title: 'About App',
          semantic: 'About App. Double tap to hear about this app.',
          onTap: () => _info(context, 'About App',
              'Advance Audio Editor version ${s.appVersion}. '
              'A simple, powerful, high quality recorder for Naat and Tilawat, '
              'made for blind users. It works offline and every button speaks in English.'),
        ),
        // 3
        tile(
          title: 'Developer Name: Hafiz Qasim',
          semantic: 'Developer name, Hafiz Qasim. This item is information only.',
        ),
        // 4
        tile(
          title: 'How To Use App - Full Guide',
          semantic: 'How To Use App. Double tap for the full guide in English, with voice.',
          onTap: () => _howToUse(context),
        ),
        // 5
        tile(
          title: 'Logs History',
          semantic: 'Logs History. Double tap to see when you recorded, edited and saved.',
          onTap: () => _showLogs(context),
        ),
        // 6
        tile(
          title: 'Language: English Only',
          semantic: 'Language. English only. This app uses English for everything.',
        ),
        // 7
        tile(
          title: 'Theme: ${s.themeMode == ThemeMode.light
              ? 'Light' : s.themeMode == ThemeMode.highContrast
              ? 'High Contrast' : 'Dark'}',
          semantic: 'Theme. Double tap to switch between Dark, Light and High Contrast.',
          onTap: () => _pick(context, 'Theme', ['Dark', 'Light', 'High Contrast'],
              (v) async {
            await s.setTheme(v);
            widget.onThemeChanged(s.themeMode);
            VoiceService.instance.speak('Theme set to $v');
          }),
        ),
        // 8
        tile(
          title: 'Audio Quality: ${s.audioQuality.label}',
          semantic: 'Audio Quality. Double tap to choose Low, Medium, High or Studio Lossless.',
          onTap: () => _pick(context, 'Audio Quality',
              AudioQuality.values.map((a) => a.label).toList(),
              (v) async {
            await s.setAudioQuality(
                AudioQuality.values.indexWhere((a) => a.label == v));
            VoiceService.instance.speak('Audio quality set to $v');
          }),
        ),
        // 9
        tile(
          title: 'Save Format: ${s.saveFormat}',
          semantic: 'Save Format. Double tap to choose MP3, WAV, M4A and more.',
          onTap: () => _pick(context, 'Save Format',
              ['MP3', 'WAV', 'M4A', 'AAC', 'OGG', 'OPUS', 'FLAC', 'AMR', '3GP', 'AIFF'],
              (v) async {
            await s.setSaveFormat(v);
            VoiceService.instance.speak('Save format set to $v');
          }),
        ),
        // 10
        tile(
          title: 'TalkBack Voice Prompts: ${s.voicePrompts ? 'ON' : 'OFF'}',
          semantic: 'TalkBack voice prompts. Double tap to switch ON or OFF.',
          onTap: () async {
            await s.setVoicePrompts(!s.voicePrompts);
            VoiceService.instance.speak(
                'Voice prompts ${s.voicePrompts ? 'ON' : 'OFF'}');
            if (mounted) setState(() {});
          },
        ),
        // 11
        tile(
          title: 'Voice Speed: ${s.voiceSpeed.label}',
          semantic: 'Voice Speed. Double tap to choose Slow, Normal or Fast.',
          onTap: () => _pick(context, 'Voice Speed',
              VoiceSpeed.values.map((v) => v.label).toList(), (v) async {
            await s.setVoiceSpeed(VoiceSpeed.fromLabel(v));
            VoiceService.instance.speak('Voice speed set to $v');
          }),
        ),
        // 12
        tile(
          title: 'Auto Save: ${s.autoSave ? 'ON' : 'OFF'}',
          semantic: 'Auto Save. Double tap to switch ON or OFF.',
          onTap: () async {
            await s.setAutoSave(!s.autoSave);
            VoiceService.instance.speak('Auto save ${s.autoSave ? 'ON' : 'OFF'}');
            if (mounted) setState(() {});
          },
        ),
        // 13
        tile(
          title: 'Clear Cache',
          semantic: 'Clear Cache. Double tap to remove temporary files. Your recordings are never deleted.',
          onTap: () async {
            await s.clearCache();
            VoiceService.instance.speak('Cache cleared. Your recordings are safe.');
          },
        ),
        // 14
        tile(
          title: 'Reset Settings',
          semantic: 'Reset Settings. Double tap to restore all settings to default. Recordings are not deleted.',
          onTap: () => _confirm(context, 'Reset all settings to default? '
              'Your recordings will not be deleted.', () async {
            await s.resetAll();
            VoiceService.instance.speak('Settings reset to default');
            if (context.mounted) Navigator.pop(context);
          }),
        ),
        // 15
        tile(
          title: 'App Version: ${s.appVersion}',
          semantic: 'App version ${s.appVersion}. Information only.',
        ),
        // 16
        tile(
          title: 'Privacy Policy',
          semantic: 'Privacy Policy. Double tap to read the privacy policy.',
          onTap: () => _info(context, 'Privacy Policy',
              'Advance Audio Editor works fully offline. Your recordings stay on your phone. '
              'No data is collected, no ads, no tracking. Ever.'),
        ),
        // 17
        tile(
          title: 'Report Bug',
          semantic: 'Report Bug. Double tap to send an email to the developer.',
          onTap: () => launchUrl(Uri.parse(
              'mailto:support@hafizqasim.app?subject=Advance%20Audio%20Editor%20Bug%20Report')),
        ),
        // Extra: battery optimization guidance for all brands.
        tile(
          title: 'Background Recording Help (All Brands)',
          semantic:
              'Background Recording Help. Double tap for steps to allow recording in background '
              'on Samsung, Xiaomi, Vivo, Oppo, Realme and other brands.',
          onTap: () => _info(context, 'Background Recording Help',
              'To keep recording in background: open your phone Settings, then Battery, '
              'find Advance Audio Editor, and choose Unrestricted or No battery optimization. '
              'On Xiaomi and Poco also enable Autostart in Security app. '
              'On Vivo and Oppo allow Autostart in the Phone Manager app. '
              'On Samsung, remove the app from Deep sleeping apps in Battery settings.'),
        ),
      ]),
    );
  }

  Future<void> _pick(BuildContext context, String title, List<String> options,
      void Function(String) onSelected) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          ...options.map((o) => SizedBox(
                height: 70,
                child: ListTile(title: Text(o, style: const TextStyle(fontSize: 18)),
                    onTap: () => Navigator.pop(ctx, o)),
              )),
        ]),
      ),
    );
    if (value != null) onSelected(value);
    if (mounted) setState(() {});
  }

  void _info(BuildContext context, String title, String body) {
    VoiceService.instance.speak('$title. $body');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
    ));
  }

  void _confirm(BuildContext context, String message, VoidCallback onYes) {
    VoiceService.instance.speak('$message. Double tap Yes to confirm, or Cancel.');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Please Confirm'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
        TextButton(onPressed: onYes, child: const Text('YES')),
      ],
    ));
  }

  void _howToUse(BuildContext context) {
    const guide = 'How to use this app. '
        'Step 1. On the Home screen, double tap Studio Recording. '
        'Step 2. To record, double tap the Recording button once. You will hear: 3, 2, 1. '
        'Then recording starts automatically. '
        'Step 3. Double tap the same button again to pause. Double tap again to resume. '
        'Step 4. Use Play Pause to listen to your last recording. '
        'Step 5. Use Single Voice to hear the original voice, '
        'or Eight Voices Chorus to hear eight people reading together. '
        'Step 6. Use Add Merge to join recordings into one track. '
        'Use Split to cut a long recording into pieces and keep only the good pieces. '
        'Step 7. Use Delete to remove only the last piece. The app will ask you first. '
        'Step 8. Press Save. The app tells you the total time, and the time after silence removal. '
        'Then choose Save or Go Back. '
        'You can also Import a file from your phone in any format, '
        'and learn the Advance Voice Master Course inside Studio Recording.';
    _info(context, 'How To Use App', guide);
  }

  void _showLogs(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LogsHistoryScreen()));
  }
}

class LogsHistoryScreen extends StatelessWidget {
  const LogsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logs History')),
      body: FutureBuilder<List<LogEntry>>(
        future: LogsService.instance.load(),
        builder: (context, snap) {
          final logs = snap.data ?? [];
          if (logs.isEmpty) {
            return const Center(child: Text('No activity yet.'));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final e = logs[i];
              return Semantics(
                label: '${e.action}, ${e.detail}, at ${e.time}',
                child: ListTile(
                  minVerticalPadding: 16,
                  title: Text('${e.action}: ${e.detail}'),
                  subtitle: Text('${e.time.toLocal()}'.split('.').first),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
