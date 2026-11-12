import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/profile_banner.dart';

/// Renders the profile header banner: the AniList banner image or one of the
/// app's animated, anime-inspired styles.
///
/// This is a website-only feature — AniList has no banner picker. It fills its
/// parent, so callers size it (usually with a [SizedBox] or [AspectRatio]).
class ProfileBannerView extends StatelessWidget {
  const ProfileBannerView({
    required this.preset,
    this.fallbackImageUrl,
    super.key,
  });

  final BannerPreset preset;

  /// The signed-in user's AniList banner, used by [BannerPreset.auto].
  final String? fallbackImageUrl;

  @override
  Widget build(BuildContext context) {
    final url = preset == BannerPreset.auto ? _clean(fallbackImageUrl) : null;
    if (url != null) {
      return _ImageBanner(
        url: url,
        fallback: _AnimatedBanner(builder: _aurora),
      );
    }
    return switch (preset) {
      BannerPreset.sakura => _AnimatedBanner(builder: _sakura),
      BannerPreset.sunset => _AnimatedBanner(builder: _sunset),
      BannerPreset.ocean => _AnimatedBanner(builder: _ocean),
      BannerPreset.neon => _AnimatedBanner(builder: _neon),
      BannerPreset.starfield => _AnimatedBanner(builder: _starfield),
      BannerPreset.gradient => _AnimatedBanner(builder: _gradient),
      BannerPreset.grid => _AnimatedBanner(builder: _grid),
      // Aurora is both the explicit choice and the graceful fallback.
      BannerPreset.aurora ||
      BannerPreset.auto => _AnimatedBanner(builder: _aurora),
    };
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

/// Three drifting radial glows over a deep lagoon base — "komorebi aurora".
Widget _aurora(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  final angle = t * 2 * math.pi;
  return Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xFF06201E)),
      _glow(
        Alignment(
          -0.7 + 0.5 * math.sin(angle),
          -0.6 + 0.4 * math.cos(angle),
        ),
        scheme.primary.withValues(alpha: 0.85),
        1.15,
      ),
      _glow(
        Alignment(
          0.9 - 0.4 * math.cos(angle * 1.3),
          0.8 - 0.3 * math.sin(angle * 0.9),
        ),
        scheme.tertiary.withValues(alpha: 0.55),
        1.0,
      ),
      _glow(
        Alignment(-0.3 + 0.6 * math.sin(angle * 0.7 + 1), 1.1),
        Tokens.sun.withValues(alpha: 0.4),
        0.9,
      ),
    ],
  );
}

Widget _glow(Alignment center, Color color, double radius) {
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: center,
        radius: radius,
        colors: [color, color.withValues(alpha: 0)],
      ),
    ),
  );
}

/// A brand-colour sweep that flows by rotating its gradient axis.
Widget _gradient(BuildContext context, double t) {
  final angle = t * 2 * math.pi;
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment(-1 + 2 * math.sin(angle), -1),
        end: Alignment(1, 1 - 2 * math.cos(angle)),
        colors: const [
          Color(0xFF5EEAD4),
          Color(0xFF0E7C6B),
          Color(0xFF0B4F46),
          Color(0xFFB98A2E),
          Color(0xFFE9C46A),
        ],
      ),
    ),
  );
}

/// Cherry-blossom petals drifting across a dusky plum sky.
Widget _sakura(BuildContext context, double t) {
  return CustomPaint(
    size: Size.infinite,
    painter: _SakuraPainter(t),
  );
}

/// A warm anime sky: violet fading into coral and gold with a low sun glow.
Widget _sunset(BuildContext context, double t) {
  final angle = t * 2 * math.pi;
  return Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1, -1 + 0.08 * math.sin(angle)),
            end: Alignment(1, 1),
            colors: const [
              Color(0xFF2B1B4A),
              Color(0xFF6B2C63),
              Color(0xFFC2464A),
              Color(0xFFE8824D),
              Color(0xFFF7C46B),
            ],
          ),
        ),
      ),
      _glow(
        Alignment(0.15, 0.95),
        const Color(0xFFFFE3A6).withValues(alpha: 0.85),
        0.85,
      ),
      _glow(
        Alignment(-0.65, 0.35),
        const Color(0xFFB05A8E).withValues(alpha: 0.35),
        1.25,
      ),
    ],
  );
}

