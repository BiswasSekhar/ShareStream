import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Manages a webtorrent-hybrid Node.js subprocess for P2P streaming.
///
/// Desktop only (Windows/macOS). Communicates via stdin/stdout JSON.
/// The sidecar seeds & downloads torrents, and creates a localhost HTTP
/// server so media_kit can play via Range requests.
class TorrentService {
  Process? _process;
  StreamSubscription? _stdoutSub;

  // State
  final ValueNotifier<bool> isReady = ValueNotifier(false);
  final ValueNotifier<bool> isSeeding = ValueNotifier(false);
  final ValueNotifier<bool> isDownloading = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0); // 0.0 – 1.0
  final ValueNotifier<int> downloadSpeed = ValueNotifier(0); // bytes/sec
  final ValueNotifier<int> numPeers = ValueNotifier(0);
  final ValueNotifier<String?> serverUrl = ValueNotifier(null);
  final ValueNotifier<String?> magnetUri = ValueNotifier(null);
  final ValueNotifier<String?> torrentName = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  // Completers for awaitable commands
  Completer<String?>? _seedCompleter;
  Completer<String?>? _addCompleter;

  String get _trackerUrl {
    final url = dotenv.env['SERVER_URL'] ?? 'http://localhost:3001';
    return '${url.replaceFirst(RegExp(r'^http'), 'ws')}/';
  }

  /// Start the Node.js sidecar process.
  Future<bool> start() async {
    if (_process != null) return true;

    try {
      // Locate the torrent-bridge script
      final bridgePath = _findBridgePath();
      if (bridgePath == null) {
        lastError.value = 'Could not find torrent-bridge/index.js';
        return false;
      }

      debugPrint('[torrent] Starting sidecar: node $bridgePath');

      _process = await Process.start('node', [bridgePath], runInShell: true);

      // Listen to stdout for JSON messages
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleMessage);

      // Log stderr
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('[torrent-stderr] $line');
      });

      _process!.exitCode.then((code) {
        debugPrint('[torrent] Sidecar exited with code: $code');
        _process = null;
        isReady.value = false;
      });

      // Wait for ready event
      await _waitForReady();
      return isReady.value;
    } catch (e) {
      debugPrint('[torrent] Failed to start sidecar: $e');
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
    progress.value = 1.0; // Host has the full file
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

  /// Shut down the sidecar process.
  Future<void> dispose() async {
    _send({'cmd': 'quit'});
    await _stdoutSub?.cancel();

    // Give it a moment to clean up, then force kill
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

  // ─── Private ──────────────────────────────────────────────

  void _send(Map<String, dynamic> msg) {
    if (_process == null) return;
    final json = jsonEncode(msg);
    _process!.stdin.writeln(json);
  }

  void _handleMessage(String line) {
    if (line.trim().isEmpty) return;

    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final event = msg['event'] as String?;

      switch (event) {
        case 'ready':
          debugPrint('[torrent] Sidecar ready');
          isReady.value = true;
          break;

        case 'seeding':
          final url = msg['serverUrl'] as String?;
          final magnet = msg['magnetURI'] as String?;
          debugPrint('[torrent] Seeding: $url');
          serverUrl.value = url;
          magnetUri.value = magnet;
          torrentName.value = msg['name'] as String?;
          isSeeding.value = true;
          _seedCompleter?.complete(url);
          _seedCompleter = null;
          break;

        case 'added':
          final url = msg['serverUrl'] as String?;
          debugPrint('[torrent] Added torrent, server: $url');
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
          debugPrint('[torrent] Download complete');
          progress.value = 1.0;
          isDownloading.value = false;
          break;

        case 'stopped':
          debugPrint('[torrent] Stopped');
          isSeeding.value = false;
          isDownloading.value = false;
          break;

        case 'error':
          final errorMsg = msg['message'] as String?;
          debugPrint('[torrent] Error: $errorMsg');
          lastError.value = errorMsg;
          _seedCompleter?.complete(null);
          _seedCompleter = null;
          _addCompleter?.complete(null);
          _addCompleter = null;
          break;

        case 'info':
          debugPrint('[torrent] Info: $msg');
          break;

        default:
          debugPrint('[torrent] Unknown event: $event');
      }
    } catch (e) {
      debugPrint('[torrent] Parse error: $e, line: $line');
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

    // Timeout after 10 seconds
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        isReady.removeListener(listener);
        lastError.value = 'Sidecar startup timeout';
        completer.complete();
      }
    });

    return completer.future;
  }

  String? _findBridgePath() {
    // Try multiple possible locations
    final candidates = [
      // Development: relative to project
      '${Directory.current.path}/assets/torrent-bridge/index.js',
      // Packaged: next to executable
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/torrent-bridge/index.js',
      // Windows packaged
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/torrent-bridge/index.js',
      // macOS packaged
      '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/App.framework/Resources/flutter_assets/assets/torrent-bridge/index.js',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // Fallback: try current directory
    final fallback = 'assets/torrent-bridge/index.js';
    if (File(fallback).existsSync()) return fallback;

    debugPrint('[torrent] Bridge not found in: $candidates');
    return null;
  }
}
