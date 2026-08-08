import 'dart:math';
import 'dart:typed_data';

/// FFT radix-2 en el sitio (Cooley-Tukey). n debe ser potencia de 2.
class FFT {
  final int n;
  late final Int32List _rev;
  late final Float64List _cos;
  late final Float64List _sin;

  FFT(this.n) {
    assert((n & (n - 1)) == 0, 'n debe ser potencia de 2');
    final bits = _log2(n);
    _rev = Int32List(n);
    for (int i = 0; i < n; i++) {
      int x = i, r = 0;
      for (int b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
    final half = n >> 1;
    _cos = Float64List(half);
    _sin = Float64List(half);
    for (int i = 0; i < half; i++) {
      _cos[i] = cos(-2 * pi * i / n);
      _sin[i] = sin(-2 * pi * i / n);
    }
  }

  int _log2(int x) {
    int r = 0;
    while ((1 << r) < x) r++;
    return r;
  }

  /// Transforma en el sitio. re/im deben tener longitud n.
  void transform(Float64List re, Float64List im) {
    // bit-reversal
    for (int i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        double t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    for (int size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (int i = 0; i < n; i += size) {
        int k = 0;
        for (int j = i; j < i + half; j++) {
          final wr = _cos[k];
          final wi = _sin[k];
          final tpre = re[j + half] * wr - im[j + half] * wi;
          final tpim = re[j + half] * wi + im[j + half] * wr;
          re[j + half] = re[j] - tpre;
          im[j + half] = im[j] - tpim;
          re[j] += tpre;
          im[j] += tpim;
          k += step;
        }
      }
    }
  }
}
