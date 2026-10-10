import 'dart:convert';
import 'dart:io';

class StorageService {
  static Directory get _storageDir {
    final appData = Platform.environment['APPDATA'] ?? '.';
    final dir = Directory('$appData/FlowStateTracker/data');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static String _fileNameForDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d.json';
  }

  static Future<void> saveDay({
    required DateTime date,
    required Map<String, int> appTotals,
    required Map<String, int> appActiveSeconds,
    required Map<String, int> appTypingSeconds,
    required Map<String, int> appKeystrokes,
    required int totalIdleSeconds,
    required Map<int, dynamic> hourlyData,
    int totalWindowSwitches = 0,
    Map<String, int> appFocusBreaks = const {},
  }) async {
    try {
      final file = File('${_storageDir.path}/${_fileNameForDate(date)}');

      final Map<String, dynamic> hourlyJson = {};
      hourlyData.forEach((hour, activity) {
        hourlyJson[hour.toString()] = {
          'appSeconds': activity.appSeconds,
          'appActiveSeconds': activity.appActiveSeconds,
          'appTypingSeconds': activity.appTypingSeconds,
          'appKeystrokes': activity.appKeystrokes,
          'idleSeconds': activity.idleSeconds,
          'keystrokes': activity.keystrokes,
        };
      });

      final payload = {
        'date': _fileNameForDate(date).replaceAll('.json', ''),
        'totalIdleSeconds': totalIdleSeconds,
        'appTotals': appTotals,
        'appActiveSeconds': appActiveSeconds,
        'appTypingSeconds': appTypingSeconds,
        'appKeystrokes': appKeystrokes,
        'hourlyData': hourlyJson,
        'totalWindowSwitches': totalWindowSwitches,
        'appFocusBreaks': appFocusBreaks,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(jsonEncode(payload));
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } catch (_) {}
  }

  static Map<String, dynamic>? loadDay(DateTime date) {
    try {
      final file = File('${_storageDir.path}/${_fileNameForDate(date)}');
      if (!file.existsSync()) return null;

      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> loadDaysInRange(DateTime start, DateTime end) {
    final List<Map<String, dynamic>> results = [];
    var current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);

    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      final data = loadDay(current);
      if (data != null) {
        results.add(data);
      }
      current = DateTime(current.year, current.month, current.day + 1);
    }

    return results;
  }
}