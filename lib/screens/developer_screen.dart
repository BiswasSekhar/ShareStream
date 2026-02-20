import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/torrent_service.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyLogs(List<String> logs) {
    final text = logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearLogs(int tabIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgDeep,
        title: const Text('Clear Logs', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to clear these logs?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              switch (tabIndex) {
                case 0:
                  EngineLogService.clearEngineLogs();
                  break;
                case 1:
                  EngineLogService.clearSignalLogs();
                  break;
                case 2:
                  LogService.clear();
                  break;
              }
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Clear', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        title: const Text('Developer Options', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [
            Tab(text: 'Engine Logs'),
            Tab(text: 'Signal Logs'),
            Tab(text: 'App Logs'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copy all logs',
            onPressed: () {
              final logs = _getCurrentLogs();
              _copyLogs(logs);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Clear logs',
            onPressed: () => _clearLogs(_tabController.index),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLogList(EngineLogService.engineLogs),
          _buildLogList(EngineLogService.signalLogs),
          _buildLogList(LogService.logs),
        ],
      ),
    );
  }

  List<String> _getCurrentLogs() {
    switch (_tabController.index) {
      case 0:
        return EngineLogService.engineLogs;
      case 1:
        return EngineLogService.signalLogs;
      case 2:
        return LogService.logs;
      default:
        return [];
    }
  }

  Widget _buildLogList(List<String> logs) {
    _scrollToBottom();

    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No logs yet',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            log,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        );
      },
    );
  }
}
