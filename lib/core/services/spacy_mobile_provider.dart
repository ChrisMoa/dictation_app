import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'ai_grammar_service.dart';

class SpaCyMobileProvider implements GrammarCorrectionProvider {
  static const String _modelPath = 'assets/models/de_grammar_model.tflite';
  static const String _vocabPath = 'assets/models/de_vocab.json';
  Interpreter? _interpreter;
  Map<String, int>? _vocabulary;
  bool _isInitialized = false;

  @override
  String get providerName => 'SpaCy Mobile Grammar Checker';

  /// Initialize the TensorFlow Lite model
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load vocabulary
      final vocabData = await rootBundle.loadString(_vocabPath);
      _vocabulary = Map<String, int>.from(json.decode(vocabData));

      // Copy model to temporary directory
      final modelFile = await _getModelFile();
      
      // Load TFLite model
      _interpreter = await Interpreter.fromFile(modelFile);
      _isInitialized = true;
      
      debugPrint('SpaCyMobileProvider: Model initialized successfully');
    } catch (e) {
      debugPrint('SpaCyMobileProvider: Error initializing model: $e');
      rethrow;
    }
  }

  /// Get the model file from assets
  Future<File> _getModelFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelFile = File('${appDir.path}/de_grammar_model.tflite');
    
    if (!await modelFile.exists()) {
      final modelData = await rootBundle.load(_modelPath);
      await modelFile.writeAsBytes(modelData.buffer.asUint8List());
    }
    
    return modelFile;
  }

  /// Convert text to model input format
  List<int> _textToInput(String text) {
    final words = text.toLowerCase().split(' ');
    return words.map((word) => _vocabulary?[word] ?? 0).toList();
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Prepare input
      final input = _textToInput(text);
      final inputShape = [1, input.length]; // Batch size 1
      final outputShape = [1, input.length, _vocabulary!.length];

      // Prepare input and output tensors
      final inputArray = Float32List.fromList(input.map((e) => e.toDouble()).toList());
      final outputArray = Float32List(outputShape.reduce((a, b) => a * b));

      // Run inference
      _interpreter!.run(inputArray.buffer, outputArray.buffer);

      // Process results
      final results = _processModelOutput(text, outputArray);
      
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: results['correctedText'],
        confidence: results['confidence'],
        errors: results['errors'],
        correctionMethod: providerName,
      );
    } catch (e) {
      debugPrint('SpaCyMobileProvider: Error processing text: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _processModelOutput(String originalText, Float32List output) {
    // Convert model output to corrections
    final words = originalText.split(' ');
    List<GrammarError> errors = [];
    String correctedText = originalText;
    int errorCount = 0;

    // Process each word's predictions
    for (int i = 0; i < words.length; i++) {
      final wordStart = i * _vocabulary!.length;
      final wordPredictions = output.sublist(wordStart, wordStart + _vocabulary!.length);
      
      // Find the most likely correction
      final maxIndex = wordPredictions.indexOf(wordPredictions.reduce(max));
      final originalWord = words[i];
      final predictedWord = _vocabulary!.entries
          .firstWhere((e) => e.value == maxIndex)
          .key;

      if (predictedWord != originalWord.toLowerCase()) {
        errorCount++;
        errors.add(GrammarError(
          offset: correctedText.indexOf(originalWord),
          length: originalWord.length,
          message: 'Consider using "$predictedWord" instead of "$originalWord"',
          category: 'Grammar',
          replacements: [predictedWord],
          ruleId: 'word_prediction',
        ));

        // Apply correction
        correctedText = correctedText.replaceFirst(originalWord, predictedWord);
      }
    }

    // Calculate confidence
    final confidence = 1.0 - (errorCount / words.length);
    
    return {
      'correctedText': correctedText,
      'confidence': confidence.clamp(0.0, 1.0),
      'errors': errors,
    };
  }

  /// Clean up resources
  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
} 