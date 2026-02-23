import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class AppLogger {
  static File? _logFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/app.log');
      
      // Store original debugPrint
      final originalDebugPrint = debugPrint;
      
      // Override debugPrint to write to file too
      debugPrint = (String? message, {int? wrapWidth}) {
        originalDebugPrint(message, wrapWidth: wrapWidth);
        _writeToFile('[DEBUG] $message');
      };

      // Catch Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        _writeToFile('[FATAL] FlutterError: ${details.exception}\\nStackTrace: ${details.stack}');
      };

      // Catch asynchronous Dart errors
      PlatformDispatcher.instance.onError = (error, stack) {
        _writeToFile('[FATAL] AsyncError: $error\\nStackTrace: $stack');
        return true;
      };

      _initialized = true;
      _writeToFile('=== App Logger Initialized ===');
    } catch (e) {
      print('Failed to initialize logger: $e');
    }
  }

  static void _writeToFile(String message) {
    if (_logFile == null) return;
    try {
      final now = DateTime.now();
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(now);
      _logFile!.writeAsStringSync('[$timestamp] $message\\n', mode: FileMode.append);
    } catch (e) {
      // Ignore write errors to prevent infinite loops
    }
  }

  static Future<String> getLogs() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return 'No logs found.';
    }
    try {
      final lines = await _logFile!.readAsLines();
      // Return last 200 lines to avoid massive text in UI
      if (lines.length > 200) {
        return lines.sublist(lines.length - 200).join('\\n');
      }
      return lines.join('\\n');
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  static Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
      _writeToFile('=== Logs Cleared ===');
    }
  }
}
