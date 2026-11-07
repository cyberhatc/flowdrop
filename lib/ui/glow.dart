import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Deep gradient background with two soft neon blobs.
class NeonBackground extends StatelessWidget {
  const NeonBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF04060C), Color(0xFF070B16), Color(0xFF04060C)]
              : const [Color(0xFFF7F9FF), Color(0xFFEDF2FF), Color(0xFFF7F9FF)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -120,
            child: _Blob(color: scheme.primary, size: 340, opacity: 0.18),
          ),
          Positioned(
            bottom: -160,
            right: -140,
            child: _Blob(color: scheme.secondary, size: 380, opacity: 0.14),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card with a gradient hairline border and a faint accent glow.
class GlowCard extends StatelessWidget {
  const GlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.accent,
    this.radius = 22,
    this.glow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = accent ?? scheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final border = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tint.withValues(alpha: isDark ? 0.55 : 0.35),
        Colors.white.withValues(alpha: isDark ? 0.06 : 0.0),
        scheme.secondary.withValues(alpha: isDark ? 0.30 : 0.20),
      ],
    );

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.055),
                  Colors.white.withValues(alpha: 0.02),
                ]
              : [Colors.white, Colors.white.withValues(alpha: 0.9)],
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: tint.withValues(alpha: isDark ? 0.14 : 0.08),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tint.withValues(alpha: isDark ? 0.18 : 0.14)),
        gradient: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius - 1),
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius - 1),
                child: content,
              ),
      ),
    );
  }
}

/// Solid accent button with a bloom shadow.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
    this.tone = GlowTone.primary,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;
  final GlowTone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (tone) {
      GlowTone.primary => scheme.primary,
      GlowTone.secondary => scheme.secondary,
      GlowTone.ghost => Colors.transparent,
    };
    final foreground = tone == GlowTone.ghost || !isDark
        ? scheme.onSurface
        : const Color(0xFF04060C);

    final button = FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : (icon == null ? null : Icon(icon, size: 18)),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground,
        disabledBackgroundColor: color.withValues(alpha: 0.30),
        disabledForegroundColor: foreground.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: tone == GlowTone.ghost
                ? scheme.onSurface.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
        ),
        elevation: 0,
        shadowColor: color.withValues(alpha: 0.6),
      ),
    );

    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: tone == GlowTone.ghost
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: button,
    );

    return expanded
        ? SizedBox(width: double.infinity, child: shadowed)
        : shadowed;
  }
}

enum GlowTone { primary, secondary, ghost }

/// Small tinted icon inside a rounded square.
class GlowIcon extends StatelessWidget {
  const GlowIcon({super.key, required this.icon, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: tint.withValues(alpha: 0.12),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// Pill with a coloured dot and a short label.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: color)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 8),
                ],
              ),
            ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Headline with an accent gradient fill.
class GradientHeadline extends StatelessWidget {
  const GradientHeadline(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base =
        style ??
        Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: [scheme.primary, scheme.secondary])
              .createShader(bounds),
      child: Text(text, style: base, textAlign: textAlign),
    );
  }
}

/// Animated pulsing dot used for "live" indicators.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.size + 6,
          height: widget.size + 6,
          alignment: Alignment.center,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.45 + 0.55 * t),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4 + 0.4 * t),
                  blurRadius: 4 + 8 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Rotating radar sweep drawn behind the peer bubbles.
class RadarSweep extends StatefulWidget {
  const RadarSweep({super.key, required this.color, this.size = 320});

  final Color color;
  final double size;

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _RadarPainter(
            color: widget.color,
            angle: _controller.value * math.pi * 2,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.color,
    required this.angle,
    required this.isDark,
  });

  final Color color;
  final double angle;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      ring.color = color.withValues(alpha: isDark ? 0.18 / i : 0.14 / i);
      canvas.drawCircle(center, radius * i / 3, ring);
    }

    final cross = Paint()
      ..color = color.withValues(alpha: isDark ? 0.08 : 0.06)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      cross,
    );

    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + math.pi / 2,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: isDark ? 0.22 : 0.12),
        ],
        transform: GradientRotation(angle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweep);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.color != color;
}
