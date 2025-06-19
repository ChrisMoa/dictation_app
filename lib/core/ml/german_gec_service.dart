import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'dart:io';

class GermanGECService {
  static const String modelAsset = 'assets/models/german_gec_dynamic.tflite';
  static const String vocabAsset = 'assets/models/vocab.json';
  static const int maxLength = 64;
  
  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  Map<int, String>? _reverseVocab;
  
  Future<void> initialize() async {
    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset(modelAsset);
      print('TFLite model loaded successfully');
      
      // Load vocabulary
      await _loadVocabulary();
      
      // Allocate tensors
      _interpreter!.allocateTensors();
      
      print('German GEC Service initialized');
    } catch (e) {
      print('Error initializing GEC Service: $e');
      throw Exception('Failed to initialize German GEC Service');
    }
  }
  
  Future<void> _loadVocabulary() async {
    try {
      final String vocabJson = await DefaultAssetBundle.of(context).loadString(vocabAsset);
      final Map<String, dynamic> vocabData = json.decode(vocabJson);
      
      _vocab = Map<String, int>.from(vocabData);
      _reverseVocab = _vocab!.map((key, value) => MapEntry(value, key));
      
      print('Vocabulary loaded: ${_vocab!.length} tokens');
    } catch (e) {
      print('Error loading vocabulary: $e');
      // Fallback: create minimal vocab
      _createMinimalVocab();
    }
  }
  
  void _createMinimalVocab() {
    // Minimal MT5 vocab for basic functionality
    _vocab = {
      '<pad>': 0,
      '</s>': 1,
      '<unk>': 2,
      'Korrigiere': 100,
      ':': 101,
      'Das': 200,
      'ist': 201,
      'ein': 202,
      'fehler': 203,
      '.': 204,
    };
    _reverseVocab = _vocab!.map((key, value) => MapEntry(value, key));
  }
  
  List<int> _tokenize(String text) {
    // Simple tokenization - in production use proper MT5 tokenizer
    final words = text.toLowerCase().split(' ');
    final tokens = <int>[];
    
    for (final word in words) {
      if (_vocab!.containsKey(word)) {
        tokens.add(_vocab![word]!);
      } else {
        tokens.add(_vocab!['<unk>']!); // Unknown token
      }
    }
    
    // Pad or truncate to maxLength
    while (tokens.length < maxLength) {
      tokens.add(_vocab!['<pad>']!);
    }
    
    return tokens.take(maxLength).toList();
  }
  
  String _detokenize(List<int> tokens) {
    final words = <String>[];
    
    for (final token in tokens) {
      if (token == _vocab!['<pad>'] || token == _vocab!['</s>']) {
        break; // Stop at padding or end token
      }
      
      if (_reverseVocab!.containsKey(token)) {
        words.add(_reverseVocab![token]!);
      }
    }
    
    return words.join(' ');
  }
  
  Future<GECResult> correctText(String text) async {
    if (_interpreter == null) {
      throw Exception('Model not initialized');
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Prepare input
      final inputText = 'Korrigiere: $text';
      final inputTokens = _tokenize(inputText);
      
      // Create input tensor
      final inputData = [inputTokens];
      final inputTensor = [inputData];
      
      // Create output tensor
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final outputData = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => List.filled(outputShape[2], 0.0),
        ),
      );
      
      // Run inference
      _interpreter!.run(inputTensor, outputData);
      
      // Process output
      final predictions = outputData[0];
      final predictedTokens = <int>[];
      
      for (final logits in predictions) {
        final maxIndex = _argmax(logits);
        predictedTokens.add(maxIndex);
      }
      
      final correctedText = _detokenize(predictedTokens);
      
      stopwatch.stop();
      
      return GECResult(
        originalText: text,
        correctedText: correctedText,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
        confidence: _calculateConfidence(predictions),
      );
      
    } catch (e) {
      stopwatch.stop();
      print('Error during inference: $e');
      
      return GECResult(
        originalText: text,
        correctedText: text, // Return original on error
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
        confidence: 0.0,
        error: e.toString(),
      );
    }
  }
  
  int _argmax(List<double> list) {
    int maxIndex = 0;
    double maxValue = list[0];
    
    for (int i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }
    
    return maxIndex;
  }
  
  double _calculateConfidence(List<List<double>> predictions) {
    double totalConfidence = 0.0;
    int validTokens = 0;
    
    for (final logits in predictions) {
      final maxLogit = logits.reduce((a, b) => a > b ? a : b);
      final expSum = logits.fold(0.0, (sum, logit) => sum + exp(logit - maxLogit));
      final softmax = exp(maxLogit - maxLogit) / expSum;
      
      if (softmax > 0.1) { // Only count confident predictions
        totalConfidence += softmax;
        validTokens++;
      }
    }
    
    return validTokens > 0 ? totalConfidence / validTokens : 0.0;
  }
  
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class GECResult {
  final String originalText;
  final String correctedText;
  final int inferenceTimeMs;
  final double confidence;
  final String? error;
  
  const GECResult({
    required this.originalText,
    required this.correctedText,
    required this.inferenceTimeMs,
    required this.confidence,
    this.error,
  });
  
  bool get hasCorrections => originalText != correctedText;
  bool get hasError => error != null;
  
  @override
  String toString() {
    return 'GECResult('
        'original: "$originalText", '
        'corrected: "$correctedText", '
        'time: ${inferenceTimeMs}ms, '
        'confidence: ${confidence.toStringAsFixed(2)}'
        ')';
  }
}