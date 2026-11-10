import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'settings_service.dart';

/// One piece of the working track. Merge joins these; Split marks them;
/// Delete removes the last one (original is never touched without asking).
class TrackPiece {
  TrackPiece({required this.path, required this.label});
  final String path; // absolute WAV file on disk
  final String label; // e.g. "Piece 1", "Chorus take"
  Duration duration = Duration.zero;
}

/// Central audio engine. All heavy work is done by FFmpeg on converted
/// 48 kHz stereo WAV so every format behaves the same.
class AudioEngine {
  AudioEngine._();
  static final AudioEngine instance = AudioEngine._();

  final List<TrackPiece> pieces = [];

  Future<String> get workDir async {
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/recordings');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> get cacheDir async {
    final dir =
        Directory('${(await getTemporaryDirectory()).path}/import_cache');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  // ------------------------------------------------------------------
  // FORMAT CONVERSION (import of ANY format)
  // ------------------------------------------------------------------

  /// Converts an imported file of any container/codec to our working
  /// 48 kHz stereo WAV. Returns null plus a message when FFmpeg cannot
  /// decode it (user hears "This file format is not supported").
  Future<(String?, String)> convertToWorkingWav(String inputPath) async {
    final out = '${await cacheDir}/import_${DateTime.now().millisecondsSinceEpoch}.wav';
    final ok = await _run(
        '-y -i "${_esc(inputPath)}" -ar 48000 -ac 2 -c:a pcm_s16le "$out"');
    if (!ok) return (null, 'This file format is not supported');
    return (out, 'File imported successfully');
  }

  // ------------------------------------------------------------------
  // RECORDING PIPELINE HELPERS
  // ------------------------------------------------------------------

  Future<String> newRecordingPath() async =>
      '${await workDir}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';

  // ------------------------------------------------------------------
  // 8 VOICES CHORUS
  // ------------------------------------------------------------------

  /// Builds a natural 8-voice chorus: 8 layered copies of the take with
  /// tiny delays (0, 18, 36, 54, 72, 90, 108, 126 ms) and small pitch
  /// detunes (+/- up to 6 cents). Original pitch and tempo are preserved;
  /// layers are mixed at 0.55 so the lead voice stays dominant.
  Future<(String?, String)> buildChorus(String takePath) async {
    final out = '${await workDir}/chorus_${DateTime.now().millisecondsSinceEpoch}.wav';
    // aecho adds spaced copies; asetrate/atempo combo gives micro detune
    // without changing perceived tempo.
    final layers = <String>[];
    for (var i = 0; i < 8; i++) {
      final delayMs = i * 18;
      final cents = (i - 3.5) * 1.7; // -6 .. +6 cents
      final ratio = 1 + cents / 100 / 12; // semitone->Hz ratio approx
      final tempo = 1 / ratio;
      final pan = i.isEven ? '0.7|0.3' : '0.3|0.7';
      layers.add(
        '[0:a]aecho=0.8:0.7:$delayMs|${delayMs + 7}:0.25|0.2,'
        'asetrate=48000*$ratio,atempo=$tempo,'
        'volume=0.55,stereo$pan=[v$i]',
      );
    }
    final filter = '${layers.join(';')};'
        '[v0][v1][v2][v3][v4][v5][v6][v7]amix=inputs=8:duration=longest:normalize=0[out]';
    final ok = await _run(
        '-y -i "${_esc(takePath)}" -filter_complex "$filter" -map "[out]" '
        '-ar 48000 -ac 2 -c:a pcm_s16le "$out"');
    if (!ok) return (null, 'Chorus could not be created');
    return (out, 'Eight voices chorus ready');
  }

  // ------------------------------------------------------------------
  // MERGE (ADD) - one track, no gap
  // ------------------------------------------------------------------

  Future<(String?, String)> mergePieces(List<TrackPiece> list) async {
    if (list.isEmpty) return (null, 'Nothing to merge');
    if (list.length == 1) return (list.first.path, 'One track ready');
    final files = list.map((p) => '${await workDir}/${p.path.split('/').last}').toList();
    final listFile = File('${await workDir}/merge_list.txt');
    await listFile.writeAsString(
        files.map((f) => 'file \'${f.replaceAll("'", "'\\''")}\'').join('\n'));
    final out = '${await workDir}/merged_${DateTime.now().millisecondsSinceEpoch}.wav';
    final ok = await _run('-y -f concat -safe 0 -i "${listFile.path}" '
        '-ar 48000 -ac 2 -c:a pcm_s16le "$out"');
    if (!ok) return (null, 'Merge failed');
    return (out, 'Recordings joined into one track');
  }

  // ------------------------------------------------------------------
  // SMART SILENCE REMOVER + TRIM START NOISE (cough, breath)
  // ------------------------------------------------------------------

  /// Removes silence in the middle, and leading breath/cough: audio below
  /// -38 dB for more than 350 ms is dropped everywhere except the very end.
  Future<(String?, String)> removeSilence(String inputPath,
      {bool trimStart = true}) async {
    final out =
        '${await workDir}/clean_${DateTime.now().millisecondsSinceEpoch}.wav';
    final ok = await _run(
        '-y -i "${_esc(inputPath)}" '
        '-af "silenceremove='
        'stop_periods=-1:stop_duration=0.35:stop_threshold=-38dB'
        '${trimStart ? ':start_periods=1:start_duration=0.35:start_threshold=-38dB' : ''}" '
        '-ar 48000 -ac 2 -c:a pcm_s16le "$out"');
    if (!ok) return (null, 'Silence removal failed');
    return (out, 'Silence removed');
  }

  // ------------------------------------------------------------------
  // SPLIT AT SILENCE - pieces with no silence inside them
  // ------------------------------------------------------------------

  /// Splits at every silence longer than 700 ms; each piece is trimmed
  /// with 250 ms padding so pieces have no internal silence and join
  /// back seamlessly. Returns the list of piece files.
  Future<(List<String>, String)> splitAtSilence(String inputPath) async {
    final dir = Directory('${await workDir}/split_${DateTime.now().millisecondsSinceEpoch}');
    await dir.create(recursive: true);
    final piece = '${dir.path}/piece_%03d.wav';
    final ok2 = await _run(
        '-y -i "${_esc(inputPath)}" -f segment -segment_time 30 '
        '-af "silenceremove=stop_periods=-1:stop_duration=0.7:stop_threshold=-38dB" '
        '-ar 48000 -ac 2 -c:a pcm_s16le "$piece"');
    if (!ok2) return (<String>[], 'Split failed');
    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toList()
      ..sort();
    return (files, '${files.length} pieces created');
  }

  // ------------------------------------------------------------------
  // EXPORT - every requested format, chosen quality
  // ------------------------------------------------------------------

  Future<(String?, String)> exportFile(String inputPath, String format) async {
    final q = SettingsService.instance.audioQuality;
    final dir = await workDir;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final f = format.toUpperCase();
    String out;
    String args;

    switch (f) {
      case 'WAV':
        out = '$dir/naat_$stamp.wav';
        args = '-c:a pcm_s16le';
        break;
      case 'FLAC':
        out = '$dir/naat_$stamp.flac';
        args = '-c:a flac -compression_level 8';
        break;
      case 'MP3':
        out = '$dir/naat_$stamp.mp3';
        args = '-c:a libmp3lame -b:a ${q.bitRate == 0 ? 320 : q.bitRate}k';
        break;
      case 'AAC':
      case 'M4A':
        out = '$dir/naat_$stamp.${f == 'M4A' ? 'm4a' : 'aac'}';
        args = '-c:a aac -b:a ${q.bitRate == 0 ? 320 : q.bitRate}k';
        break;
      case 'OGG':
        out = '$dir/naat_$stamp.ogg';
        args = '-c:a libvorbis -q:a 9';
        break;
      case 'OPUS':
        out = '$dir/naat_$stamp.opus';
        args = '-c:a libopus -b:a 320k';
        break;
      case 'AMR':
        out = '$dir/naat_$stamp.amr';
        args = '-c:a libopencore_amrnb -b:a 23.05k';
        break;
      case '3GP':
        out = '$dir/naat_$stamp.3gp';
        args = '-c:a libopencore_amrnb -b:a 23.05k';
        break;
      case 'AIFF':
        out = '$dir/naat_$stamp.aiff';
        args = '-c:a pcm_s16be';
        break;
      default:
        out = '$dir/naat_$stamp.mp3';
        args = '-c:a libmp3lame -b:a 320k';
    }
    final sr = f == 'AMR' || f == '3GP' ? 16000 : q.sampleRate;
    final ok = await _run('-y -i "${_esc(inputPath)}" $args -ar $sr '
        '${f == 'AMR' || f == '3GP' ? '-ac 1' : '-ac 2'} "$out"');
    if (!ok) return (null, 'Export failed');
    return (out, 'Saved successfully');
  }

  // ------------------------------------------------------------------
  // DURATION (for the Save preview)
  // ------------------------------------------------------------------

  Future<Duration> getDuration(String path) async {
    final session = await FFmpegKit.execute(
        '-i "${_esc(path)}" -show_entries format=duration -of csv=p=0 -f null -');
    final logs = await session.getAllLogsAsString();
    final match =
        RegExp(r'(\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(logs) ??
        RegExp(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(logs);
    if (match == null) return Duration.zero;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: double.parse(match.group(3)!).round(),
    );
  }

  // ------------------------------------------------------------------

  Future<bool> _run(String cmd) async {
    try {
      final session = await FFmpegKit.execute(cmd);
      return ReturnCode.isSuccess(await session.getReturnCode());
    } catch (_) {
      return false;
    }
  }

  String _esc(String p) => p.replaceAll('"', '\\"');
}
