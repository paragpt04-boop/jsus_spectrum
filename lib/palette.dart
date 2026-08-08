import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Saca 3 colores dominantes de la imagen del círculo (01) para teñir las ondas
/// con "sus mismos colores": [brillante, cálido, frío].
Future<List<Color>> extractPalette(String assetPath, {int grid = 42}) async {
  try {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return _fallback;
    final px = bd.buffer.asUint8List();
    final w = img.width, h = img.height;

    final cols = <List<int>>[];
    for (int i = 0; i < grid; i++) {
      for (int j = 0; j < grid; j++) {
        final x = (i / grid * w).floor();
        final y = (j / grid * h).floor();
        final idx = (y * w + x) * 4;
        final r = px[idx], g = px[idx + 1], b = px[idx + 2], a = px[idx + 3];
        if (a < 200) continue;
        final bright = (r + g + b) / 3;
        if (bright < 28) continue; // ignora el negro del fondo
        cols.add([r, g, b, bright.round()]);
      }
    }
    if (cols.isEmpty) return _fallback;

    Color pick(int Function(List<int>) score) {
      cols.sort((a, b) => score(b).compareTo(score(a)));
      final c = cols.first;
      return Color.fromARGB(255, c[0], c[1], c[2]);
    }

    final highlight = pick((c) => c[3]); // más brillante
    final warm = pick((c) => c[0] + c[1] - c[2]); // más cálido (dorado/ámbar)
    final cool = pick((c) => c[2] - c[0]); // más frío (azul/teal)
    return [highlight, warm, cool];
  } catch (_) {
    return _fallback;
  }
}

const _fallback = [
  Color(0xFFFFE7A6),
  Color(0xFFF5A623),
  Color(0xFF4FC3D6),
];
