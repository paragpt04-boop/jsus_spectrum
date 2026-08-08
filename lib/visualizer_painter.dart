import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'snow.dart';

class VisualizerPainter extends CustomPainter {
  final ui.Image? bg; // imagen 02 (logo) -> fondo
  final ui.Image? circle; // imagen 01 (cósmica) -> círculo con ondas
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

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));

    // ---- fondo (02) con movimiento suave ----
    if (bg != null) {
      final breathe = 1.03 + 0.02 * sin(time * 0.5) + kick * 0.012;
      _drawCover(
        canvas,
        bg!,
        size,
        scale: breathe,
        dx: sin(time * 0.15) * w * 0.010,
        dy: cos(time * 0.12) * h * 0.010,
      );
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.32));
    }

    final hl = palette.isNotEmpty ? palette[0] : const Color(0xFFFFE7A6);
    final warm = palette.length > 1 ? palette[1] : const Color(0xFFF5A623);
    final cool = palette.length > 2 ? palette[2] : const Color(0xFF4FC3D6);

    final baseR = h * 0.26;
    final r = baseR * (1 + kick * 0.05);
    final innerR = r + h * 0.020;
    final maxBar = baseR * 1.15;
    const bars = 140;
    final bands = spectrum.length;

    // ---- anillo de espectro (ondas), simétrico izquierda/derecha ----
    final glowPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final barPaint = Paint()..strokeCap = StrokeCap.round;

    for (int i = 0; i < bars; i++) {
      final tt = i / bars;
      final fold = tt < 0.5 ? tt * 2 : (1 - tt) * 2; // espejo por el eje vertical

      double mag;
      if (bands == 0) {
        // animación idle antes de cargar canción
        mag = 0.10 + 0.06 * (0.5 + 0.5 * sin(time * 2 + i * 0.15));
      } else {
        final bi = fold * (bands - 1);
        final lo = bi.floor().clamp(0, bands - 1);
        final hi = (lo + 1).clamp(0, bands - 1);
        final frac = (bi - lo).clamp(0.0, 1.0);
        mag = spectrum[lo] * (1 - frac) + spectrum[hi] * frac;
      }

      final len = (0.12 + mag * 0.88) * maxBar;
      final ang = -pi / 2 + tt * 2 * pi;
      final ca = cos(ang), sa = sin(ang);
      final p1 = Offset(cx + ca * innerR, cy + sa * innerR);
      final p2 = Offset(cx + ca * (innerR + len), cy + sa * (innerR + len));

      final base = Color.lerp(warm, cool, fold)!;
      final col = Color.lerp(base, hl, mag * 0.6)!;

      glowPaint
        ..color = col.withOpacity(0.55)
        ..strokeWidth = 5.0;
      canvas.drawLine(p1, p2, glowPaint);
      barPaint
        ..color = col
        ..strokeWidth = 3.0;
      canvas.drawLine(p1, p2, barPaint);
    }

    // ---- imagen del círculo (01) girando + pulso con el bajo ----
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
    if (circle != null) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(time * 0.05);
      final s = r * 2.4;
      canvas.drawImageRect(
        circle!,
        Rect.fromLTWH(0, 0, circle!.width.toDouble(), circle!.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: s, height: s),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = warm.withOpacity(0.3));
    }
    canvas.restore();

    // ---- borde del círculo con glow ----
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = hl.withOpacity(0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = hl,
    );

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
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant VisualizerPainter old) => true;
}
