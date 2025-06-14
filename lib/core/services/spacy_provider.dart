import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_grammar_service.dart';

class SpaCyProvider implements GrammarCorrectionProvider {
  static const String _spacyServiceUrl = 'http://localhost:5000/check';
  bool _isServiceRunning = false;

  @override
  String get providerName => 'SpaCy Grammar Checker';

  /// Check if the SpaCy service is running
  Future<bool> isServiceAvailable() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:5000/check'))
          .timeout(const Duration(seconds: 1));
      _isServiceRunning = response.statusCode != 404;
      return _isServiceRunning;
    } catch (e) {
      _isServiceRunning = false;
      return false;
    }
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    if (!_isServiceRunning) {
      final isAvailable = await isServiceAvailable();
      if (!isAvailable) {
        throw Exception('SpaCy service is not running. Please start the Python service first.');
      }
    }

    try {
      final response = await http.post(
        Uri.parse(_spacyServiceUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return GrammarCorrectionResult(
          originalText: data['originalText'],
          correctedText: data['correctedText'],
          confidence: data['confidence'].toDouble(),
          errors: (data['errors'] as List)
              .map((e) => GrammarError(
                    offset: e['offset'],
                    length: e['length'],
                    message: e['message'],
                    category: e['category'],
                    replacements: List<String>.from(e['replacements']),
                    ruleId: e['ruleId'],
                  ))
              .toList(),
          correctionMethod: data['correctionMethod'],
        );
      } else {
        throw Exception('SpaCy service error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('SpaCyProvider: Error: $e');
      rethrow;
    }
  }
} 