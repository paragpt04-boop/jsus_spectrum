import 'dart:math';

import 'package:flutter/material.dart';

/// Nieve/goticas estilo Trap City. Posiciones en espacio normalizado 0..1.
class SnowField {
  final List<_Flake> flakes = [];
  final Random _r = Random(7);

  SnowField([int count = 90]) {
    for (int i = 0; i < count; i++) {
      flakes.add(_spawn(initial: true));
    }
  }

  _Flake _spawn({bool initial = false}) => _Flake(
        x: _r.nextDouble(),
        y: initial ? _r.nextDouble() : -0.05,
        r: 0.6 + _r.nextDouble() * 2.4,
        speed: 0.02 + _r.nextDouble() * 0.06,
        drift: (_r.nextDouble() - 0.5) * 0.03,
        phase: _r.nextDouble() * pi * 2,
        twinkle: 0.4 + _r.nextDouble() * 0.6,
      );

  void update(double dt, double t, double kick) {
    final boost = 1 + kick * 0.6;
    for (final f in flakes) {
      f.y += f.speed * dt * boost;
      f.x += sin(f.phase + t * 0.6) * f.drift * dt * 8;
      if (f.y > 1.08) {
        final n = _spawn();
        f
          ..x = n.x
          ..y = n.y
          ..r = n.r
          ..speed = n.speed
          ..drift = n.drift
          ..phase = n.phase
          ..twinkle = n.twinkle;
      }
    }
  }

  void paint(Canvas canvas, Size size, Color color, double t) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final f in flakes) {
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2 + f.phase)) * f.twinkle;
      p.color = color.withOpacity(0.55 * tw.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(f.x * size.width, f.y * size.height),
        f.r,
        p,
      );
    }
  }
}

class _Flake {
  double x, y, r, speed, drift, phase, twinkle;
  _Flake({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.drift,
    required this.phase,
    required this.twinkle,
  });
}
