import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String signalServerBaseUrl = 'http://localhost:3001';

class EngineLogService {
  static final List<String> _engineLogs = [];
  static final List<String> _signalLogs = [];
  static const int _maxLogs = 500;

  static List<String> get engineLogs => List.unmodifiable(_engineLogs);
  static List<String> get signalLogs => List.unmodifiable(_signalLogs);

  static void addEngineLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _engineLogs.add('[$timestamp] $message');
    if (_engineLogs.length > _maxLogs) {
      _engineLogs.removeAt(0);
    }
  }

  static void addSignalLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _signalLogs.add('[$timestamp] $message');
    if (_signalLogs.length > _maxLogs) {
      _signalLogs.removeAt(0);
    }
  }

  static void clearEngineLogs() => _engineLogs.clear();
  static void clearSignalLogs() => _signalLogs.clear();
}

/// Manages a Go-based sharestream-engine subprocess for P2P streaming.
///
/// Desktop only (Windows/macOS). Communicates via stdin/stdout JSON.
/// The engine seeds & downloads torrents, and creates a localhost HTTP
/// server so media_kit can play via Range requests.
///
/// Drop-in replacement for the Node.js torrent-bridge.
class TorrentService {
  Process? _process;
  Process? _signalProcess;
  StreamSubscription? _stdoutSub;
  File? _logFile;
  Timer? _watchdogTimer;
  int _restartCount = 0;
  static const int _maxRestarts = 3;

  static String? _cachedTunnelUrl;
  
  /// Whether we're on a mobile platform (no local engine).
  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // State
  final ValueNotifier<bool> isReady = ValueNotifier(false);
  final ValueNotifier<bool> isSeeding = ValueNotifier(false);
  final ValueNotifier<bool> isDownloading = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<int> downloadSpeed = ValueNotifier(0);
  final ValueNotifier<int> numPeers = ValueNotifier(0);
  final ValueNotifier<String?> serverUrl = ValueNotifier(null);
  final ValueNotifier<String?> magnetUri = ValueNotifier(null);
  final ValueNotifier<String?> torrentName = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  // Completers for awaitable commands
  Completer<String?>? _seedCompleter;
  Completer<String?>? _addCompleter;

  String get _trackerUrl {
    final url = dotenv.env['SERVER_URL'] ?? signalServerBaseUrl;
    return '${url.replaceFirst(RegExp(r'^http'), 'ws')}/';
  }

  static String? get tunnelUrl => _cachedTunnelUrl;

  Future<bool> checkAndStartSignalServer() async {
    try {
      final response = await http.get(Uri.parse('$signalServerBaseUrl/health')).timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode == 200) {
        _log('[signal] Signal server already running on $signalServerBaseUrl');
        // Try to get tunnel URL, but don't kill the server if it fails
        await _fetchTunnelUrl();
        return true;
      }
    } catch (e) {
      _log('[signal] Signal server not running, starting it...');
    }

