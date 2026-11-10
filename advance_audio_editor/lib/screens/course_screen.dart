import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../services/voice_service.dart';
import '../services/logs_service.dart';

/// ADVANCE VOICE MASTER COURSE - inside Studio Recording.
/// 3 levels, 19 lessons. Each lesson has: spoken explanation in English,
/// a 1-minute practice timer, then record-and-compare with an honest
/// "Check My Voice" that measures real loudness and stability of the
/// user's take on-device.
///
/// Honesty note: there are no pre-recorded teacher audio files inside the
/// app. The "Example by teacher voice" is a clear spoken walkthrough of
/// the exercise read by the app's English voice. The analysis gives honest
/// loudness/stability guidance, not professional vocal coaching.
class CourseScreen extends StatelessWidget {
  const CourseScreen({super.key});

  static const lessons = <CourseLesson>[
    // ---------------- LEVEL 1 - BASIC VOICE ----------------
    CourseLesson(level: 1, number: 1, title: 'Soft Voice',
      text: 'Soft Voice. Practice speaking very gently, like you are reading a '
          'soft Naat verse late at night. Keep the words clear even when quiet. '
          'Breathe gently and let the voice flow without pushing. Practice for one minute.'),
    CourseLesson(level: 1, number: 2, title: 'Loud Voice',
      text: 'Loud Voice. Practice speaking strongly, filling the room, but without '
          'shouting or straining the throat. Support the sound from your chest. '
          'Practice for one minute.'),
    CourseLesson(level: 1, number: 3, title: 'Heavy Voice',
      text: 'Heavy Voice. Practice a deep, weighty tone. Lower your pitch slightly, '
          'relax your jaw, and let the sound come from the chest. Practice for one minute.'),
    CourseLesson(level: 1, number: 4, title: 'Thick Voice',
      text: 'Thick Voice. Practice a rich, full tone with strong chest resonance. '
          'Open the mouth well and let vowels sound round and warm. Practice for one minute.'),
    CourseLesson(level: 1, number: 5, title: 'Thin Voice',
      text: 'Thin Voice. Practice a light, bright tone placed more in the head. '
          'Smile slightly while speaking to lift the sound. Use it for soft endings of verses. '
          'Practice for one minute.'),
    // ------- LEVEL 2 - DIRECTION VOICE - 3D VOICE -------
    CourseLesson(level: 2, number: 6, title: 'Left Side Voice',
      text: 'Left Side Voice. The demo plays your recording panned fully to the '
          'left speaker, so the voice comes from the left. Practice reciting while imagining '
          'the listener on your left. Practice for one minute.'),
    CourseLesson(level: 2, number: 7, title: 'Right Side Voice',
      text: 'Right Side Voice. The demo plays your recording panned fully to the '
          'right speaker, so the voice comes from the right. Practice for one minute.'),
    CourseLesson(level: 2, number: 8, title: 'Front Voice',
      text: 'Front Voice. Practice a clear centered voice, equal in both speakers, '
          'straight and direct, like facing the listener. Practice for one minute.'),
    CourseLesson(level: 2, number: 9, title: 'Back Voice',
      text: 'Back Voice. Practice a distant, soft, roomy tone, like calling from behind. '
          'The demo adds gentle space behind the voice. Practice for one minute.'),
    CourseLesson(level: 2, number: 10, title: 'Up Voice',
      text: 'Up Voice. Practice a lifted, bright, airy tone that feels high above. '
          'Raise the soft palate and let the sound float. The demo brightens the tone to '
          'suggest height. Practice for one minute.'),
    CourseLesson(level: 2, number: 11, title: 'Down Voice',
      text: 'Down Voice. Practice a grounded, deep tone that feels low, like under the floor. '
          'Relax the throat completely. The demo deepens the tone to suggest depth. '
          'Practice for one minute.'),
    CourseLesson(level: 2, number: 12, title: 'Left to Right Moving Voice',
      text: 'Left to Right Moving Voice. The demo moves the sound from the left speaker '
          'slowly to the right speaker while playing. Practice reciting steadily as the voice travels. '
          'Practice for one minute.'),
    CourseLesson(level: 2, number: 13, title: 'Right to Left Moving Voice',
      text: 'Right to Left Moving Voice. The demo moves the sound from the right speaker '
          'slowly to the left speaker. Keep your rhythm steady as the voice travels. '
          'Practice for one minute.'),
    CourseLesson(level: 2, number: 14, title: 'Round / Circle Voice',
      text: 'Round Circle Voice. The demo moves the sound around the stereo field in a '
          'circle, left and right and back again. Practice reciting smoothly, one full circle. '
          'Practice for one minute.'),
    // -------- LEVEL 3 - PROFESSIONAL NAAT VOICE --------
    CourseLesson(level: 3, number: 15, title: 'Moving Voice Up and Down with Melody',
      text: 'Melody Control. Practice moving your voice gently up and down with the melody '
          'of the verse. Slide between notes smoothly, do not jump. Practice for one minute.'),
    CourseLesson(level: 3, number: 16, title: 'Controlling Breath',
      text: 'Breath Control. Practice taking quick, silent breaths at natural pauses. '
          'Never let breath run out in the middle of a line. Fill from the stomach, not the chest. '
          'Practice for one minute.'),
    CourseLesson(level: 3, number: 17, title: 'Keeping Voice Stable in Long Verses',
      text: 'Stability. Practice one long verse without letting the pitch waver. '
          'Keep the throat relaxed and the airflow even from the first word to the last. '
          'Practice for one minute.'),
    CourseLesson(level: 3, number: 18, title: 'Keeping 8 Voices Balanced in Chorus',
      text: 'Chorus Balance. Record your part cleanly and steadily. In the Eight Voices '
          'Chorus, your lead voice stays in front and the seven harmony layers stay behind it. '
          'Practice keeping your timing even so all eight voices sit together. Practice for one minute.'),
    CourseLesson(level: 3, number: 19, title: 'Studio-Like Clarity Without Damaging the Voice',
      text: 'Studio Clarity. Practice staying close to the microphone, speaking with clean '
          'consonants and open vowels, and never straining. The app records your raw voice at '
          'forty eight thousand hertz with noise reduction, so clarity comes from calm technique. '
          'Practice for one minute.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ADVANCE VOICE MASTER COURSE')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final lvl in [1, 2, 3]) ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                lvl == 1 ? 'LEVEL 1 - BASIC VOICE'
                    : lvl == 2 ? 'LEVEL 2 - DIRECTION VOICE - 3D VOICE'
                    : 'LEVEL 3 - PROFESSIONAL NAAT VOICE',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ...lessons.where((l) => l.level == lvl).map((l) => LessonCard(lesson: l)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class CourseLesson {
  const CourseLesson(
      {required this.level, required this.number, required this.title, required this.text});
  final int level;
  final int number;
  final String title;
  final String text;
}

class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.lesson});
  final CourseLesson lesson;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lesson ${lesson.number}, ${lesson.title}. Double tap to open this lesson.',
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          minVerticalPadding: 18,
          title: Text('${lesson.number}. ${lesson.title}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          onTap: () {
            VoiceService.instance
                .speak('Lesson ${lesson.number}, ${lesson.title}.');
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => LessonDetailScreen(lesson: lesson)));
          },
        ),
      ),
    );
  }
}

