import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'fft.dart';

/// Resultado del análisis, precomputado y determinista (mismo audio => mismos frames).
class Analysis {
  final List<Float32List> frames; // magnitudes por banda [0..1] por cada frame de video
  final Float32List kick; // fuerza del bombo/bajo [0..1] por frame
  final int bands;
  final double fps;
  final int frameCount;
  final double durationSec;
  final double bpm;

  Analysis(this.frames, this.kick, this.bands, this.fps, this.frameCount,
      this.durationSec, this.bpm);
}

class AudioAnalyzer {
  static const int sampleRate = 22050;
  static const int fftSize = 2048;
  static const int bands = 72;

  /// Decodifica cualquier audio a WAV PCM con ffmpeg y luego analiza en un isolate.
  static Future<Analysis> analyze(String audioPath, {double fps = 30}) async {
    final tmp = await getTemporaryDirectory();
    final wavPath =
        '${tmp.path}/jsus_${DateTime.now().millisecondsSinceEpoch}.wav';
    final wavFile = File(wavPath);
    if (await wavFile.exists()) await wavFile.delete();

    final cmd =
        '-y -i "$audioPath" -vn -ac 1 -ar $sampleRate -acodec pcm_s16le "$wavPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('No se pudo decodificar el audio (código $rc).');
    }

    final analysis = await compute(_analyzeEntry, _Args(wavPath, fps));

    try {
      await wavFile.delete();
    } catch (_) {}
    return analysis;
  }

  // ---- lo que corre dentro del isolate ----

  static Float64List _readWavMono(String path) {
    final bytes = File(path).readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    int pos = 12; // saltar "RIFF"<size>"WAVE"
    int dataOffset = -1, dataLen = 0;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      if (id == 'data') {
        dataOffset = pos + 8;
        dataLen = size;
        break;
      }
      pos += 8 + size + (size & 1);
    }
    if (dataOffset < 0) throw Exception('WAV inválido (sin chunk data)');
    if (dataOffset + dataLen > bytes.length) {
      dataLen = bytes.length - dataOffset; // por si el header miente
    }
    final count = dataLen ~/ 2;
    final out = Float64List(count);
    int p = dataOffset;
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(p, Endian.little) / 32768.0;
      p += 2;
    }
    return out;
  }

  static Analysis _process(Float64List samples, double fps) {
    final fft = FFT(fftSize);
    final total = samples.length;
    final durationSec = total / sampleRate;
    final frameCount = max(1, (durationSec * fps).floor());

    final hann = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      hann[i] = 0.5 * (1 - cos(2 * pi * i / (fftSize - 1)));
    }

    final nyq = sampleRate / 2.0;
    const minF = 30.0;
    final maxF = nyq;
    final edges = List<int>.generate(bands + 1, (b) {
      final frac = b / bands;
      final freq = minF * pow(maxF / minF, frac);
      return (freq / nyq * (fftSize / 2)).round().clamp(0, fftSize ~/ 2);
    });
    final kickHiBin = (140.0 / nyq * (fftSize / 2)).round();

    final re = Float64List(fftSize);
    final im = Float64List(fftSize);
    final tmpFrames = List<Float64List>.generate(frameCount, (_) => Float64List(bands));
    final kickRaw = Float64List(frameCount);
    double globalMax = 1e-9;

    for (int f = 0; f < frameCount; f++) {
      final center = ((f / fps) * sampleRate).round();
      final start = center - (fftSize >> 1);
      for (int i = 0; i < fftSize; i++) {
        final si = start + i;
        final v = (si >= 0 && si < total) ? samples[si] : 0.0;
        re[i] = v * hann[i];
        im[i] = 0.0;
      }
      fft.transform(re, im);

      final band = tmpFrames[f];
      for (int b = 0; b < bands; b++) {
        int lo = edges[b], hi = edges[b + 1];
        if (hi <= lo) hi = lo + 1;
        double sum = 0;
        for (int k = lo; k < hi; k++) {
          sum += sqrt(re[k] * re[k] + im[k] * im[k]);
        }
        final avg = sum / (hi - lo);
        final val = log(1 + avg * 8); // escala perceptual
        band[b] = val;
        if (val > globalMax) globalMax = val;
      }

      double le = 0;
      for (int k = 1; k <= kickHiBin; k++) {
        le += sqrt(re[k] * re[k] + im[k] * im[k]);
      }
      kickRaw[f] = le;
    }

    final frames = <Float32List>[];
    for (int f = 0; f < frameCount; f++) {
      final src = tmpFrames[f];
      final dst = Float32List(bands);
      // suavizado espacial ligero entre bandas para que las barras fluyan
      for (int b = 0; b < bands; b++) {
        final prev = b > 0 ? src[b - 1] : src[b];
        final next = b < bands - 1 ? src[b + 1] : src[b];
        final v = (src[b] * 0.6 + prev * 0.2 + next * 0.2) / globalMax;
        dst[b] = v.clamp(0.0, 1.0);
      }
      frames.add(dst);
    }

    // envolvente del bombo: onset (diferencia positiva), normalizado, ataque rápido / caída lenta
    final onset = Float64List(frameCount);
    double kmax = 1e-9;
    for (int f = 1; f < frameCount; f++) {
      final d = kickRaw[f] - kickRaw[f - 1];
      onset[f] = d > 0 ? d : 0;
      if (onset[f] > kmax) kmax = onset[f];
    }
    final kick = Float32List(frameCount);
    double env = 0;
    for (int f = 0; f < frameCount; f++) {
      final o = (onset[f] / kmax).clamp(0.0, 1.0);
      if (o > env) {
        env = o;
      } else {
        env *= 0.80;
      }
      kick[f] = env;
    }

    final bpm = _estimateBpm(kickRaw, fps);
    return Analysis(frames, kick, bands, fps, frameCount, durationSec, bpm);
  }

  static double _estimateBpm(Float64List env, double fps) {
    final n = env.length;
    if (n < fps.toInt() * 2) return 0;
    final minLag = (fps * 60 / 180).round();
    final maxLag = (fps * 60 / 60).round();
    double best = -1;
    int bestLag = minLag;
    for (int lag = minLag; lag <= maxLag && lag < n; lag++) {
      double s = 0;
      for (int i = lag; i < n; i++) {
        s += env[i] * env[i - lag];
      }
      if (s > best) {
        best = s;
        bestLag = lag;
      }
    }
    if (bestLag == 0) return 0;
    return 60.0 * fps / bestLag;
  }
}

class _Args {
  final String wavPath;
  final double fps;
  _Args(this.wavPath, this.fps);
}

// Entry point del isolate (top-level, mismo archivo => accede a los métodos privados).
Analysis _analyzeEntry(_Args a) =>
    AudioAnalyzer._process(AudioAnalyzer._readWavMono(a.wavPath), a.fps);
