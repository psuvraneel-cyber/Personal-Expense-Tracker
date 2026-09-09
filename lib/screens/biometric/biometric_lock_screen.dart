import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pet/services/biometric_service.dart';

/// Premium biometric lock screen with 3D visuals, glassmorphism,
/// animated particles, and glowing fingerprint.
class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const BiometricLockScreen({super.key, required this.onUnlocked});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with TickerProviderStateMixin {
  bool _authenticating = false;
  String? _errorMessage;

  // ---------- Animation controllers ----------
  late final AnimationController _rippleController;
  late final AnimationController _glowController;
  late final AnimationController _particleController;
  late final AnimationController _breatheController;
  late final AnimationController _errorShakeController;

  late final Animation<double> _ripple;
  late final Animation<double> _glow;
  late final Animation<double> _breathe;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();

    // Concentric ripple rings
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _ripple = CurvedAnimation(parent: _rippleController, curve: Curves.easeOut);

    // Glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Floating particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Breathing scale on fingerprint
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _breathe = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Error shake
    _errorShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shake = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _errorShakeController, curve: Curves.elasticIn),
    );

    // Auto-prompt on first display
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    _breatheController.dispose();
    _errorShakeController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _errorMessage = null;
    });

    final success = await BiometricService.instance.authenticate(
      reason: 'Authenticate to unlock P.E.T',
    );

    if (!mounted) return;

    if (success) {
      widget.onUnlocked();
    } else {
      _errorShakeController.forward(from: 0);
      setState(() {
        _authenticating = false;
        _errorMessage = 'Authentication failed. Tap to try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ──── Deep gradient background ────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D0B1E),
                  Color(0xFF1A0F3C),
                  Color(0xFF0D0B1E),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ──── Mesh grid overlay for depth ────
          CustomPaint(size: size, painter: _MeshGridPainter()),

          // ──── Floating particles ────
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _ParticlePainter(
                progress: _particleController.value,
                screenSize: size,
              ),
            ),
          ),

          // ──── Main content ────
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ──── App logo with halo ────
                  _buildLogoWithHalo(),
                  const SizedBox(height: 20),

                  // ──── Title ────
                  Text(
                    'P.E.T is Locked',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: const Color(0xFF8B5CF6).withAlpha(120),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Authenticate to access your financial data',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withAlpha(100),
                      letterSpacing: 0.2,
                    ),
                  ),

                  const Spacer(),

                  // ──── Glassmorphism card + fingerprint ────
                  _buildGlassFingerprint(),

                  const SizedBox(height: 24),

                  // ──── Error message ────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _errorMessage != null
                        ? AnimatedBuilder(
                            animation: _shake,
                            builder: (context, child) {
                              final offset = sin(_shake.value * pi * 4) * 8;
                              return Transform.translate(
                                offset: Offset(offset, 0),
                                child: child,
                              );
                            },
                            child: Container(
                              key: const ValueKey('error'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4757).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFF4757).withAlpha(60),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: const Color(0xFFFF6B6B),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B6B),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox(height: 40, key: ValueKey('empty')),
                  ),

                  const Spacer(),

                  // ──── Unlock button ────
                  _buildUnlockButton(),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Logo with soft purple halo glow
  Widget _buildLogoWithHalo() {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF8B5CF6).withAlpha((40 * _glow.value).toInt()),
                const Color(0xFF8B5CF6).withAlpha((15 * _glow.value).toInt()),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF8B5CF6,
                ).withAlpha((50 * _glow.value).toInt()),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1B33).withAlpha(200),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withAlpha(60),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.pets, size: 36, color: Color(0xFF8B5CF6)),
          ),
        );
      },
    );
  }

  /// Glassmorphism card with glowing fingerprint + concentric ripple rings
  Widget _buildGlassFingerprint() {
    return GestureDetector(
      onTap: _authenticating ? null : _authenticate,
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ripple rings
            ...List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _ripple,
                builder: (context, _) {
                  final delay = i * 0.33;
                  final value = ((_ripple.value + delay) % 1.0);
                  final scale = 0.6 + value * 0.8;
                  final opacity = (1.0 - value).clamp(0.0, 0.6);
                  final hasError = _errorMessage != null;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (hasError
                                  ? const Color(0xFFFF4757)
                                  : const Color(0xFF8B5CF6))
                              .withAlpha((opacity * 255).toInt()),
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              );
            }),

            // Glassmorphism card
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                final hasError = _errorMessage != null;
                final glowColor = hasError
                    ? const Color(0xFFFF4757)
                    : const Color(0xFF8B5CF6);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        color: Colors.white.withAlpha(8),
                        border: Border.all(
                          color: glowColor.withAlpha(
                            (60 * _glow.value).toInt(),
                          ),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withAlpha(
                              (30 * _glow.value).toInt(),
                            ),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF14B8A6,
                            ).withAlpha((15 * _glow.value).toInt()),
                            blurRadius: 40,
                            spreadRadius: -5,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Fingerprint icon with 3D depth
            AnimatedBuilder(
              animation: _breathe,
              builder: (context, child) {
                return Transform.scale(scale: _breathe.value, child: child);
              },
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8B5CF6), Color(0xFF14B8A6)],
                ).createShader(bounds),
                child: Icon(Icons.fingerprint, size: 72, color: Colors.white),
              ),
            ),

            // Authenticating spinner overlay
            if (_authenticating)
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF8B5CF6).withAlpha(150),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Premium gradient unlock button
  Widget _buildUnlockButton() {
    return GestureDetector(
      onTap: _authenticating ? null : _authenticate,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, _) {
          return Container(
            width: 220,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: _authenticating
                    ? [
                        const Color(0xFF8B5CF6).withAlpha(80),
                        const Color(0xFF14B8A6).withAlpha(80),
                      ]
                    : const [
                        Color(0xFF8B5CF6),
                        Color(0xFF6D28D9),
                        Color(0xFF14B8A6),
                      ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF8B5CF6,
                  ).withAlpha((80 * _glow.value).toInt()),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: const Color(
                    0xFF14B8A6,
                  ).withAlpha((40 * _glow.value).toInt()),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_authenticating)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  const Icon(
                    Icons.lock_open_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Text(
                  _authenticating ? 'Authenticating...' : 'Unlock',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Custom painters
// ═══════════════════════════════════════════════════════════════════

/// Subtle mesh grid for background depth
class _MeshGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8B5CF6).withAlpha(8)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Floating luminous particles
class _ParticlePainter extends CustomPainter {
  final double progress;
  final Size screenSize;
  static final List<_Particle> _particles = _generateParticles(30);

  _ParticlePainter({required this.progress, required this.screenSize});

  static List<_Particle> _generateParticles(int count) {
    final rng = Random(42);
    return List.generate(count, (_) {
      return _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 1.0 + rng.nextDouble() * 2.5,
        speed: 0.2 + rng.nextDouble() * 0.8,
        phase: rng.nextDouble() * 2 * pi,
        isPurple: rng.nextBool(),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress * p.speed + p.phase / (2 * pi)) % 1.0;

      // Gentle floating path
      final x = p.x * size.width + sin(t * 2 * pi + p.phase) * 30;
      final y = (p.y * size.height + t * size.height * 0.3) % size.height;

      // Pulsing alpha
      final alpha = (sin(t * 2 * pi) * 0.5 + 0.5) * 0.6;

      final baseColor =
          p.isPurple ? const Color(0xFF8B5CF6) : const Color(0xFF14B8A6);

      final paint = Paint()
        ..color = baseColor.withAlpha((alpha * 255).toInt())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Particle {
  final double x, y, radius, speed, phase;
  final bool isPurple;

  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.isPurple,
  });
}
