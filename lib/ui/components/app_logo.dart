import 'package:material_ui/material_ui.dart';

import '../../core/theme/design_tokens.dart';

/// Ikigai brand mark — "still water sunrise".
///
/// Concept: a calm lagoon tile holding a warm paper sun rising over two
/// still-water waves. The sun is the ikigai ("reason for being"), the
/// waves are the chill. Rendered as vector so it stays crisp at any size
/// and in both themes. No image asset required.
class AppLogo extends StatelessWidget {
  const AppLogo({
    this.size = 36,
    this.showWordmark = false,
    this.wordmarkScale = 1.0,
    this.onTap,
    super.key,
  });

  final double size;
  final bool showWordmark;
  final double wordmarkScale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = _LogoMark(size: size);
    if (!showWordmark && onTap == null) return mark;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        if (showWordmark) ...[
          SizedBox(width: Tokens.space8 * wordmarkScale),
          _Wordmark(scale: wordmarkScale),
        ],
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: content,
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ikigai',
          style: TextStyle(
            fontSize: 18 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.0,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 7 * scale,
            vertical: 2.5 * scale,
          ),
          decoration: BoxDecoration(
            color: Tokens.brand,
            borderRadius: BorderRadius.circular(6 * scale),
          ),
          child: Text(
            'ANIME • MANGA',
            style: TextStyle(
              fontSize: 8.5 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1A3A37), Color(0xFF0C1A19)]
              : const [Color(0xFF12705F), Color(0xFF0B4F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.30),
        boxShadow: [
          BoxShadow(
            color: Tokens.brand.withValues(alpha: 0.28),
            blurRadius: size * 0.30,
            offset: Offset(0, size * 0.10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: CustomPaint(painter: _StillWaterPainter()),
    );
  }
}

/// Paints a warm sun rising over two calm wave strokes.
class _StillWaterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sun: warm paper circle, upper third.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.38),
      w * 0.155,
      Paint()..color = const Color(0xFFF4EBD9),
    );
    // Soft sun glow.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.38),
      w * 0.21,
      Paint()..color = const Color(0xFFF4EBD9).withValues(alpha: 0.22),
    );

    // Waves: two rounded still-water strokes in mist teal.
    final wavePaint = Paint()
      ..color = const Color(0xFF8FD4C5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round;
    final wavePaintDim = Paint()
      ..color = const Color(0xFF8FD4C5).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.24, h * 0.66),
      Offset(w * 0.76, h * 0.66),
      wavePaint,
    );
    canvas.drawLine(
      Offset(w * 0.32, h * 0.79),
      Offset(w * 0.68, h * 0.79),
      wavePaintDim,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
