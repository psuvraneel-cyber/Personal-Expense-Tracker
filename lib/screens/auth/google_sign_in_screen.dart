import 'package:pet/core/utils/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/services/firebase_auth_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/screens/auth/guest_username_screen.dart';

/// Google Sign-In screen shown to unauthenticated users.
class GoogleSignInScreen extends StatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  State<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends State<GoogleSignInScreen>
    with SingleTickerProviderStateMixin {
  final _authService = FirebaseAuthService();
  final _syncService = FirestoreSyncService();

  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    // Check platform support on init
    if (!_authService.isGoogleSignInSupported) {
      _errorMessage =
          'Google Sign-In is only supported on Android, iOS, and Web. '
          'Please run the app on Android to use Google authentication.';
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = await _authService.signInWithGoogle();

      if (credential == null) {
        // User cancelled
        setState(() => _isLoading = false);
        return;
      }

      // Fire-and-forget: sync user profile to Firestore in the background.
      // Don't block navigation on a potentially slow network call.
      _syncService
          .ensureUserProfile(
            displayName: credential.user?.displayName ?? '',
            email: credential.user?.email ?? '',
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => AppLogger.debug('ensureUserProfile timed out'),
          )
          .catchError((e) => AppLogger.debug('ensureUserProfile error: $e'));

      if (mounted) {
        // Navigate immediately — splash will detect the auth state
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 72),

                  // App logo + name
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: AppTheme.onboardingGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentPurple.withAlpha(80),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '₹',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'P.E.T',
                    style: GoogleFonts.poppins(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Personal Expense Tracker',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textTertiary,
                    ),
                  ),

                  const Spacer(),

                  // Value props
                  _buildFeatureRow(
                    Icons.cloud_sync_rounded,
                    'Syncs across all your devices',
                    isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureRow(
                    Icons.offline_bolt_rounded,
                    'Works offline — syncs when back online',
                    isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureRow(
                    Icons.lock_rounded,
                    'Your data, protected by Google',
                    isDark,
                  ),

                  const Spacer(),

                  // Error message or platform warning
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _authService.isGoogleSignInSupported
                            ? AppTheme.expenseRed.withAlpha(30)
                            : Colors.orange.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _authService.isGoogleSignInSupported
                              ? AppTheme.expenseRed.withAlpha(100)
                              : Colors.orange.withAlpha(100),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _authService.isGoogleSignInSupported
                                ? Icons.error_outline
                                : Icons.warning_amber_rounded,
                            color: _authService.isGoogleSignInSupported
                                ? AppTheme.expenseRed
                                : Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: _authService.isGoogleSignInSupported
                                    ? AppTheme.expenseRed
                                    : Colors.orange.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Google Sign-In button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed:
                          (_isLoading || !_authService.isGoogleSignInSupported)
                          ? null
                          : _handleGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF2D2D44)
                            : Colors.white,
                        foregroundColor: isDark
                            ? Colors.white
                            : const Color(0xFF3C4043),
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withAlpha(30)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Google "G" logo using coloured icon
                                _GoogleLogo(size: 22),
                                const SizedBox(width: 12),
                                Text(
                                  'Continue with Google',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  // Guest Sign-In button
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const GuestUsernameScreen(),
                                ),
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : AppTheme.primaryDark,
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.3)
                              : AppTheme.primaryDark.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline, size: 22, color: isDark ? Colors.white : AppTheme.primaryDark),
                          const SizedBox(width: 12),
                          Text(
                            'Sign in as Guest',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Skip button for unsupported platforms (Windows/Linux/macOS)
                  if (!_authService.isGoogleSignInSupported) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        // Navigate to home without authentication (local mode only)
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/', (_) => false);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Skip for now (Local mode - No sync)',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.accentPurple,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    'By signing in you agree to our Terms of Service.\nYour financial data is stored securely in your Google account.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentPurple.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accentPurple, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white.withAlpha(200) : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple Google "G" coloured icon rendered via a text widget.
class _GoogleLogo extends StatelessWidget {
  final double size;

  const _GoogleLogo({this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final colors = [
      const Color(0xFF4285F4), // Blue
      const Color(0xFFEA4335), // Red
      const Color(0xFFFBBC05), // Yellow
      const Color(0xFF34A853), // Green
    ];

    final sweeps = [90.0, 90.0, 90.0, 90.0];
    final starts = [-90.0, 0.0, 90.0, 180.0];

    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.13;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.75),
        starts[i] * (3.14159 / 180),
        sweeps[i] * (3.14159 / 180),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
