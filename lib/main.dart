import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import 'audio_analyzer.dart';
import 'exporter.dart';
import 'palette.dart';
import 'snow.dart';
import 'visualizer_painter.dart';

void main() => runApp(const JsusSpectrumApp());

class JsusSpectrumApp extends StatelessWidget {
  const JsusSpectrumApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JSUS+ Spectrum',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC14D),
          secondary: Color(0xFFF5A623),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final SnowField _snow = SnowField(90);
  final ValueNotifier<double> _clock = ValueNotifier(0);

  ui.Image? _bg;
  ui.Image? _circle;
  List<Color> _palette = const [
    Color(0xFFFFE7A6),
    Color(0xFFF5A623),
    Color(0xFF4FC3D6),
  ];

  Analysis? _analysis;
  String? _audioPath;
  bool _busy = false;
  String _status = 'Sube una canción para empezar';
  String? _songName;

  // Export
  bool _exporting = false;
  String _exportStage = '';
  final ValueNotifier<double> _exportProg = ValueNotifier(0);

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadAssets() async {
    // fondo = tu logo JSUS+ (bg.png -> se ve TU logo) ; centro = cósmica (circle.png)
    final bg = await _loadImage('assets/bg.png');
    final circle = await _loadImage('assets/circle.png');
    final pal = await extractPalette('assets/circle.png');
    if (!mounted) return;
    setState(() {
      _bg = bg;
      _circle = circle;
      _palette = pal;
    });
  }

  Future<ui.Image> _loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final t = elapsed.inMicroseconds / 1e6;
    _snow.update(dt, t, _currentKick());
    _clock.value = t;
  }

  int _frameIndex() {
    final a = _analysis;
    if (a == null) return -1;
    final idx = (_player.position.inMicroseconds / 1e6 * a.fps).floor();
    if (idx < 0) return 0;
    if (idx >= a.frameCount) return a.frameCount - 1;
    return idx;
  }

  Float32List _currentSpectrum() {
    final a = _analysis;
    if (a == null) return Float32List(0);
    return a.frames[_frameIndex()];
  }

  double _currentKick() {
    final a = _analysis;
    if (a == null || !_player.playing) return 0;
    return a.kick[_frameIndex()];
  }

  Future<void> _pickAndAnalyze() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _status = 'Analizando tempo y frecuencias…';
      _songName = res!.files.single.name;
      _audioPath = path;
    });
    try {
      await _player.setFilePath(path);
      final analysis = await AudioAnalyzer.analyze(path, fps: 30);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _busy = false;
        _status = 'Listo · ${analysis.bpm.round()} BPM';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error al analizar';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _togglePlay() {
    if (_player.playing) {
      _player.pause();
    } else {
      if (_player.position >= (_player.duration ?? Duration.zero)) {
        _player.seek(Duration.zero);
      }
      _player.play();
    }
  }

  Future<void> _startExport() async {
    final a = _analysis;
    final audio = _audioPath;
    if (a == null || audio == null) return;

    final choice = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Exportar video'),
        content: const Text(
          'Se renderiza cuadro por cuadro para que salga profesional y sin '
          'tirones. Puede tardar varios minutos y necesita espacio libre en el '
          'teléfono. No cierres la app mientras trabaja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, [1280, 720]),
            child: const Text('HD 720p'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFF5A623)),
            onPressed: () => Navigator.pop(ctx, [1920, 1080]),
            child: const Text('Full HD 1080p'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    _player.pause();
    _ticker.stop();
    setState(() {
      _exporting = true;
      _exportStage = 'Preparando…';
    });
    _exportProg.value = 0;

    try {
      final outPath = await VideoExporter.export(
        bg: _bg,
        circle: _circle,
        palette: _palette,
        analysis: a,
        audioPath: audio,
        width: choice[0],
        height: choice[1],
        onProgress: (p, stage) {
          _exportProg.value = p;
          if (stage != _exportStage && mounted) {
            setState(() => _exportStage = stage);
          }
        },
      );
      if (!mounted) return;
      setState(() => _exporting = false);
      _ticker.start();
      await Share.shareXFiles([XFile(outPath)],
          text: 'Hecho con JSUS+ Spectrum');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video listo: $outPath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _ticker.start();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _player.dispose();
    _clock.dispose();
    _exportProg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('JSUS',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1)),
                      const Text('+',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFC14D))),
                      const Spacer(),
                      Text(_status,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white10),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFFFC14D)
                                    .withOpacity(0.08),
                                blurRadius: 30),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _clock,
                          builder: (_, t, __) => CustomPaint(
                            size: Size.infinite,
                            painter: VisualizerPainter(
                              bg: _bg,
                              circle: _circle,
                              spectrum: _currentSpectrum(),
                              kick: _currentKick(),
                              time: t,
                              palette: _palette,
                              snow: _snow,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_songName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Text(_songName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_busy || _exporting) ? null : _pickAndAnalyze,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.library_music),
                          label:
                              Text(_busy ? 'Analizando…' : 'Elegir canción'),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              foregroundColor: Colors.black),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: (_analysis == null || _exporting)
                            ? null
                            : _togglePlay,
                        icon: Icon(_player.playing
                            ? Icons.pause
                            : Icons.play_arrow),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: (_analysis == null || _exporting)
                            ? null
                            : _startExport,
                        icon: const Icon(Icons.hd),
                        label: const Text('Exportar'),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2B2B2B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_exporting) _buildExportOverlay(),
        ],
      ),
    );
  }

  Widget _buildExportOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.82),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Generando tu video',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                ValueListenableBuilder<double>(
                  valueListenable: _exportProg,
                  builder: (_, p, __) => Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 10,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFFFC14D)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${(p * 100).toStringAsFixed(0)} %',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(_exportStage,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 16),
                Text('No cierres la app',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
