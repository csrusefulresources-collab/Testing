import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// English-only voice prompts. Every action in the app speaks a
/// confirmation through this service. Voice speed: Slow / Normal / Fast.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  bool enabled = true;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(await _loadRate());
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setAwaitSpeakCompletion(false);
  }

  Future<double> _loadRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('voice_rate') ?? 0.5;
  }

  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voice_rate', rate);
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // TTS failures must never crash the app.
    }
  }

  Future<void> stop() => _tts.stop();
}

/// Voice speed presets. Flutter TTS rate: 0.0 (slowest) - 1.0 (fastest).
enum VoiceSpeed {
  slow(0.3, 'Slow'),
  normal(0.5, 'Normal'),
  fast(0.7, 'Fast');

  const VoiceSpeed(this.rate, this.label);
  final double rate;
  final String label;

  static VoiceSpeed fromLabel(String label) =>
      VoiceSpeed.values.firstWhere((v) => v.label == label,
          orElse: () => VoiceSpeed.normal);
}
