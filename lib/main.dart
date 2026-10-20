import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'models.dart';
import 'inference.dart';

void main() => runApp(const NaadchitraApp());

class NaadchitraApp extends StatelessWidget {
  const NaadchitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Naadchitra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5E3C), // warm terracotta
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5E3C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ScanScreen(),
    );
  }
}

// ── Scan Screen ──────────────────────────────────────────────────────────────

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _inference = NaadchitraInference();

  XFile? _image;
  bool _isProcessing = false;
  bool _isReady = false;
  String _status = 'Loading model…';
  EmbeddingResult? _result;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    await _inference.init();
    setState(() {
      _isReady = _inference.isReady;
      _status = _isReady ? 'Ready — pick or photograph artwork' : 'Model not ready';
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await _picker.pickImage(source: source, maxWidth: 2048, imageQuality: 90);
    if (img == null) return;
    _classifyPath(img.path, img);
  }

  /// Debug: classify a test image from the app's cache directory
  Future<void> _debugTest() async {
    // Find the app's cache directory dynamically
    final cacheDir = Directory('/data/data/com.naadchitra.naadchitra/cache/test');
    final testFile = File('${cacheDir.path}/sitar_test.jpg');
    if (!await testFile.exists()) {
      setState(() => _status = 'Test image not found at ${testFile.path}');
      return;
    }
    final img = XFile(testFile.path);
    _classifyPath(testFile.path, img);
  }

  Future<void> _classifyPath(String path, XFile img) async {
    setState(() {
      _image = img;
      _result = null;
      _isProcessing = true;
      _status = 'Scanning…';
    });

    final result = await _inference.classify(path);
    setState(() {
      _result = result;
      _isProcessing = false;
      _status = result != null ? 'Matched: ${result.instrumentName}' : 'Could not identify instrument';
    });
  }

  @override
  void dispose() {
    _inference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naadchitra', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: cs.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _isReady ? Icons.check_circle_outline : Icons.hourglass_empty,
                    size: 20,
                    color: _isReady ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_status,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (_isProcessing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Debug: test classify button
            TextButton.icon(
              onPressed: _isProcessing ? null : _debugTest,
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: const Text('Debug: Test Sitar Image', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 12),

            // Results
            Expanded(child: _buildBody(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_image == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text('Photograph artwork to discover the instrument inside',
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_image!.path), height: 200, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              const Text('No instrument detected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Try a different image with a visible instrument',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return InstrumentResultCard(result: _result!, image: _image!);
  }
}

// ── Result Card ──────────────────────────────────────────────────────────────

class InstrumentResultCard extends StatelessWidget {
  final EmbeddingResult result;
  final XFile image;

  const InstrumentResultCard({super.key, required this.result, required this.image});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final instrument = findInstrumentById(result.instrumentId);
    if (instrument == null) return const SizedBox.shrink();

    return ListView(
      children: [
        // Image + matched instrument header
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.file(File(image.path), height: 180, fit: BoxFit.cover),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.music_note, color: cs.primary, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(instrument.name,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(instrument.family, style: TextStyle(fontSize: 14, color: cs.primary)),
                    Text(instrument.familyEn, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    // Confidence bar
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: result.confidence,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${(result.confidence * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Cultural context card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.secondary),
                    const SizedBox(width: 8),
                    const Text('Cultural Context',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow('Region', instrument.region),
                _infoRow('Period', instrument.period),
                const Divider(height: 24),
                Text(instrument.description, style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Scores breakdown
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detection Confidence',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ..._scoreBars(cs),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Play button
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayScreen(instrument: instrument),
            ),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play This Instrument', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  List<Widget> _scoreBars(ColorScheme cs) {
    final sorted = result.allScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) {
      final name = findInstrumentById(e.key)?.name ?? e.key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(name, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: LinearProgressIndicator(
                value: e.value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                    e.key == result.instrumentId ? cs.primary : cs.outline),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 45,
              child: Text('${(e.value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12), textAlign: TextAlign.end),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ── Play Screen ──────────────────────────────────────────────────────────────

class PlayScreen extends StatefulWidget {
  final Instrument instrument;
  const PlayScreen({super.key, required this.instrument});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late AudioPlayer _player;
  bool _isPlaying = false;

  // Saptak notes, each mapped to a real 1s segment cut from the instrument's
  // own recording (assets/audio/note_<id>_<tag>.mp3, built by tool/extract_notes.py)
  static const _swaras = [
    ('Sa', 'sa'),
    ('Re', 're'),
    ('Ga', 'ga'),
    ('Ma', 'ma'),
    ('Pa', 'pa'),
    ('Dha', 'dha'),
    ('Ni', 'ni'),
    ("Sa'", 'sa2'),
  ];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  void _audioUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No recording yet — add ${widget.instrument.audioFile} to assets/audio/'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _playSwar(String tag) async {
    try {
      // Each note is a real 1-second clip cut from the instrument's own
      // recording, so no pitch-shifting needed — just play the segment.
      await _player.stop();
      await _player.play(AssetSource('audio/note_${widget.instrument.id}_$tag.mp3'));
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('Playback error: $e');
      _audioUnavailable();
    }
  }

  Future<void> _playFull() async {
    try {
      await _player.stop();
      await _player.setPlaybackRate(1.0);
      await _player.play(AssetSource('audio/${widget.instrument.audioFile}'));
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('Playback error: $e');
      _audioUnavailable();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.instrument.name} — Play')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instrument header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(widget.instrument.name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(widget.instrument.family,
                        style: TextStyle(fontSize: 14, color: cs.primary)),
                    Text(widget.instrument.familyEn,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Listen button
            FilledButton.icon(
              onPressed: _isPlaying ? null : _playFull,
              icon: Icon(_isPlaying ? Icons.volume_up : Icons.volume_up_outlined),
              label: Text(_isPlaying ? 'Playing…' : 'Listen to the Instrument'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 24),
            Text('Play the Saptak (七 notes)',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Tap a note — hear a snippet of it from the real recording',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),

            // Saptak grid
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                itemCount: _swaras.length,
                itemBuilder: (context, index) {
                  final (name, tag) = _swaras[index];
                  return GestureDetector(
                    onTap: () => _playSwar(tag),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant, width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer)),
                          const SizedBox(height: 4),
                          Icon(Icons.music_note, color: cs.onPrimaryContainer.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
