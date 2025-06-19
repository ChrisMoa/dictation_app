// Flutter TFLite Integration Example
// Based on working model test

import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';

class GermanGECTFLite {
  static const String modelAsset = 'assets/models/german_gec_optimized.tflite';
  static const String vocabAsset = 'assets/models/vocab_optimized.json';
  
  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  
  // Model expects input shape: (1, 1)
  static const int maxLength = 1;
  
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
      
      // Load vocabulary
      final vocabJson = await rootBundle.loadString(vocabAsset);
      final Map<String, dynamic> vocabData = json.decode(vocabJson);
      _vocab = Map<String, int>.from(vocabData);
      
      print('✅ German GEC TFLite initialized');
      print('   Model size: ~16.6 MB');
      print('   Expected inference time: ~40ms');
      
    } catch (e) {
      print('❌ Failed to initialize GEC: $e');
      throw Exception('GEC initialization failed');
    }
  }
  
  Future<String> correctText(String text) async {
    if (_interpreter == null || _vocab == null) {
      throw Exception('Model not initialized');
    }
    
    try {
      // Tokenize input
      final tokens = _tokenize(text);
      
      // Prepare input tensor
      final inputData = Int32List(maxLength);
      for (int i = 0; i < maxLength; i++) {
        inputData[i] = i < tokens.length ? tokens[i] : 0; // 0 = <pad>
      }
      
      // Reshape for model: [1, maxLength]
      final input = inputData.reshape([1, maxLength]);
      
      // Prepare output tensor  
      final output = List.generate(1, (_) => 
        List.generate(maxLength, (_) => 
          List.filled(32000, 0.0) // vocab_size = 32000
        )
      );
      
      // Run inference
      final stopwatch = Stopwatch()..start();
      _interpreter!.run(input, output);
      stopwatch.stop();
      
      // Get predictions (argmax)
      final predictions = <int>[];
      for (int i = 0; i < maxLength; i++) {
        double maxLogit = output[0][i][0];
        int maxIndex = 0;
        
        for (int j = 1; j < output[0][i].length; j++) {
          if (output[0][i][j] > maxLogit) {
            maxLogit = output[0][i][j];
            maxIndex = j;
          }
        }
        
        predictions.add(maxIndex);
      }
      
      // Detokenize
      final correctedText = _detokenize(predictions);
      
      print('Inference time: ${stopwatch.elapsedMilliseconds}ms');
      
      return correctedText;
      
    } catch (e) {
      print('❌ Correction failed: $e');
      return text; // Return original on error
    }
  }
  
  List<int> _tokenize(String text) {
    // Simple tokenization (implement your logic here)
    final words = text.toLowerCase().split(' ');
    final tokens = <int>[];
    
    for (final word in words) {
      final tokenId = _vocab![word] ?? _vocab!['<unk>'] ?? 1;
      tokens.add(tokenId);
    }
    
    return tokens;
  }
  
  String _detokenize(List<int> tokens) {
    // Convert token IDs back to text
    final reverseVocab = Map.fromEntries(
      _vocab!.entries.map((e) => MapEntry(e.value, e.key))
    );
    
    final words = <String>[];
    for (final tokenId in tokens) {
      if (tokenId == 0) break; // Stop at padding
      
      final word = reverseVocab[tokenId];
      if (word != null && !word.startsWith('__')) {
        words.add(word.replaceAll('▁', ''));
      }
    }
    
    return words.join(' ');
  }
  
  void dispose() {
    _interpreter?.close();
  }
}

// Usage Example:
/*
final gec = GermanGECTFLite();
await gec.initialize();

final corrected = await gec.correctText("Das ist ein fehler.");
print("Corrected: $corrected");
*/
