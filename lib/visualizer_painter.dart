import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'snow.dart';

class VisualizerPainter extends CustomPainter {
  final ui.Image? bg; // fondo (cósmica)
  final ui.Image? circle; // centro (logo JSUS+)
  final Float32List spectrum; // bandas 0..1 del frame actual
  final double kick; // 0..1
  final double time; // segundos
  final List<Color> palette; // [brillante, cálido, frío]
  final SnowField snow;

  VisualizerPainter({
    required this.bg,
    required this.circle,
    required this.spectrum,
    required this.kick,
    required this.time,
    required this.palette,
    required this.snow,
  });

  // Muchas barras finas y pegadas => se leen como una ola continua.
  static const int bars = 260;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));

    // ---- fondo (cósmica) con movimiento suave ----
    if (bg != null) {
      final breathe = 1.03 + 0.02 * sin(time * 0.5) + kick * 0.012;
      _drawCover(canvas, bg!, size,
          scale: breathe,
          dx: sin(time * 0.15) * w * 0.010,
          dy: cos(time * 0.12) * h * 0.010);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.38));
    }

    final hl = palette.isNotEmpty ? palette[0] : const Color(0xFFFFE7A6);
    final warm = palette.length > 1 ? palette[1] : const Color(0xFFF5A623);

    final baseR = h * 0.235;
    final r = baseR * (1 + kick * 0.06);
    final innerR = r; // las ondas salen justo del borde de tu logo, hacia afuera
    final maxBar = baseR * 0.95;
    final bands = spectrum.length;

    // ---- calcular longitudes y suavizarlas (efecto ola) ----
    final lens = List<double>.filled(bars, 0);
    for (int i = 0; i < bars; i++) {
      final tt = i / bars;
      final fold = tt < 0.5 ? tt * 2 : (1 - tt) * 2; // simétrico izq/der
      double mag;
      if (bands == 0) {
        mag = 0.12 + 0.05 * (0.5 + 0.5 * sin(time * 2 + i * 0.20));
      } else {
        final bi = fold * (bands - 1);
        final lo = bi.floor().clamp(0, bands - 1);
        final hi = (lo + 1).clamp(0, bands - 1);
        final frac = (bi - lo).clamp(0.0, 1.0);
        mag = spectrum[lo] * (1 - frac) + spectrum[hi] * frac;
      }
      lens[i] = (0.06 + mag * 0.94) * maxBar;
    }
    // suavizado circular (2 pasadas) para que las puntas fluyan como olas
    for (int pass = 0; pass < 2; pass++) {
      final copy = List<double>.from(lens);
      for (int i = 0; i < bars; i++) {
        final a = copy[(i - 1 + bars) % bars];
        final b = copy[i];
        final c = copy[(i + 1) % bars];
        lens[i] = a * 0.25 + b * 0.5 + c * 0.25;
      }
    }

    // el bajo/kick empuja TODA la ola hacia afuera (pega duro)
    final kickBoost = 1.0 + kick * 0.85;
    for (int i = 0; i < bars; i++) {
      lens[i] *= kickBoost;
    }

    // ---- GLOW: un solo blur del contorno (barato y rápido) ----
    final glow = Path();
    for (int i = 0; i <= bars; i++) {
      final k = i % bars;
      final ang = -pi / 2 + (i / bars) * 2 * pi;
      final rr = innerR + lens[k];
      final p = Offset(cx + cos(ang) * rr, cy + sin(ang) * rr);
      if (i == 0) {
        glow.moveTo(p.dx, p.dy);
      } else {
        glow.lineTo(p.dx, p.dy);
      }
    }
    for (int i = bars; i >= 0; i--) {
      final ang = -pi / 2 + (i / bars) * 2 * pi;
      final p = Offset(cx + cos(ang) * innerR, cy + sin(ang) * innerR);
      glow.lineTo(p.dx, p.dy);
    }
    glow.close();
    canvas.drawPath(
      glow,
      Paint()
        ..color = warm.withOpacity(0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, maxBar * 0.07),
    );

    // ---- barras finas pegadas (sin blur individual => rápido) ----
    final barW = max(1.6, (2 * pi * innerR / bars) * 0.92);
    final barPaint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < bars; i++) {
      final tt = i / bars;
      final fold = tt < 0.5 ? tt * 2 : (1 - tt) * 2;
      final ang = -pi / 2 + tt * 2 * pi;
      final ca = cos(ang), sa = sin(ang);
      final len = lens[i];
      final magN = (len / maxBar).clamp(0.0, 1.0);
      final p1 = Offset(cx + ca * innerR, cy + sa * innerR);
      final p2 = Offset(cx + ca * (innerR + len), cy + sa * (innerR + len));
      final col = Color.lerp(warm, hl, 0.25 + magN * 0.6)!;
      barPaint
        ..color = col
        ..strokeWidth = barW;
      canvas.drawLine(p1, p2, barPaint);
    }

    // ---- logo (02) en el centro, quieto, latiendo con el bajo ----
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
    canvas.drawColor(Colors.black, BlendMode.srcOver);
    if (circle != null) {
      final s = r * 2.05;
      canvas.drawImageRect(
        circle!,
        Rect.fromLTWH(0, 0, circle!.width.toDouble(), circle!.height.toDouble()),
        Rect.fromCenter(center: Offset(cx, cy), width: s, height: s),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();

    // (sin anillo dibujado: se usa el que ya trae tu logo)

    // ---- nieve ----
    snow.paint(canvas, size, Colors.white, time);
  }

  void _drawCover(Canvas canvas, ui.Image img, Size size,
      {double scale = 1.0, double dx = 0, double dy = 0}) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = max(size.width / iw, size.height / ih) * scale;
    final dw = iw * s, dh = ih * s;
    final left = (size.width - dw) / 2 + dx;
    final top = (size.height - dh) / 2 + dy;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(left, top, dw, dh),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant VisualizerPainter old) => true;
}
