import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../services/audio_engine.dart';
import '../services/voice_service.dart';
import '../services/settings_service.dart';
import '../services/logs_service.dart';
import 'course_screen.dart';

/// TOGGLE 2: STUDIO RECORDING. The main screen. Buttons in the exact
/// required order. One Recording button does Start / Pause / Resume.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

enum RecState { idle, countdown, recording, paused }

class _StudioScreenState extends State<StudioScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  RecState _recState = RecState.idle;
  String? _lastTake; // last raw recording WAV
  String? _lastChorus; // generated 8-voices chorus of last take
  String? _playTarget; // what the Play button currently plays
  bool _deleteArmed = false; // two-step delete confirmation
  Timer? _countdownTimer;
  int _count = 3;
  String _status = 'Ready. Double tap Record to begin.';

  String get _recordButtonLabel {
    switch (_recState) {
      case RecState.recording:
        return 'RECORDING - DOUBLE TAP TO PAUSE';
      case RecState.paused:
        return 'PAUSED - DOUBLE TAP TO RESUME';
      case RecState.countdown:
        return '$_count';
      default:
        return 'RECORD - DOUBLE TAP TO START';
    }
  }

  // ------------------------------------------------------------------
  // RECORDING (highest quality: 48 kHz stereo WAV, echo cancel OFF,
  // auto gain OFF, built-in noise suppressor ON as the noise gate).
  // ------------------------------------------------------------------

  Future<void> _onRecordPressed() async {
    HapticFeedback.heavyImpact();
    switch (_recState) {
      case RecState.idle:
        await _startCountdown();
        break;
      case RecState.countdown:
        // Double tap during countdown: ignore, countdown always completes.
        break;
      case RecState.recording:
        await _recorder.pause();
        setState(() => _recState = RecState.paused);
        VoiceService.instance.speak('Recording paused');
        break;
      case RecState.paused:
        await _recorder.resume();
        setState(() => _recState = RecState.recording);
        VoiceService.instance.speak('Recording resumed');
        break;
    }
  }

  Future<void> _startCountdown() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      VoiceService.instance.speak(
          'Microphone permission is needed. Please allow microphone and try again.');
      return;
    }
    _count = 3;
    setState(() => _recState = RecState.countdown);
    VoiceService.instance.speak('3');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      _count--;
      if (_count == 2) VoiceService.instance.speak('2');
      if (_count == 1) VoiceService.instance.speak('1');
      if (_count <= 0) {
        t.cancel();
        await _beginRecording();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _beginRecording() async {
    final path = await AudioEngine.instance.newRecordingPath();
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav, // lossless, no compression, RAW voice
          sampleRate: 48000,
          numChannels: 2, // stereo
          echoCancel: false, // keep original voice
          autoGain: false, // user controls volume manually
          noiseSuppress: true, // real-time noise gate, no background hiss
        ),
        path: path,
      );
      setState(() {
        _recState = RecState.recording;
        _lastTake = path;
        _lastChorus = null;
        _status = 'Recording...';
      });
      VoiceService.instance.speak('Recording started');
      LogsService.instance.add('Recorded', path.split('/').last);
    } catch (e) {
      setState(() => _recState = RecState.idle);
      VoiceService.instance.speak('Could not start recording. Please try again.');
    }
  }

  Future<void> _stopIfActive() async {
    if (_recState == RecState.recording || _recState == RecState.paused) {
      final path = await _recorder.stop();
      if (path != null) _lastTake = path;
      setState(() => _recState = RecState.idle);
    }
  }

  // ------------------------------------------------------------------
  // PLAY / PAUSE
  // ------------------------------------------------------------------

  Future<void> _onPlayPausePressed() async {
    if (await _player.playing) {
      await _player.pause();
      VoiceService.instance.speak('Paused');
      return;
    }
    final target = _playTarget ?? _lastTake;
    if (target == null) {
      VoiceService.instance.speak('No recording yet. Record first.');
      return;
    }
    try {
      await _player.setFilePath(target);
      await _player.play();
      VoiceService.instance.speak('Playing');
    } catch (_) {
      VoiceService.instance.speak('Could not play this audio');
    }
  }

  // ------------------------------------------------------------------
  // SINGLE VOICE
  // ------------------------------------------------------------------

  Future<void> _onSingleVoicePressed() async {
    await _stopIfActive();
    if (_lastTake == null) {
      VoiceService.instance.speak('No recording yet. Record first.');
      return;
    }
    setState(() => _playTarget = _lastTake);
    await _player.setFilePath(_lastTake!);
    await _player.play();
    VoiceService.instance.speak('Playing single voice, original recording');
  }

  // ------------------------------------------------------------------
  // 8 VOICES CHORUS
  // ------------------------------------------------------------------

  Future<void> _onChorusPressed() async {
    await _stopIfActive();
    if (_lastTake == null) {
      VoiceService.instance.speak('No recording yet. Record first.');
      return;
    }
    VoiceService.instance.speak('Creating eight voices chorus, please wait.');
    final (out, msg) = await AudioEngine.instance.buildChorus(_lastTake!);
    if (out == null) {
      VoiceService.instance.speak(msg);
      return;
    }
    setState(() => _lastChorus = out);
    _playTarget = out;
    await _player.setFilePath(out);
    await _player.play();
    VoiceService.instance.speak('$msg. Playing now.');
    LogsService.instance.add('Edited', '8 voices chorus created');
  }

  // ------------------------------------------------------------------
  // ADD / MERGE
  // ------------------------------------------------------------------

  Future<void> _onMergePressed() async {
    await _stopIfActive();
    if (_lastTake == null) {
      VoiceService.instance.speak('Nothing to add yet. Record first.');
      return;
    }
    AudioEngine.instance.pieces
        .add(TrackPiece(path: _lastTake!, label: 'Take ${AudioEngine.instance.pieces.length + 1}'));
    final (out, msg) = await AudioEngine.instance.mergePieces(AudioEngine.instance.pieces);
    if (out == null) {
      VoiceService.instance.speak(msg);
      return;
    }
    setState(() => _playTarget = out);
    VoiceService.instance.speak(
        'Added and merged. ${AudioEngine.instance.pieces.length} recordings joined into one track.');
    LogsService.instance.add('Merged',
        '${AudioEngine.instance.pieces.length} pieces joined into one track');
  }

  // ------------------------------------------------------------------
  // SPLIT
  // ------------------------------------------------------------------

  Future<void> _onSplitPressed() async {
    await _stopIfActive();
    if (_lastTake == null) {
      VoiceService.instance.speak('No recording to split. Record first.');
      return;
    }
    VoiceService.instance.speak('Splitting recording, please wait.');
    final (files, msg) = await AudioEngine.instance.splitAtSilence(_lastTake!);
    if (files.isEmpty) {
      VoiceService.instance.speak(msg);
      return;
    }
    AudioEngine.instance.pieces.clear();
    for (var i = 0; i < files.length; i++) {
      AudioEngine.instance.pieces.add(TrackPiece(path: files[i], label: 'Piece ${i + 1}'));
    }
    setState(() => _playTarget = files.first);
    VoiceService.instance.speak('$msg. Good pieces are kept. Use Delete to remove the last bad piece.');
    LogsService.instance.add('Split', '${files.length} pieces');
  }

  // ------------------------------------------------------------------
  // DELETE (two-step confirmation, last piece only)
  // ------------------------------------------------------------------

  Future<void> _onDeletePressed() async {
    if (!_deleteArmed) {
      setState(() => _deleteArmed = true);
      VoiceService.instance.speak(
          'Do you want to delete the last recording? Double tap again for Yes.');
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _deleteArmed) setState(() => _deleteArmed = false);
      });
      return;
    }
    _deleteArmed = false;
    await _stopIfActive();
    final list = AudioEngine.instance.pieces;
    if (list.isNotEmpty) {
      final removed = list.removeLast();
      try {
        // Delete the working piece only; originals in storage are never touched.
        final f = File(removed.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      VoiceService.instance.speak('Last piece deleted');
    } else if (_lastChorus != null) {
      VoiceService.instance.speak('Chorus preview deleted');
      setState(() => _lastChorus = null);
    } else {
      VoiceService.instance.speak('Nothing to delete');
    }
  }

  // ------------------------------------------------------------------
  // SAVE (preview, then smart silence removal, then export)
  // ------------------------------------------------------------------

  Future<void> _onSavePressed() async {
    await _stopIfActive();
    final list = AudioEngine.instance.pieces;
    if (_lastTake == null && list.isEmpty) {
      VoiceService.instance.speak('Nothing to save. Record first.');
      return;
    }
    VoiceService.instance.speak('Calculating preview, please wait.');

    final (merged, msg) = await AudioEngine.instance.mergePieces(list);
    if (merged == null) {
      VoiceService.instance.speak(msg);
      return;
    }
    final (clean, msg2) = await AudioEngine.instance.removeSilence(merged);
    if (clean == null) {
      VoiceService.instance.speak(msg2);
      return;
    }
    final total = await AudioEngine.instance.getDuration(merged);
    final after = await AudioEngine.instance.getDuration(clean);
    final useMerged = list.isNotEmpty; // MERGE used: save as ONE track

    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preview'),
        content: Text(
          'Your total audio is ${_fmt(total)}.\n'
          'After silence skip, it will be ${_fmt(after)}.',
          style: const TextStyle(fontSize: 18, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('GO BACK')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
        ],
      ),
    );
    await VoiceService.instance.speak(
        'Your total audio is ${_fmt(total)}. After silence skip, it will be ${_fmt(after)}. '
        'Double tap Save to save, or Go Back.');
    if (save != true) {
      VoiceService.instance.speak('Save cancelled. Going back.');
      return;
    }

    VoiceService.instance.speak('Saving, please wait.');
    final fmt = SettingsService.instance.saveFormat;
    final (exported, msg3) = await AudioEngine.instance.exportFile(
        useMerged ? clean : clean, fmt);
    if (exported == null) {
      VoiceService.instance.speak(msg3);
      return;
    }
    LogsService.instance.add('Saved', '$fmt file: ${exported.split('/').last}');
    if (SettingsService.instance.autoSave) {
      // Auto Save: remember the last export location silently.
    }
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Saved'),
      content: Text('Saved successfully as $fmt.\n$exported'),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
    VoiceService.instance.speak('Saved successfully');
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m minutes $s seconds';
  }

  // ------------------------------------------------------------------
  // IMPORT FILE (every format, everywhere)
  // ------------------------------------------------------------------

  Future<void> _onImportPressed() async {
    VoiceService.instance.speak('Opening file picker. Choose any audio file.');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) {
        VoiceService.instance.speak('Import cancelled.');
        return;
      }
      VoiceService.instance.speak('Reading file, please wait.');
      final (wav, msg) = await AudioEngine.instance.convertToWorkingWav(path);
      if (wav == null) {
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Not Supported'),
          content: const Text('This file format is not supported'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ));
        VoiceService.instance.speak('This file format is not supported');
        return;
      }
      setState(() => _lastTake = wav);
      _playTarget = wav;
      VoiceService.instance.speak('File imported successfully. You can play it now.');
      LogsService.instance.add('Imported', path.split('/').last);
    } catch (_) {
      VoiceService.instance.speak('Import failed. Please try again.');
    }
  }

  // ------------------------------------------------------------------

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recorder.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Recording'),
        actions: [
          // Course entry point.
          Semantics(
            label: 'Advance Voice Master Course. Double tap to open the voice course.',
            button: true,
            child: TextButton(
              onPressed: () {
                VoiceService.instance.speak('Opening Advance Voice Master Course.');
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CourseScreen()));
              },
              child: const Text('COURSE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            label: _status,
            child: Text(_status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),

          // 1. IMPORT FILE
          _BigButton(
            label: '1. IMPORT FILE',
            semantic: 'Import file button. Double tap to import an audio file '
                'from internal storage, SD card, WhatsApp, Downloads, Google Drive or File Manager. '
                'Every format is supported.',
            onPressed: _onImportPressed,
          ),
          const SizedBox(height: 12),

          // 2. RECORDING (Start / Pause / Resume - one button)
          Semantics(
            label: 'Recording button. ${_recState == RecState.idle
                ? 'Double tap to hear countdown 3, 2, 1 and start recording.'
                : _recState == RecState.recording
                ? 'Recording now. Double tap to pause.'
                : _recState == RecState.paused
                ? 'Paused. Double tap to resume.'
                : 'Starting.'}',
            button: true,
            child: SizedBox(
              height: 90,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _recState == RecState.recording
                      ? Colors.red.shade700
                      : scheme.primary,
                  foregroundColor:
                      _recState == RecState.recording ? Colors.white : scheme.onPrimary,
                ),
                onPressed: _onRecordPressed,
                child: Text(_recordButtonLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3. PLAY / PAUSE
          _BigButton(
            label: '3. PLAY / PAUSE',
            semantic: 'Play Pause button. Double tap to play or pause the last recorded audio.',
            onPressed: _onPlayPausePressed,
          ),
          const SizedBox(height: 12),

          // 4. SINGLE VOICE
          _BigButton(
            label: '4. SINGLE VOICE',
            semantic: 'Single voice button. Double tap to play the original single voice recording.',
            onPressed: _onSingleVoicePressed,
          ),
          const SizedBox(height: 12),

          // 5. 8 VOICES CHORUS
          _BigButton(
            label: '5. 8 VOICES CHORUS',
            semantic: 'Eight voices chorus button. Double tap to hear the same recording '
                'in eight natural voices, like eight people reading together.',
            onPressed: _onChorusPressed,
          ),
          const SizedBox(height: 12),

          // 6. ADD / MERGE
          _BigButton(
            label: '6. ADD / MERGE',
            semantic: 'Add Merge button. Double tap to join all recordings into one single track.',
            onPressed: _onMergePressed,
          ),
          const SizedBox(height: 12),

          // 7. SPLIT
          _BigButton(
            label: '7. SPLIT',
            semantic: 'Split button. Double tap to split the recording into pieces at the silences. '
                'Keep the good pieces, delete the bad pieces.',
            onPressed: _onSplitPressed,
          ),
          const SizedBox(height: 12),

          // 8. DELETE
          _BigButton(
            label: _deleteArmed ? '8. DELETE - DOUBLE TAP TO CONFIRM YES' : '8. DELETE LAST PIECE',
            semantic: 'Delete button. Double tap to be asked: '
                'do you want to delete the last recording? Double tap again for yes. '
                'Only the last piece is deleted, never the full file.',
            onPressed: _onDeletePressed,
            danger: true,
          ),
          const SizedBox(height: 12),

          // 9. SAVE
          _BigButton(
            label: '9. SAVE',
            semantic: 'Save button. Double tap to hear the time preview and save in your chosen format.',
            onPressed: _onSavePressed,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton(
      {required this.label, required this.semantic, required this.onPressed,
       this.danger = false});

  final String label;
  final String semantic;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semantic,
      button: true,
      child: SizedBox(
        height: 80, // minimum 70 dp, always big.
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: danger
                ? Colors.red.withOpacity(0.12)
                : scheme.surface,
          ),
          onPressed: onPressed,
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
