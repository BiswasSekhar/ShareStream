import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../providers/room_provider.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
    final code = _roomCodeController.text.trim();
    if (code.isEmpty) {
      _showError('Enter a room code');
      return;
    }
    if (_isJoining) return;
    setState(() => _isJoining = true);

    final provider = context.read<RoomProvider>();
    provider.setServerUrl(_serverController.text.trim());
    provider.setUserName(_nameController.text.trim());

    final success = await provider.joinRoom(code);

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
      body: Container(
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
                        label: 'Create Room',
                        icon: Icons.add_circle_outline_rounded,
                        isLoading: _isCreating,
                        onPressed: _createRoom,
                      ),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15),
                    const SizedBox(height: AppTheme.spacingLG),

                    // ─── Divider ───
                    _buildDivider(),
                    const SizedBox(height: AppTheme.spacingLG),

                    // ─── Join Room ───
                    GlassTextField(
                      controller: _roomCodeController,
                      hintText: 'Room code',
                      prefixIcon: Icons.tag_rounded,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.go,
                      maxLength: 6,
                      onSubmitted: (_) => _joinRoom(),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.15),
                    const SizedBox(height: AppTheme.spacingMD),
                    SizedBox(
                      width: double.infinity,
                      child: _buildOutlinedButton(
                        label: 'Join Room',
                        icon: Icons.login_rounded,
                        isLoading: _isJoining,
                        onPressed: _joinRoom,
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
          Text(
            'Server URL',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          GlassTextField(
            controller: _serverController,
            hintText: 'Server URL',
            prefixIcon: Icons.dns_outlined,
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }
}
