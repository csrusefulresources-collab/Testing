import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry shown in Settings > Logs History: when the user recorded,
/// edited or saved.
class LogEntry {
  LogEntry({required this.time, required this.action, required this.detail});
  final DateTime time;
  final String action; // Recorded / Edited / Saved / Imported / Merged / Split
  final String detail;

  Map<String, dynamic> toMap() => {
        't': time.toIso8601String(),
        'a': action,
        'd': detail,
      };

  factory LogEntry.fromMap(Map<String, dynamic> m) => LogEntry(
        time: DateTime.parse(m['t'] as String),
        action: m['a'] as String,
        detail: m['d'] as String,
      );
}

/// Lightweight log storage in SharedPreferences. Never deletes recordings.
class LogsService {
  LogsService._();
  static final LogsService instance = LogsService._();

  static const _key = 'logs_history';

  Future<List<LogEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (json.decode(raw) as List)
          .map((e) => LogEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      return list.reversed.toList(); // newest first
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String action, String detail) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = json.decode(raw) as List;
      } catch (_) {}
    }
    list.add(LogEntry(
            time: DateTime.now(), action: action, detail: detail)
        .toMap());
    // Keep the most recent 200 entries so storage stays light.
    if (list.length > 200) list = list.sublist(list.length - 200);
    await prefs.setString(_key, json.encode(list));
  }
}
