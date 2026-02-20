class LogService {
  static final List<String> _logs = [];
  static const int _maxLogs = 500;

  static List<String> get logs => List.unmodifiable(_logs);

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  static void clear() {
    _logs.clear();
  }
}
