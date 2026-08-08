import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_analyzer.dart';
import 'snow.dart';
import 'visualizer_painter.dart';

class VideoExporter {
  /// Renderiza el mismo motor del preview, frame por frame (determinista, sin
  /// tirones), y lo codifica en MP4 H.264 + audio original. Devuelve la ruta.
  static Future<String> export({
    required ui.Image? bg,
    required ui.Image? circle,
    required List<Color> palette,
    required Analysis analysis,
    required String audioPath,
    required int width,
    required int height,
    required void Function(double progress, String stage) onProgress,
  }) async {
    final fps = analysis.fps;
    final frameCount = analysis.frameCount;
    final size = Size(width.toDouble(), height.toDouble());

    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final framesDir = Directory('${tmp.path}/jsus_frames_$stamp');
    if (framesDir.existsSync()) framesDir.deleteSync(recursive: true);
    framesDir.createSync(recursive: true);

    // Nieve determinista para el export (misma semilla, avance fijo por frame).
    final snow = SnowField(90);

    for (int f = 0; f < frameCount; f++) {
      final t = f / fps;
      snow.update(1 / fps, t, analysis.kick[f]);

      final recorder = ui.PictureRecorder();
      final canvas =
          Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      VisualizerPainter(
        bg: bg,
        circle: circle,
        spectrum: analysis.frames[f],
        kick: analysis.kick[f],
        time: t,
        palette: palette,
        snow: snow,
      ).paint(canvas, size);

      final pic = recorder.endRecording();
      final img = await pic.toImage(width, height);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      pic.dispose();

      if (bytes != null) {
        final name = 'f_${f.toString().padLeft(5, '0')}.png';
        File('${framesDir.path}/$name')
            .writeAsBytesSync(bytes.buffer.asUint8List());
      }

      onProgress((f + 1) / frameCount * 0.8, 'Renderizando ${f + 1}/$frameCount');
      if (f % 2 == 0) await Future.delayed(Duration.zero); // deja respirar la UI
    }

    onProgress(0.82, 'Codificando video…');
    final outPath = '${tmp.path}/JSUS_Spectrum_$stamp.mp4';
    final cmd = '-y -framerate ${fps.round()} '
        '-i "${framesDir.path}/f_%05d.png" '
        '-i "$audioPath" '
        '-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p '
        '-c:a aac -b:a 192k -shortest "$outPath"';

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();

    try {
      framesDir.deleteSync(recursive: true);
    } catch (_) {}

    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Falló la codificación (código $rc).');
    }
    onProgress(1.0, 'Listo');
    return outPath;
  }
}