/// Deep-sea waves with rising bubbles.
Widget _ocean(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  return CustomPaint(
    size: Size.infinite,
    painter: _OceanPainter(t, scheme.primary),
  );
}

/// A night-city skyline glowing with neon light and a travelling scanline.
Widget _neon(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  return CustomPaint(
    size: Size.infinite,
    painter: _NeonPainter(t, scheme.primary, scheme.tertiary),
  );
}

/// Twinkling, slowly drifting stars.
Widget _starfield(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  return CustomPaint(
    size: Size.infinite,
    painter: _StarfieldPainter(t, scheme.secondary),
  );
}

/// Faint grid with a highlight band travelling across it.
Widget _grid(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  return CustomPaint(
    size: Size.infinite,
    painter: _GridPainter(
      t,
      line: Colors.white.withValues(alpha: 0.07),
      glow: scheme.primary,
      background: const Color(0xFF0B1F1C),
    ),
  );
}

// ---------------------------------------------------------------------------
// Animated host
// ---------------------------------------------------------------------------

/// Drives a slow looping clock and hands it to [builder]. Motion is disabled
/// when the platform asks for reduced animation, leaving a still frame.
class _AnimatedBanner extends StatefulWidget {
  const _AnimatedBanner({required this.builder});

  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_AnimatedBanner> createState() => _AnimatedBannerState();
}

class _AnimatedBannerState extends State<_AnimatedBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => widget.builder(context, _controller.value),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image banner (AniList "Auto" preset)
// ---------------------------------------------------------------------------

class _ImageBanner extends StatelessWidget {
  const _ImageBanner({required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surfaceContainerHigh),
        Image.network(
          url,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => fallback,
        ),
        // Scrim so overlaid avatar / name / buttons stay legible.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.42),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Deterministic pseudo-random in [0, 1) — no state, stable across repaints.
double _unit(int i, int salt) =>
    ((i * 2654435761 + salt * 40503) % 1000003) / 1000003.0;

class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter(this.t, this.tint);

  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF071626),
    );
    final paint = Paint();
    for (var i = 0; i < 110; i++) {
      final x = _unit(i, 1) * size.width;
      final speed = 0.04 + _unit(i, 2) * 0.14;
      final y = ((_unit(i, 3) + t * speed) % 1.0) * size.height;
      final radius = 0.6 + _unit(i, 4) * 1.9;
      final twinkle =
          0.35 +
          0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + _unit(i, 5) * 12));
      paint.color = Color.lerp(
        Colors.white,
        tint,
        _unit(i, 6),
      )!.withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.tint != tint;
}

class _GridPainter extends CustomPainter {
  const _GridPainter(
    this.t, {
    required this.line,
    required this.glow,
    required this.background,
  });

  final double t;
  final Color line;
  final Color glow;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    const step = 28.0;
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Highlight band sweeping left -> right.
    final bandWidth = size.width * 0.38;
    final left = t * (size.width + bandWidth) - bandWidth;
    final band = Rect.fromLTWH(left, 0, bandWidth, size.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        glow.withValues(alpha: 0),
        glow.withValues(alpha: 0.32),
        glow.withValues(alpha: 0),
      ],
    ).createShader(band);
    canvas.drawRect(band, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.line != line ||
      oldDelegate.glow != glow ||
      oldDelegate.background != background;
}