    return await _startSignalServer();
  }

  Future<void> _killExistingSignalServer() async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'sharestream-signal.exe', '/T']);
      } else {
        await Process.run('pkill', ['-f', 'sharestream-signal']);
      }
      _log('[signal] Killed existing sharestream-signal processes');
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      _log('[signal] Failed to kill existing signal server: $e');
    }
  }

  Future<bool> _startSignalServer() async {
    try {
      final signalPath = await _findSignalPath();
      if (signalPath == null) {
        _log('[signal] Could not find sharestream-signal');
        return false;
      }

      _log('[signal] Starting signal server: $signalPath');
      _signalProcess = await Process.start(
        signalPath,
        [],
        runInShell: true,
      );

      _signalProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _log('[signal-stdout] $line');
        EngineLogService.addSignalLog('[signal-stdout] $line');
      });

      _signalProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _log('[signal-stderr] $line');
        EngineLogService.addSignalLog('[signal-stderr] $line');
      });

      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          final response = await http.get(Uri.parse('$signalServerBaseUrl/health')).timeout(
            const Duration(seconds: 2),
          );
          if (response.statusCode == 200) {
            _log('[signal] Signal server started successfully');
            await _fetchTunnelUrl();
            return true;
          }
        } catch (e) {
          continue;
        }
      }

      _log('[signal] Failed to start signal server');
      return false;
    } catch (e) {
      _log('[signal] Error starting signal server: $e');
      return false;
    }
  }

  Future<bool> _fetchTunnelUrl() async {
    // Retry up to 3 times — the tunnel may take a while to become ready
    for (int attempt = 0; attempt < 3; attempt++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final response = await http.get(Uri.parse('$signalServerBaseUrl/api/tunnel')).timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // Server returns key 'tunnel', with a 'ready' boolean
          final url = data['tunnel'] as String?;
          final ready = data['ready'] as bool? ?? false;
          if (ready && url != null && url.isNotEmpty) {
            _cachedTunnelUrl = url;
            _log('[signal] Got tunnel URL: $_cachedTunnelUrl');
            return true;
          }
          _log('[signal] Tunnel not ready yet (attempt ${attempt + 1}/3)');
        }
      } catch (e) {
        _log('[signal] Could not fetch tunnel URL (attempt ${attempt + 1}/3): $e');
      }
    }
    _log('[signal] Tunnel URL unavailable after 3 attempts');
    return false;
  }

  Future<String?> _findSignalPath() async {
    final candidates = [
      'C:/Users/biswa/ShareStream/go/sharestream-signal/sharestream-signal.exe',
      'C:/Users/biswa/ShareStream/go/sharestream-signal/sharestream-signal',
      '${Directory.current.path}/go/sharestream-signal/sharestream-signal.exe',
      '${Directory.current.path}/go/sharestream-signal/sharestream-signal',
      '${File(Platform.resolvedExecutable).parent.path}/sharestream-signal.exe',
      '${File(Platform.resolvedExecutable).parent.path}/sharestream-signal',
    ];

    final exeExt = Platform.isWindows ? '.exe' : '';
    candidates.add('C:/Users/biswa/ShareStream/go/sharestream-signal/bin/sharestream-signal$exeExt');
    candidates.add('sharestream-signal$exeExt');
    candidates.add('${File(Platform.resolvedExecutable).parent.path}/sharestream-signal$exeExt');

    for (final path in candidates) {
      var fullPath = path.replaceAll('\$exeExt', exeExt);
      fullPath = fullPath.replaceAll('\$\{Directory.current.path\}', Directory.current.path);
      fullPath = fullPath.replaceAll('\$\{File(Platform.resolvedExecutable).parent.path\}', 
          File(Platform.resolvedExecutable).parent.path);
      fullPath = fullPath.replaceAll('\$debugPath', 'C:/Users/biswa/ShareStream/go/sharestream-signal/bin/sharestream-signal$exeExt');
      
      if (File(fullPath).existsSync()) {
        _log('[signal] Found signal at: $fullPath');
        return fullPath;
      }
    }

    try {
      final result = await Process.run('where', ['sharestream-signal$exeExt']);
      if (result.exitCode == 0) {
        final foundPath = (result.stdout as String).trim().split('\n').first;
        _log('[signal] Found signal in PATH: $foundPath');
        return foundPath;
      }
    } catch (e) {
      // Ignore
    }

    _log('[signal] Signal not found');
    return null;
  }

  /// Start the Go engine process.
  /// On mobile platforms, skips local engine (uses tunnel-based streaming).
  Future<bool> start() async {
    if (_process != null) return true;

    // Mobile doesn't run a local engine
    if (isMobile) {
      _log('[torrent] Mobile platform — skipping local engine');
      isReady.value = true;
      return true;
    }

    await checkAndStartSignalServer();

    try {
      await _initLogging();
      _log('[torrent] Starting TorrentService...');

      final enginePath = await _findEnginePath();
      if (enginePath == null) {
        final err = 'Could not find sharestream-engine';
        _log('[torrent] Error: $err');
        lastError.value = err;
        return false;
      }

      _log('[torrent] Starting engine: $enginePath');

      // Port 0 = auto-assign; the engine reports the actual port in events
      _process = await Process.start(
        enginePath,
        ['-http', ':0'],
        runInShell: true,
      );

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleMessage);

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _log('[torrent-stderr] $line');
      });

      _process!.exitCode.then((code) {
        _log('[torrent] Engine exited with code: $code');
        _process = null;
        isReady.value = false;
        _stopWatchdog();
        // Auto-restart on unexpected exit
        if (_restartCount < _maxRestarts) {
          _restartCount++;
          _log('[torrent] Auto-restarting engine (attempt $_restartCount/$_maxRestarts)');
          Future.delayed(const Duration(seconds: 2), () => start());
        } else {
          lastError.value = 'Engine crashed $_maxRestarts times, giving up';
        }
      });

      await _waitForReady();
      if (isReady.value) {
        _restartCount = 0; // Reset on successful start
        _startWatchdog();
      }
      return isReady.value;
    } catch (e) {
      _log('[torrent] Failed to start engine: $e');
      lastError.value = 'Failed to start: $e';
      return false;
    }
  }

  /// Seed a local file and return the localhost HTTP URL for playback.
  /// Also returns the magnet URI via [magnetUri] notifier.
  Future<String?> seed(String filePath) async {
    if (_process == null) {
      final started = await start();
      if (!started) return null;
    }

    _seedCompleter = Completer<String?>();
    isSeeding.value = true;
    progress.value = 1.0;
    lastError.value = null;

    _send({
      'cmd': 'seed',
      'filePath': filePath,
      'trackerUrl': _trackerUrl,
    });

    return _seedCompleter!.future;
  }

  /// Download a torrent from a magnet URI and return the localhost HTTP URL.
  Future<String?> download(String magnet) async {
    if (_process == null) {
      final started = await start();
      if (!started) return null;
    }

    _addCompleter = Completer<String?>();
    isDownloading.value = true;
    progress.value = 0;
    lastError.value = null;

    _send({
      'cmd': 'add',
      'magnetURI': magnet,
      'trackerUrl': _trackerUrl,
    });

    return _addCompleter!.future;
  }

  /// Stop the current torrent.
  void stop() {
    _send({'cmd': 'stop'});
    isSeeding.value = false;
    isDownloading.value = false;
    progress.value = 0;
    serverUrl.value = null;
    magnetUri.value = null;
    torrentName.value = null;
  }

  /// Shut down the engine process.
  Future<void> dispose() async {
    _stopWatchdog();
    _restartCount = _maxRestarts; // Prevent auto-restart during shutdown
    _send({'cmd': 'quit'});
    await _stdoutSub?.cancel();

    await Future.delayed(const Duration(seconds: 2));
    _process?.kill();
    _process = null;

    isReady.dispose();
    isSeeding.dispose();
    isDownloading.dispose();
    progress.dispose();
    downloadSpeed.dispose();
    numPeers.dispose();
    serverUrl.dispose();
    magnetUri.dispose();
    torrentName.dispose();
    lastError.dispose();
  }

  // ─── Watchdog ───

  void _startWatchdog() {
    _stopWatchdog();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_process == null) return;
      _send({'cmd': 'info'});
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  // Private

  Future<void> _initLogging() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/torrent.log');
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      debugPrint('[torrent] Logging to: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[torrent] Failed to init logging: $e');
    }
  }

  void _log(String message) {
    debugPrint(message);
    EngineLogService.addEngineLog(message);
    if (_logFile != null) {
      try {
        final timestamp = DateTime.now().toIso8601String();
        _logFile!.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
      } catch (e) {
        // Ignore write errors
      }
    }
  }

  void _send(Map<String, dynamic> msg) {
    if (_process == null) return;
    final json = jsonEncode(msg);
    _log('[torrent-tx] $json');
    _process!.stdin.writeln(json);
  }

  void _handleMessage(String line) {
    if (line.trim().isEmpty) return;

    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final event = msg['event'] as String?;

      if (event != 'progress') {
        _log('[torrent-rx] $line');
      }

      switch (event) {
        case 'ready':
          isReady.value = true;
          break;

        case 'seeding':
          final url = msg['serverUrl'] as String?;
          final magnet = msg['magnetURI'] as String?;
          serverUrl.value = url;
          magnetUri.value = magnet;
          torrentName.value = msg['name'] as String?;
          isSeeding.value = true;
          _seedCompleter?.complete(url);
          _seedCompleter = null;
          break;

        case 'added':
          final url = msg['serverUrl'] as String?;
          serverUrl.value = url;
          torrentName.value = msg['name'] as String?;
          _addCompleter?.complete(url);
          _addCompleter = null;
          break;

        case 'progress':
          progress.value = (msg['downloaded'] as num?)?.toDouble() ?? 0;
          downloadSpeed.value = (msg['speed'] as num?)?.toInt() ?? 0;
          numPeers.value = (msg['peers'] as num?)?.toInt() ?? 0;
          break;

        case 'done':
          _log('[torrent] Download complete');
          progress.value = 1.0;
          isDownloading.value = false;
          break;

        case 'stopped':
          isSeeding.value = false;
          isDownloading.value = false;
          break;

        case 'error':
          final errorMsg = msg['message'] as String?;
          _log('[torrent] Error: $errorMsg');
          lastError.value = errorMsg;
          _seedCompleter?.complete(null);
          _seedCompleter = null;
          _addCompleter?.complete(null);
          _addCompleter = null;
          break;

        case 'info':
          break;

        default:
          _log('[torrent] Unknown event: $event');
      }
    } catch (e) {
      _log('[torrent] Parse error: $e, line: $line');
    }
  }

  Future<void> _waitForReady() async {
    if (isReady.value) return;

    final completer = Completer<void>();
    void listener() {
      if (isReady.value) {
        isReady.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    isReady.addListener(listener);

    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        isReady.removeListener(listener);
        lastError.value = 'Engine startup timeout';
        completer.complete();
      }
    });

    return completer.future;
  }

  Future<String?> _findEnginePath() async {
    final candidates = [
      'C:/Users/biswa/ShareStream/go/sharestream-engine/sharestream-engine.exe',
      'C:/Users/biswa/ShareStream/go/sharestream-engine/sharestream-engine',
      '${Directory.current.path}/go/sharestream-engine/sharestream-engine.exe',
      '${Directory.current.path}/go/sharestream-engine/sharestream-engine',
      '${File(Platform.resolvedExecutable).parent.path}/sharestream-engine.exe',
      '${File(Platform.resolvedExecutable).parent.path}/sharestream-engine',
    ];

    final exeExt = Platform.isWindows ? '.exe' : '';
    final debugPath = 'C:/Users/biswa/ShareStream/go/sharestream-engine/cmd/sharestream-engine$exeExt';
    
    candidates.add(debugPath);

    candidates.add('sharestream-engine$exeExt');

    candidates.add('${File(Platform.resolvedExecutable).parent.path}/sharestream-engine$exeExt');

    for (final path in candidates) {
      var fullPath = path.replaceAll('\$exeExt', exeExt);
      fullPath = fullPath.replaceAll('\$\{Directory.current.path\}', Directory.current.path);
      fullPath = fullPath.replaceAll('\$\{File(Platform.resolvedExecutable).parent.path\}', 
          File(Platform.resolvedExecutable).parent.path);
      
      if (File(fullPath).existsSync()) {
        _log('[torrent] Found engine at: $fullPath');
        return fullPath;
      }
    }

    // Try looking in PATH
    try {
      final result = await Process.run('where', ['sharestream-engine$exeExt']);
      if (result.exitCode == 0) {
        final foundPath = (result.stdout as String).trim().split('\n').first;
        _log('[torrent] Found engine in PATH: $foundPath');
        return foundPath;
      }
    } catch (e) {
      // Ignore
    }

    _log('[torrent] Engine not found in: $candidates');
    return null;
  }
}
