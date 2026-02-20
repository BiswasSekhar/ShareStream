import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../providers/room_provider.dart';
import '../services/torrent_service.dart';
import 'room_screen.dart';
import 'developer_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? arguments;
  
  const HomeScreen({super.key, this.arguments});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _roomCodeController = TextEditingController();
  final _nameController = TextEditingController(text: 'User');
  final _serverController = TextEditingController(
    text: dotenv.env['SERVER_URL'] ?? 'http://localhost:3001',
  );
  bool _isCreating = false;
  bool _isJoining = false;
  bool _showSettings = false;
  bool _isDetecting = false;
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.arguments != null && widget.arguments!.isNotEmpty) {
        final code = _extractRoomCode(widget.arguments!);
        if (code != null) {
          _roomCodeController.text = code;
        }
      }
      _parseInitialRoute();
      _detectServerUrl();
    });
  }

  bool _hasExplicitServerUrl = false;

  Future<void> _detectServerUrl() async {
    // Skip auto-detection if user already provided an explicit server URL
    if (_hasExplicitServerUrl) {
      debugPrint('[home] Skipping auto-detection, explicit URL already set');
      return;
    }

    setState(() => _isDetecting = true);

    // Ports to try in order
    const ports = [3001, 3002];

    try {
      final torrent = TorrentService();
      await torrent.checkAndStartSignalServer();

      final tunnelUrl = TorrentService.tunnelUrl;
      if (tunnelUrl != null) {
        _serverController.text = tunnelUrl;
        _serverReady = true;
        debugPrint('[home] Using tunnel URL: $tunnelUrl');
        return;
      }

      // Try each port for a live server
      for (final port in ports) {
        try {
          final response = await http.get(
            Uri.parse('http://localhost:$port/api/tunnel'),
          ).timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            // Server is live — use tunnel URL if available, else localhost
            final tunnel = data['tunnel'] as String?;
            if (tunnel != null && tunnel.isNotEmpty) {
              _serverController.text = tunnel;
              debugPrint('[home] Auto-detected tunnel URL on port $port: $tunnel');
            } else {
              _serverController.text = 'http://localhost:$port';
              debugPrint('[home] No tunnel — using localhost:$port directly');
            }
            _serverReady = true;
            return;
          }
        } catch (_) {
          // Try next port
        }
      }

      debugPrint('[home] No server found on ports $ports — showing button anyway');
      _serverReady = true; // Let user try anyway
    } catch (e) {
      debugPrint('[home] Server detection failed: $e');
      _serverReady = true; // Don\'t block user
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  void _parseInitialRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        final code = _extractRoomCode(args);
        if (code != null) {
          _roomCodeController.text = code;
        }
      }
    });
  }

  String? _extractRoomCode(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('/join/')) {
      final parts = lower.split('/join/');
      if (parts.length > 1) {
        final code = parts[1].replaceAll(RegExp(r'[^a-z0-9]'), '').toUpperCase();
        return code.isNotEmpty && code.length <= 6 ? code : null;
      }
    }
    final codeOnly = input.replaceAll(RegExp(r'[^a-z0-9]'), '').toUpperCase();
    return codeOnly.isNotEmpty && codeOnly.length <= 6 ? codeOnly : null;
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _nameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    final provider = context.read<RoomProvider>();
    provider.setServerUrl(_serverController.text.trim());
    provider.setUserName(_nameController.text.trim());

    final code = await provider.createRoom();

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (code.isNotEmpty) {
      Navigator.push(
        context,
        _createRoute(const RoomScreen()),
      );
    } else {
      _showError(provider.error ?? 'Failed to create room');
    }
  }

  Future<void> _joinRoom() async {
    final rawInput = _roomCodeController.text.trim();
    if (rawInput.isEmpty) {
      _showError('Enter a room code or link');
      return;
    }
    
    if (_isJoining) return;
    setState(() => _isJoining = true);

    String codeToUse = rawInput;
    String? explicitServerUrl;
    
    // Check if input contains '#' separator for ServerURL#RoomCode format
    if (rawInput.contains('#')) {
      final parts = rawInput.split('#');
      if (parts.length >= 2) {
        explicitServerUrl = parts[0].trim();
        codeToUse = parts[1].trim().toUpperCase();
        _hasExplicitServerUrl = true;
        // Update UI to reflect the parsed values
        setState(() {
          _serverController.text = explicitServerUrl!;
          _roomCodeController.text = codeToUse;
        });
        debugPrint('[home] Parsed explicit server URL from link: $explicitServerUrl');
      }
    } else if (rawInput.toLowerCase().startsWith('http')) {
      // Handle URL without # - try to extract room code from query params or path
      try {
        final uri = Uri.parse(rawInput);
        // Check for room param in query
        final roomParam = uri.queryParameters['room'];
        if (roomParam != null && roomParam.isNotEmpty) {
          explicitServerUrl = '${uri.scheme}://${uri.host}${uri.port != 0 ? ':${uri.port}' : ''}';
          codeToUse = roomParam.toUpperCase();
          _hasExplicitServerUrl = true;
          setState(() {
            _serverController.text = explicitServerUrl!;
            _roomCodeController.text = codeToUse;
          });
          debugPrint('[home] Parsed server URL from query param: $explicitServerUrl');
        } else {
          // Extract code from /join/CODE path
          final extracted = _extractRoomCode(rawInput);
          if (extracted != null) {
            explicitServerUrl = '${uri.scheme}://${uri.host}${uri.port != 0 ? ':${uri.port}' : ''}';
            codeToUse = extracted;
            _hasExplicitServerUrl = true;
            setState(() {
              _serverController.text = explicitServerUrl!;
              _roomCodeController.text = codeToUse;
            });
            debugPrint('[home] Parsed server URL from path: $explicitServerUrl');
          }
        }
      } catch (_) {
        // Not a valid URL, treat as room code
      }
    } else {
      // Just extract code if it's a simple code or /join/CODE format
      final extracted = _extractRoomCode(rawInput);
      if (extracted != null) {
        codeToUse = extracted;
        _roomCodeController.text = codeToUse;
      }
    }

    final provider = context.read<RoomProvider>();
    final serverUrlToUse = explicitServerUrl ?? _serverController.text.trim();
    debugPrint('[home] Joining with server URL: $serverUrlToUse, room: $codeToUse');
    provider.setServerUrl(serverUrlToUse);
    provider.setUserName(_nameController.text.trim());

    final success = await provider.requestJoin(codeToUse);

    if (!mounted) return;
    setState(() => _isJoining = false);

    if (success) {
      Navigator.push(
        context,
        _createRoute(const RoomScreen()),
      );
    } else {
      _showError(provider.error ?? 'Failed to join room');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isCompact = screenHeight < 700;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.bgDeep, AppTheme.bgPrimary, Color(0xFF0D0D1E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLG,
                    vertical: isCompact ? AppTheme.spacingMD : AppTheme.spacingXL,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ─── Logo & Title ───
                        _buildLogo(),
                        SizedBox(height: isCompact ? 8 : 12),
                        _buildTitle(),
                        SizedBox(height: isCompact ? 4 : 8),
                        _buildSubtitle(),
                        SizedBox(height: isCompact ? 24 : 40),

                        // ─── Name Input ───
                        GlassTextField(
                          controller: _nameController,
                          hintText: 'Your display name',
                          prefixIcon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),
                        const SizedBox(height: AppTheme.spacingMD),

                        // ─── Create Room ───
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            label: _serverReady ? 'Host Room' : 'Starting server...',
                            icon: _serverReady ? Icons.add_circle_outline_rounded : Icons.hourglass_empty,
                            isLoading: _isCreating || !_serverReady,
                            onPressed: _serverReady ? _createRoom : null,
                          ),
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15),
                        const SizedBox(height: AppTheme.spacingLG),

                        // ─── Divider ───
                        _buildDivider(),
                        const SizedBox(height: AppTheme.spacingLG),

                        // ─── Join Room ───
                        GlassTextField(
                          controller: _roomCodeController,
                          hintText: 'Room code or paste link',
                          prefixIcon: Icons.tag_rounded,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _joinRoom(),
                        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.15),
                        const SizedBox(height: AppTheme.spacingMD),
                        SizedBox(
                          width: double.infinity,
                          child: _buildOutlinedButton(
                            label: _serverReady ? 'Join Room' : 'Starting server...',
                            icon: _serverReady ? Icons.login_rounded : Icons.hourglass_empty,
                            isLoading: _isJoining || !_serverReady,
                            onPressed: _serverReady ? () => _joinRoom() : () {},
                          ),
                        ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.15),

                        const SizedBox(height: AppTheme.spacingXL),

                        // ─── Settings Toggle ───
                        _buildSettingsToggle(),

                        if (_showSettings) ...[
                          const SizedBox(height: AppTheme.spacingMD),
                          _buildSettingsPanel(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.developer_mode, color: AppTheme.textMuted),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DeveloperScreen()),
                );
              },
              tooltip: 'Developer Options',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.play_circle_filled_rounded,
        size: 36,
        color: Colors.white,
      ),
    ).animate().scale(
      begin: const Offset(0.5, 0.5),
      end: const Offset(1.0, 1.0),
      curve: Curves.elasticOut,
      duration: 800.ms,
    );
  }

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => AppTheme.accentGradient.createShader(bounds),
      child: Text(
        'ShareStream',
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildSubtitle() {
    return Text(
      'Watch together, instantly.',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppTheme.textSecondary,
          ),
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.border.withValues(alpha: 0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.border.withValues(alpha: 0.5))),
      ],
    ).animate().fadeIn(delay: 350.ms);
  }

  Widget _buildOutlinedButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: AppTheme.primaryLight),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSettingsToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showSettings = !_showSettings),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_outlined,
            size: 16,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            _showSettings ? 'Hide Settings' : 'Server Settings',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
          ),
          const SizedBox(width: 4),
          Icon(
            _showSettings ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: AppTheme.textMuted,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 600.ms);
  }

  Widget _buildSettingsPanel() {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Server URL',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              if (_isDetecting)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GlassTextField(
            controller: _serverController,
            hintText: _isDetecting ? 'Detecting server...' : 'Server URL',
            prefixIcon: Icons.dns_outlined,
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }
}
