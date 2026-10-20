import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

class EmbeddingResult {
  final String instrumentId;
  final String instrumentName;
  /// Normalized match score for the winner, in 0..1 (see NaadchitraInference._matchScore).
  final double confidence;
  /// Per-instrument normalized match scores, keyed by instrument id.
  final Map<String, double> allScores;

  EmbeddingResult({
    required this.instrumentId,
    required this.instrumentName,
    required this.confidence,
    required this.allScores,
  });
}

class InstrumentEmbeddings {
  final String model;
  final int dim;
  final Map<String, List<double>> embeddings;
  final Map<String, List<String>> images;

  InstrumentEmbeddings._({
    required this.model,
    required this.dim,
    required this.embeddings,
    required this.images,
  });

  factory InstrumentEmbeddings.fromJson(Map<String, dynamic> json) {
    final instruments = json['instruments'] as Map<String, dynamic>;
    final embeddings = <String, List<double>>{};
    final images = <String, List<String>>{};

    for (final entry in instruments.entries) {
      final data = entry.value as Map<String, dynamic>;
      embeddings[entry.key] = (data['embedding'] as List).map((e) => (e as num).toDouble()).toList();
      images[entry.key] = (data['images'] as List).map((e) => e.toString()).toList();
    }

    return InstrumentEmbeddings._(
      model: json['model'] as String,
      dim: json['dim'] as int,
      embeddings: embeddings,
      images: images,
    );
  }
}

class NaadchitraInference {
  static const channel = MethodChannel('com.naadchitra/embedder');

  InstrumentEmbeddings? _embeddings;
  bool _initialized = false;

  bool get isReady => _initialized && _embeddings != null;

  Future<void> init() async {
    // Load precomputed embeddings from assets
    try {
      final jsonStr = await rootBundle.loadString('assets/refs/embeddings.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      _embeddings = InstrumentEmbeddings.fromJson(json);
    } catch (e) {
      debugPrint('[Naadchitra] Failed to load embeddings: $e');
      return;
    }

    // Initialize the native ONNX embedder
    try {
      final result = await channel.invokeMethod('initialize');
      _initialized = result['success'] == true;
    } catch (e) {
      debugPrint('[Naadchitra] Native init failed: $e');
    }
  }

  // Cosine below this = the photo is not plausibly any of the 5 instruments.
  static const double _gate = 0.50;
  // Normalization span: cosine == _gate maps to 0.0, _gate + _span maps to 1.0.
  static const double _span = 0.40;

  /// Maps a raw cosine (which for real matches sits around 0.65–0.92 in this
  /// embedding space) to a 0..1 match score. Keeps ranking identical to the
  /// cosine while making the confidence bar legible on screen.
  static double _matchScore(double cosine) {
    final s = (cosine - _gate) / _span;
    return s.clamp(0.0, 1.0);
  }

  Future<EmbeddingResult?> classify(String imagePath) async {
    if (!isReady) return null;

    try {
      // Get embedding from native ONNX model
      final result = await channel.invokeMethod('embed', {'imagePath': imagePath});
      final embedding = (result['embedding'] as List).map((e) => (e as num).toDouble()).toList();

      // Cosine similarity against each instrument's reference embedding
      final cosines = <String, double>{};
      for (final entry in _embeddings!.embeddings.entries) {
        cosines[entry.key] = _cosineSimilarity(embedding, entry.value);
      }

      // Winner by raw cosine
      String bestId = '';
      double bestCos = -1;
      for (final entry in cosines.entries) {
        if (entry.value > bestCos) {
          bestCos = entry.value;
          bestId = entry.key;
        }
      }

      // Nothing close enough to all reference means -> not an instrument
      if (bestCos < _gate) return null;

      final scores = cosines.map((k, v) => MapEntry(k, _matchScore(v)));
      final instrument = findInstrumentById(bestId);
      return EmbeddingResult(
        instrumentId: bestId,
        instrumentName: instrument?.name ?? bestId,
        confidence: _matchScore(bestCos),
        allScores: scores,
      );
    } catch (e) {
      debugPrint('[Naadchitra] Classification failed: $e');
      return null;
    }
  }

  void dispose() {
    channel.invokeMethod('release');
  }
}

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;
  double dot = 0.0, normA = 0.0, normB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0.0;
  return dot / (sqrt(normA) * sqrt(normB));
}

