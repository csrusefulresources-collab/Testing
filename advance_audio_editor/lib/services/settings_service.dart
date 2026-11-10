import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_service.dart';

/// All persisted settings. Simple, safe defaults for blind users.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---------- Theme ----------
  ThemeMode get themeMode {
    final v = _prefs.getString('theme') ?? 'Dark';
    if (v == 'Light') return ThemeMode.light;
    if (v == 'High Contrast') return ThemeMode.highContrast;
    return ThemeMode.dark;
  }

  double get textScale {
    final v = _prefs.getString('text_scale') ?? 'Normal';
    if (v == 'Large') return 1.25;
    if (v == 'Extra Large') return 1.5;
    return 1.0;
  }

  Future<void> setTheme(String value) => _prefs.setString('theme', value);
  Future<void> setTextScale(String value) =>
      _prefs.setString('text_scale', value);

  // ---------- Audio quality ----------
  AudioQuality get audioQuality => AudioQuality
      .values[_prefs.getInt('quality') ?? AudioQuality.studio.index];
  Future<void> setAudioQuality(int i) => _prefs.setInt('quality', i);

  // ---------- Save format ----------
  String get saveFormat => _prefs.getString('format') ?? 'MP3';
  Future<void> setSaveFormat(String f) => _prefs.setString('format', f);

  // ---------- TalkBack / voice prompt toggle ----------
  bool get voicePrompts => _prefs.getBool('voice_prompts') ?? true;
  Future<void> setVoicePrompts(bool v) async {
    await _prefs.setBool('voice_prompts', v);
    VoiceService.instance.enabled = v;
  }

  VoiceSpeed get voiceSpeed =>
      VoiceSpeed.fromLabel(_prefs.getString('speed') ?? 'Normal');
  Future<void> setVoiceSpeed(VoiceSpeed s) async {
    await _prefs.setString('speed', s.label);
    await VoiceService.instance.setRate(s.rate);
  }

  // ---------- Auto save ----------
  bool get autoSave => _prefs.getBool('auto_save') ?? false;
  Future<void> setAutoSave(bool v) => _prefs.setBool('auto_save', v);

  // ---------- Cache / reset ----------
  Future<void> clearCache() async {
    // Cached converted import files live in the app cache directory;
    // settings and recordings are never touched here.
    await _prefs.remove('last_import_path');
  }

  Future<void> resetAll() async {
    await _prefs.clear();
    VoiceService.instance.enabled = true;
    await VoiceService.instance.setRate(VoiceSpeed.normal.rate);
  }

  String get appVersion => '1.0.0';
}

enum AudioQuality {
  low('Low', 22050, 96),
  medium('Medium', 44100, 192),
  high('High', 48000, 320),
  studio('Studio Lossless', 48000, 0); // 0 = lossless WAV

  const AudioQuality(this.label, this.sampleRate, this.bitRate);
  final String label;
  final int sampleRate;
  final int bitRate; // kbps; 0 means lossless WAV
}
