import 'package:pet/core/utils/app_logger.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/screens/home/home_screen.dart';
import 'package:pet/screens/auth/google_sign_in_screen.dart';
import 'package:pet/screens/onboarding/onboarding_screen.dart';
import 'package:pet/utils/retry_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/services/firebase_auth_service.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ThemeMode? themeMode;

  const SplashScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
    this.onThemeModeChanged,
    this.themeMode,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──
  late AnimationController _iconController;
  late AnimationController _textController;
  late AnimationController _shimmerController;
  late AnimationController _particleController;
  late AnimationController _progressController;
  late AnimationController _floatController;

  // ── Animations ──
  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _progressValue;

  bool _showOnboarding = false;
  bool _hasNavigated = false;

  /// Auth state: null = still resolving, true = signed in, false = signed out.
  bool? _authResolved;

  /// True once the minimum splash animation sequence has played through.
  /// Navigation is deferred until this is true, so the loading screen always
  /// shows fully before transitioning — regardless of how fast auth resolves.
  bool _splashMinimumShown = false;

  late final StreamSubscription<User?> _authSubscription;

  // Particles for background ambience
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();

    // ── Generate floating particles ──
    final rng = Random(42);
    _particles = List.generate(20, (_) => _Particle.random(rng));

    // ── Auth Gate ──
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final isLoggedIn = FirebaseAuthService().isLoggedIn;
      
      AppLogger.debug(
        '[AUTH] authStateChanges fired → user=${user?.uid ?? "null"} '
        'isLoggedIn=$isLoggedIn '
        'email=${user?.email ?? "none"} '
        '_authResolved=$_authResolved '
        '_hasNavigated=$_hasNavigated',
      );
      if (!mounted) return;

      if (_authResolved == null) {
        AppLogger.debug(
          '[AUTH] First emission — resolved as: ${isLoggedIn ? "SIGNED IN" : "SIGNED OUT"}',
        );
        setState(() => _authResolved = isLoggedIn);

        // Only act immediately if the minimum splash sequence has already
        // played; otherwise _startAnimations() will check _authResolved when
        // it reaches the end and drive the transition itself.
        if (_splashMinimumShown) {
          if (isLoggedIn) {
            _navigateToHome();
          } else {
            setState(() => _showOnboarding = true);
          }
        }
      } else if (_authResolved != isLoggedIn) {
        AppLogger.debug(
          '[AUTH] Auth state changed: ${isLoggedIn ? "SIGNED IN" : "SIGNED OUT"}',
        );
        setState(() => _authResolved = isLoggedIn);
        if (isLoggedIn && !_hasNavigated) {
          _navigateToHome();
        }
      }
    });

    // ── Icon animation ──
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.elasticOut),
    );
    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // ── Text animation ──
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
        );
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    // ── Shimmer / repeating animations ──
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // ── Progress bar animation ──
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (_hasNavigated || !mounted) return;

    _iconController.forward();

    await Future.delayed(const Duration(milliseconds: 800));
    if (_hasNavigated || !mounted) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (_hasNavigated || !mounted) return;
    _shimmerController.repeat();
    _progressController.forward();

    // Wait for the progress bar to complete before transitioning.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (_hasNavigated || !mounted) return;

    // Mark the minimum splash as shown so the auth listener can now act.
    _splashMinimumShown = true;

    // Act on whatever auth resolved to while we were animating.
    if (_authResolved == null) {
      // Auth hasn't resolved yet — keep showing the splash and wait.
      // The auth listener will call back once it fires.
      return;
    } else if (_authResolved == true) {
      _navigateToHome();
    } else {
      setState(() => _showOnboarding = true);
    }
  }

  // ── Navigation (unchanged) ─────────────────────────────────────────────

  void _navigateToHome() async {
    if (_hasNavigated) return;
    _hasNavigated = true;

    try {
      final txnProvider = context.read<TransactionProvider>();
      await retryWithBackoff(
        () => txnProvider.syncFromFirestore().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('syncFromFirestore timed out after 30s');
          },
        ),
        maxAttempts: 3,
        onRetry: (attempt, error) => AppLogger.debug(
          '[Sync] Attempt $attempt failed: $error — retrying…',
        ),
      );
    } catch (e) {
      AppLogger.debug(
        '[Sync] All sync attempts failed, proceeding with local data: $e',
      );
    }

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboardingCompleted') ?? false;

    if (!mounted) return;

    if (!onboardingDone) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              OnboardingScreen(
                onComplete: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => HomeScreen(
                        onThemeToggle: widget.onThemeToggle,
                        isDarkMode: widget.isDarkMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                        themeMode: widget.themeMode,
                      ),
                    ),
                  );
                },
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            themeMode: widget.themeMode,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  void _navigateToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const GoogleSignInScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _iconController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    _particleController.dispose();
    _progressController.dispose();
    _floatController.dispose();
    _authSubscription.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return _buildOnboardingScreen(context);
    }
    return _buildSplashScreen(context);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SPLASH / LOADING SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSplashScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B1E),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1A0F3C),
                  Color(0xFF0D0B1E),
                  Color(0xFF080614),
                ],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // Floating particles
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, _) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _ParticlesPainter(
                particles: _particles,
                progress: _particleController.value,
              ),
            ),
          ),

          // Radial glow behind icon
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentPurple.withValues(alpha: 0.15),
                    AppTheme.accentPurple.withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // Finance icon
                AnimatedBuilder(
                  animation: _iconController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _iconOpacity.value,
                      child: Transform.scale(
                        scale: _iconScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E1548), Color(0xFF140F2E)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentPurple.withValues(alpha: 0.35),
                          blurRadius: 50,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: AppTheme.accentTeal.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: CustomPaint(painter: _FinanceIconPainter()),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // "P.E.T" title with glow
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Text(
                      'P.E.T',
                      style: GoogleFonts.poppins(
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.6),
                            blurRadius: 20,
                          ),
                          Shadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.3),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: Text(
                    'Personal Expense Tracker',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Gradient progress bar
                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) => CustomPaint(
                        size: const Size(double.infinity, 4),
                        painter: _GradientProgressBarPainter(
                          progress: _progressValue.value,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  WELCOME / ONBOARDING LANDING SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOnboardingScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B1E),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0F3C), Color(0xFF0D0B1E), Color(0xFF080614)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Floating particles
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) => CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _ParticlesPainter(
                  particles: _particles,
                  progress: _particleController.value,
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // "P.E.T" branding
                  Text(
                    'P.E.T',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(
                          color: AppTheme.accentPurple.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Dashboard illustration card
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: AnimatedBuilder(
                        animation: _floatController,
                        builder: (context, child) {
                          final float =
                              sin(_floatController.value * 2 * pi) * 4;
                          return Transform.translate(
                            offset: Offset(0, float),
                            child: child,
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2A1761), Color(0xFF1A0F3C)],
                            ),
                            border: Border.all(
                              color: AppTheme.accentPurple.withValues(
                                alpha: 0.2,
                              ),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentPurple.withValues(
                                  alpha: 0.15,
                                ),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: CustomPaint(
                              painter: _DashboardIllustrationPainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Headline text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(
                          'Take control of your\nfinances, effortlessly.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Get Started button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppTheme.purpleGradient,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPurple.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _navigateToAuth,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: Text(
                                'Get Started',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Log in link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: _navigateToAuth,
                              child: Text(
                                'Log in',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PARTICLE DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _Particle {
  final double x; // 0..1
  final double y; // 0..1
  final double radius;
  final double speed; // multiplier
  final Color color;
  final double phase; // offset for sin wave

  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.color,
    required this.phase,
  });

  factory _Particle.random(Random rng) {
    final isPurple = rng.nextBool();
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      radius: 2 + rng.nextDouble() * 6,
      speed: 0.3 + rng.nextDouble() * 0.7,
      color: isPurple
          ? const Color(
              0xFF8B5CF6,
            ).withValues(alpha: 0.15 + rng.nextDouble() * 0.2)
          : const Color(
              0xFF14B8A6,
            ).withValues(alpha: 0.1 + rng.nextDouble() * 0.15),
      phase: rng.nextDouble() * 2 * pi,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Draws floating bokeh-style particles drifting slowly across the screen.
class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlesPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final dx =
          p.x * size.width + sin(progress * 2 * pi * p.speed + p.phase) * 20;
      final dy =
          p.y * size.height +
          cos(progress * 2 * pi * p.speed * 0.7 + p.phase) * 15;
      canvas.drawCircle(
        Offset(dx, dy),
        p.radius,
        Paint()
          ..color = p.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.progress != progress;
}

/// Renders a stylised credit card + ascending bar chart + trend line.
class _FinanceIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Credit card shape ──
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.52, w * 0.38, w * 0.24),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      cardRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4A1A8A), Color(0xFF2D1264)],
        ).createShader(cardRect.outerRect)
        ..style = PaintingStyle.fill,
    );
    // Card chip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.17, h * 0.57, w * 0.06, w * 0.04),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.8),
    );
    // Card stripe
    canvas.drawLine(
      Offset(w * 0.17, h * 0.68),
      Offset(w * 0.42, h * 0.68),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 2,
    );

    // ── Ascending bar chart ──
    final barColors = [
      const Color(0xFF4A1A8A),
      const Color(0xFF6D28D9),
      const Color(0xFF8B5CF6),
      const Color(0xFF14B8A6),
      const Color(0xFF10B981),
    ];
    final barHeights = [0.22, 0.32, 0.28, 0.42, 0.55];
    const barCount = 5;
    final barAreaLeft = w * 0.38;
    final barAreaRight = w * 0.88;
    final barAreaBottom = h * 0.78;
    final barWidth = (barAreaRight - barAreaLeft) / barCount - 4;

    for (var i = 0; i < barCount; i++) {
      final barH = h * barHeights[i];
      final x = barAreaLeft + i * (barWidth + 4);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, barAreaBottom - barH, barWidth, barH),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [barColors[i], barColors[i].withValues(alpha: 0.4)],
          ).createShader(rect.outerRect),
      );
    }

    // ── Upward trend line ──
    final trendPath = Path();
    final trendPoints = [
      Offset(w * 0.15, h * 0.45),
      Offset(w * 0.35, h * 0.38),
      Offset(w * 0.55, h * 0.30),
      Offset(w * 0.72, h * 0.22),
      Offset(w * 0.88, h * 0.13),
    ];
    trendPath.moveTo(trendPoints[0].dx, trendPoints[0].dy);
    for (var i = 1; i < trendPoints.length; i++) {
      final cp1 = Offset(
        (trendPoints[i - 1].dx + trendPoints[i].dx) / 2,
        trendPoints[i - 1].dy,
      );
      final cp2 = Offset(
        (trendPoints[i - 1].dx + trendPoints[i].dx) / 2,
        trendPoints[i].dy,
      );
      trendPath.cubicTo(
        cp1.dx,
        cp1.dy,
        cp2.dx,
        cp2.dy,
        trendPoints[i].dx,
        trendPoints[i].dy,
      );
    }
    canvas.drawPath(
      trendPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF14B8A6), Color(0xFF8B5CF6)],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Glow under trend line
    canvas.drawPath(
      trendPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF14B8A6), Color(0xFF8B5CF6)],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Arrow head at trend end
    final arrowEnd = trendPoints.last;
    final arrowPath = Path()
      ..moveTo(arrowEnd.dx - 8, arrowEnd.dy + 4)
      ..lineTo(arrowEnd.dx, arrowEnd.dy - 4)
      ..lineTo(arrowEnd.dx + 4, arrowEnd.dy + 6);
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFF8B5CF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Horizontal gradient progress bar with purple → teal fill.
class _GradientProgressBarPainter extends CustomPainter {
  final double progress;