class LessonDetailScreen extends StatefulWidget {
  const LessonDetailScreen({super.key, required this.lesson});
  final CourseLesson lesson;

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _userTake;
  bool _recording = false;
  Timer? _practiceTimer;
  int _secondsLeft = 60;

  Future<void> _speakLesson() async {
    await VoiceService.instance.speak(widget.lesson.text);
  }

  /// 1-minute guided practice: speaks the lesson and starts a 60-second
  /// timer with a soft alert at the end.
  void _startPractice() {
    _practiceTimer?.cancel();
    setState(() => _secondsLeft = 60);
    VoiceService.instance.speak('Practice started. One minute.');
    _practiceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        SystemSound.play(SystemSoundType.alert);
        VoiceService.instance
            .speak('Practice finished. You can now record and compare.');
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _recordTake() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      _userTake = path;
      VoiceService.instance
          .speak('Your recording is ready. Double tap Check My Voice.');
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      VoiceService.instance.speak('Microphone permission is needed.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/lesson_${widget.lesson.number}_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 48000,
          numChannels: 2,
          echoCancel: false,
          autoGain: false,
          noiseSuppress: true,
        ),
        path: path);
    setState(() => _recording = true);
    VoiceService.instance.speak('Recording started. Recite the lesson now.');
  }

  Future<void> _playTake() async {
    if (_userTake == null) {
      VoiceService.instance.speak('No recording yet.');
      return;
    }
    await _player.setFilePath(_userTake!);
    await _player.play();
    VoiceService.instance.speak('Playing your recording.');
  }

  /// "Check My Voice": honest on-device measurement of the user's take
  /// using ffmpeg volumedetect (average and peak loudness).
  Future<void> _checkMyVoice() async {
    if (_userTake == null) {
      VoiceService.instance.speak('Record first, then check.');
      return;
    }
    VoiceService.instance.speak('Checking your voice, please wait.');
    final result = await _analyze(_userTake!);
    if (result == null) {
      VoiceService.instance
          .speak('Could not analyze the recording. Please try again.');
      return;
    }
    final (meanDb, maxDb) = result;
    String advice;
    if (meanDb < -30) {
      advice = 'Your voice is quite quiet. Try to speak a little stronger.';
    } else if (meanDb > -10) {
      advice = 'Your voice is very loud. Relax a little to protect your throat.';
    } else {
      advice = 'Your loudness is in a good range.';
    }
    final peakGap = maxDb - meanDb;
    if (peakGap > 18) {
      advice +=
          ' Your volume changes a lot. Keep the airflow more even for stability.';
    } else {
      advice += ' Your volume is stable. Well done.';
    }
    if (!mounted) return;
    await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Check My Voice'),
              content: Text(
                  'Average loudness: ${meanDb.toStringAsFixed(1)} dB\n'
                  'Loudest moment: ${maxDb.toStringAsFixed(1)} dB\n\n$advice',
                  style: const TextStyle(fontSize: 17, height: 1.4)),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
              ],
            ));
    VoiceService.instance.speak(advice);
    LogsService.instance
        .add('Course', 'Lesson ${widget.lesson.number}: voice checked');
  }

  Future<(double, double)?> _analyze(String path) async {
    try {
      final session = await FFmpegKit.execute('-i "$path" -af volumedetect -f null -');
      final logs = await session.getAllLogsAsString();
      final mean = RegExp(r'mean_volume: ([-\d.]+) dB').firstMatch(logs);
      final max = RegExp(r'max_volume: ([-\d.]+) dB').firstMatch(logs);
      if (mean == null || max == null) return null;
      return (double.parse(mean.group(1)!), double.parse(max.group(1)!));
    } catch (_) {
      return null;
    }
  }

  /// Direction-voice demo: applies a real stereo effect (pan left/right,
  /// moving pan, space, brightness/depth) to the user's take so they HEAR
  /// the direction. Used for lessons 6 to 14.
  Future<void> _playDirectionDemo() async {
    if (_userTake == null) {
      VoiceService.instance.speak('Record first, then play the direction demo.');
      return;
    }
    VoiceService.instance.speak('Playing direction demo.');
    final n = widget.lesson.number;
    String filter;
    switch (n) {
      case 6: filter = 'pan=stereo|c0=1|c1=0'; break; // left only
      case 7: filter = 'pan=stereo|c0=0|c1=1'; break; // right only
      case 8: filter = 'pan=stereo|c0=0.9|c1=0.9'; break; // front / center
      case 9: filter = 'aecho=0.8:0.9:200|400:0.3|0.2'; break; // back / space
      case 10: filter = 'bass=g=-6:frequency=300,treble=g=6:frequency=3000'; break; // up
      case 11: filter = 'bass=g=6:frequency=250,treble=g=-4:frequency=3000'; break; // down
      case 12: filter = 'apulsator=hz=0.15:mode=sine:offset_l=0:offset_r=0.5'; break; // L to R
      case 13: filter = 'apulsator=hz=0.15:mode=sine:offset_l=0.5:offset_r=0'; break; // R to L
      case 14: filter = 'apulsator=hz=0.1:mode=sine'; break; // circle
      default: filter = 'anull'; break;
    }
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/demo_${n}_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      final session = await FFmpegKit.execute(
          '-y -i "${_e(_userTake!)}" -af "$filter" -ar 48000 -ac 2 "$out"');
      final ok = ReturnCode.isSuccess(await session.getReturnCode());
      if (!ok) {
        VoiceService.instance.speak('Demo could not be created');
        return;
      }
      await _player.setFilePath(out);
      await _player.play();
    } catch (_) {
      VoiceService.instance.speak('Demo could not be created');
    }
  }

  String _e(String p) => p.replaceAll('"', '\\"');

  @override
  void dispose() {
    _practiceTimer?.cancel();
    _recorder.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDirectionLesson =
        widget.lesson.level == 2 && widget.lesson.number >= 6;
    return Scaffold(
      appBar: AppBar(title: Text('Lesson ${widget.lesson.number}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.lesson.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(widget.lesson.text,
              style: const TextStyle(fontSize: 18, height: 1.5)),
          const SizedBox(height: 20),
          _CourseButton('TEACHER EXAMPLE - LISTEN', _speakLesson,
              'Teacher example button. Double tap to hear the spoken walkthrough of this lesson.'),
          const SizedBox(height: 12),
          Semantics(
            label: 'Practice button. Double tap for a one minute guided practice.',
            button: true,
            child: SizedBox(
              height: 80,
              child: FilledButton(
                onPressed: _startPractice,
                child: Text(
                    _secondsLeft > 0 && _secondsLeft < 60
                        ? 'PRACTICING... $_secondsLeft SECONDS'
                        : 'START 1 MINUTE PRACTICE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CourseButton(
              _recording ? 'STOP MY RECORDING' : 'RECORD AND COMPARE',
              _recordTake,
              _recording
                  ? 'Recording your voice now. Double tap to stop.'
                  : 'Record and compare button. Double tap to record your own voice.'),
          const SizedBox(height: 12),
          _CourseButton('PLAY MY RECORDING', _playTake,
              'Play my recording. Double tap to hear your own voice.'),
          const SizedBox(height: 12),
          _CourseButton('CHECK MY VOICE', _checkMyVoice,
              'Check My Voice button. Double tap to hear honest feedback about loudness and stability.'),
          if (isDirectionLesson) ...[
            const SizedBox(height: 12),
            _CourseButton('PLAY DIRECTION DEMO', _playDirectionDemo,
                'Play direction demo. Double tap to hear this direction effect on your own recording.'),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CourseButton extends StatelessWidget {
  const _CourseButton(this.label, this.onPressed, this.semantic);
  final String label;
  final VoidCallback onPressed;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantic,
      button: true,
      child: SizedBox(
        height: 80,
        child: OutlinedButton(
          onPressed: onPressed,
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