class _SakuraPainter extends CustomPainter {
  const _SakuraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF241324), Color(0xFF3B1F2E)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    // A soft far bloom so the sky is not flat.
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      size.shortestSide * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB7C5).withValues(alpha: 0.20),
            const Color(0xFFFFB7C5).withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.72, size.height * 0.28),
            radius: size.shortestSide * 0.55,
          ),
        ),
    );

    final paint = Paint();
    for (var i = 0; i < 48; i++) {
      final speed = 0.05 + _unit(i, 2) * 0.10;
      final y =
          ((_unit(i, 3) + t * speed) % 1.0) * (size.height + 40) - 20;
      final sway =
          math.sin(t * 2 * math.pi * (0.4 + _unit(i, 4)) + _unit(i, 5) * 9);
      final x = _unit(i, 1) * size.width + sway * 26;
      final scale = 0.55 + _unit(i, 6) * 1.1;
      final rotation =
          t * 2 * math.pi * (0.5 + _unit(i, 7)) + _unit(i, 8) * 6;
      paint.color =
          Color.lerp(
            const Color(0xFFFFC2D1),
            const Color(0xFFFF8FA3),
            _unit(i, 9),
          )!.withValues(alpha: 0.55 + _unit(i, 10) * 0.35);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 10 * scale,
          height: 5.5 * scale,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _OceanPainter extends CustomPainter {
  const _OceanPainter(this.t, this.tint);

  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF061C2A), Color(0xFF0A3B4A)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    for (var layer = 0; layer < 3; layer++) {
      final phase =
          t * 2 * math.pi * (0.5 + layer * 0.35) + layer * 1.7;
      final amplitude = 8.0 + layer * 6;
      final baseline = size.height * (0.42 + layer * 0.17);
      final path = Path()..moveTo(0, baseline);
      for (var x = 0.0; x <= size.width; x += 8) {
        final y =
            baseline +
            math.sin((x / size.width) * math.pi * 3 + phase) * amplitude;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF0E7C6B),
            tint,
            layer / 3,
          )!.withValues(alpha: 0.24 + layer * 0.14),
      );
    }

    final bubble = Paint();
    for (var i = 0; i < 26; i++) {
      final speed = 0.05 + _unit(i, 2) * 0.10;
      final y = size.height - ((_unit(i, 3) + t * speed) % 1.0) * size.height;
      final x =
          _unit(i, 1) * size.width +
          math.sin(t * 2 * math.pi + _unit(i, 4) * 6) * 6;
      bubble.color = Colors.white.withValues(alpha: 0.10 + _unit(i, 5) * 0.18);
      canvas.drawCircle(Offset(x, y), 1.0 + _unit(i, 6) * 2.4, bubble);
    }
  }

  @override
  bool shouldRepaint(covariant _OceanPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.tint != tint;
}

class _NeonPainter extends CustomPainter {
  const _NeonPainter(this.t, this.glowA, this.glowB);

  final double t;
  final Color glowA;
  final Color glowB;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0A16),
    );

    // Horizon haze.
    final horizon = size.height * 0.72;
    final hazeRect = Rect.fromLTRB(0, horizon - 44, size.width, horizon + 12);
    canvas.drawRect(
      hazeRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            glowA.withValues(alpha: 0),
            glowA.withValues(alpha: 0.24),
            glowB.withValues(alpha: 0.10),
          ],
        ).createShader(hazeRect),
    );

    // Skyline with neon edges.
    final body = Paint()..color = const Color(0xFF141428);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const count = 16;
    final columnWidth = size.width / count;
    for (var i = 0; i < count; i++) {
      final height = (0.14 + _unit(i, 1) * 0.36) * size.height;
      final rect = Rect.fromLTWH(
        i * columnWidth + 2,
        size.height - height,
        columnWidth - 4,
        height,
      );
      canvas.drawRect(rect, body);
      edge.color = (i.isEven ? glowA : glowB).withValues(alpha: 0.32);
      canvas.drawRect(rect, edge);
    }

    // Travelling scanline.
    final sweepRect = Rect.fromLTWH(
      (t % 1.0) * size.width - 34,
      0,
      68,
      size.height,
    );
    canvas.drawRect(
      sweepRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            glowB.withValues(alpha: 0),
            glowB.withValues(alpha: 0.16),
            glowB.withValues(alpha: 0),
          ],
        ).createShader(sweepRect),
    );
  }

  @override
  bool shouldRepaint(covariant _NeonPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.glowA != glowA ||
      oldDelegate.glowB != glowB;
}