  _GradientProgressBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );
    // Track background
    canvas.drawRRect(
      trackRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );

    // Fill
    if (progress > 0) {
      final fillWidth = size.width * progress;
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        Radius.circular(size.height / 2),
      );
      canvas.drawRRect(
        fillRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF14B8A6)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      // Glow at leading edge
      canvas.drawCircle(
        Offset(fillWidth, size.height / 2),
        size.height * 2,
        Paint()
          ..color = const Color(0xFF14B8A6).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_GradientProgressBarPainter old) =>
      old.progress != progress;
}

/// Paints a finance dashboard mockup: donut chart, bar chart, floating cards.
class _DashboardIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Donut chart ──
    final donutCenter = Offset(w * 0.45, h * 0.32);
    final donutRadius = w * 0.20;
    final donutStroke = w * 0.06;

    final segments = [
      (start: -pi / 2, sweep: pi * 1.2, color: const Color(0xFF14B8A6)),
      (
        start: -pi / 2 + pi * 1.2,
        sweep: pi * 0.5,
        color: const Color(0xFF8B5CF6),
      ),
      (
        start: -pi / 2 + pi * 1.7,
        sweep: pi * 0.2,
        color: const Color(0xFFF97316),
      ),
      (
        start: -pi / 2 + pi * 1.9,
        sweep: pi * 0.1,
        color: const Color(0xFF10B981),
      ),
    ];

    for (final seg in segments) {
      canvas.drawArc(
        Rect.fromCircle(center: donutCenter, radius: donutRadius),
        seg.start,
        seg.sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = donutStroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Donut glow
    canvas.drawCircle(
      donutCenter,
      donutRadius + 10,
      Paint()
        ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Center text — "Balance" label
    final balanceLabelPainter = TextPainter(
      text: TextSpan(
        text: 'Balance',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    balanceLabelPainter.paint(
      canvas,
      Offset(
        donutCenter.dx - balanceLabelPainter.width / 2,
        donutCenter.dy - 12,
      ),
    );

    // Center text — "₹42k"
    final balanceValuePainter = TextPainter(
      text: const TextSpan(
        text: '₹42k',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    balanceValuePainter.paint(
      canvas,
      Offset(
        donutCenter.dx - balanceValuePainter.width / 2,
        donutCenter.dy + 2,
      ),
    );

    // Percentage labels
    _drawBadge(
      canvas,
      Offset(w * 0.72, h * 0.18),
      '60%',
      const Color(0xFF14B8A6),
    );
    _drawBadge(
      canvas,
      Offset(w * 0.72, h * 0.42),
      '25%',
      const Color(0xFF8B5CF6),
    );

    // ── Bar chart ──
    final barData = [0.35, 0.45, 0.55, 0.7, 0.85, 0.65, 0.9];
    final barLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final barAreaLeft = w * 0.12;
    final barAreaRight = w * 0.88;
    final barAreaTop = h * 0.60;
    final barAreaBottom = h * 0.82;
    final barMaxH = barAreaBottom - barAreaTop;
    final totalBarWidth = barAreaRight - barAreaLeft;
    final barWidth = totalBarWidth / barData.length - 6;

    for (var i = 0; i < barData.length; i++) {
      final barH = barMaxH * barData[i];
      final x = barAreaLeft + i * (barWidth + 6);
      final y = barAreaBottom - barH;

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(
            const Color(0xFF8B5CF6),
            const Color(0xFF14B8A6),
            i / (barData.length - 1),
          )!,
          Color.lerp(
            const Color(0xFF8B5CF6),
            const Color(0xFF14B8A6),
            i / (barData.length - 1),
          )!.withValues(alpha: 0.3),
        ],
      );

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barH),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = gradient.createShader(Rect.fromLTWH(x, y, barWidth, barH)),
      );

      // Day label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: barLabels[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(x + barWidth / 2 - labelPainter.width / 2, barAreaBottom + 4),
      );
    }

    // ── Floating credit cards (glassmorphic) ──
    _drawGlassCard(
      canvas,
      Offset(w * 0.06, h * 0.68),
      w * 0.22,
      w * 0.14,
      -0.12,
      const Color(0xFF8B5CF6),
    );
    _drawGlassCard(
      canvas,
      Offset(w * 0.68, h * 0.08),
      w * 0.26,
      w * 0.16,
      0.15,
      const Color(0xFF14B8A6),
    );

    // ── Floating ₹ symbols ──
    _drawCurrencySymbol(
      canvas,
      Offset(w * 0.15, h * 0.15),
      14,
      const Color(0xFF8B5CF6).withValues(alpha: 0.3),
    );
    _drawCurrencySymbol(
      canvas,
      Offset(w * 0.85, h * 0.55),
      11,
      const Color(0xFF14B8A6).withValues(alpha: 0.25),
    );
    _drawCurrencySymbol(
      canvas,
      Offset(w * 0.08, h * 0.50),
      9,
      const Color(0xFFF97316).withValues(alpha: 0.2),
    );

    // ── Sparkle dots ──
    _drawSparkle(
      canvas,
      Offset(w * 0.90, h * 0.30),
      3,
      const Color(0xFF14B8A6).withValues(alpha: 0.5),
    );
    _drawSparkle(
      canvas,
      Offset(w * 0.20, h * 0.90),
      2.5,
      const Color(0xFF8B5CF6).withValues(alpha: 0.4),
    );
    _drawSparkle(
      canvas,
      Offset(w * 0.50, h * 0.92),
      2,
      const Color(0xFF10B981).withValues(alpha: 0.3),
    );
    _drawSparkle(
      canvas,
      Offset(w * 0.78, h * 0.88),
      2.5,
      const Color(0xFFF97316).withValues(alpha: 0.3),
    );
  }

  void _drawBadge(Canvas canvas, Offset pos, String text, Color color) {
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: 44, height: 22),
      const Radius.circular(11),
    );
    canvas.drawRRect(bgRect, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  void _drawGlassCard(
    Canvas canvas,
    Offset pos,
    double w,
    double h,
    double angle,
    Color tint,
  ) {
    canvas.save();
    canvas.translate(pos.dx + w / 2, pos.dy + h / 2);
    canvas.rotate(angle);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(8),
    );
    // Fill
    canvas.drawRRect(rect, Paint()..color = tint.withValues(alpha: 0.08));
    // Border
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Chip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * 0.3, -h * 0.15, w * 0.15, h * 0.22),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.5),
    );
    // Stripe
    canvas.drawLine(
      Offset(-w * 0.3, h * 0.2),
      Offset(w * 0.3, h * 0.2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  void _drawCurrencySymbol(
    Canvas canvas,
    Offset pos,
    double fontSize,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  void _drawSparkle(Canvas canvas, Offset pos, double radius, Color color) {
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
