import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dictation_app/core/services/ai_grammar_service.dart';

/// Ollama grammar correction provider that communicates with local Ollama API
class OllamaGrammarProvider implements GrammarCorrectionProvider {
  final String ollamaUrl;
  final String modelName;
  final Duration timeout;
  
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const String _generateEndpoint = '/api/generate';
  static const String _tagsEndpoint = '/api/tags';

  OllamaGrammarProvider({
    required this.ollamaUrl,
    required this.modelName,
    this.timeout = _defaultTimeout,
  }) {
    // Enhanced initialization logging
    debugPrint('=== OllamaGrammarProvider Initialization ===');
    debugPrint('OllamaGrammarProvider: URL: $ollamaUrl');
    debugPrint('OllamaGrammarProvider: Model: $modelName');
    debugPrint('OllamaGrammarProvider: Timeout: ${timeout.inSeconds}s');
    debugPrint('OllamaGrammarProvider: Platform: ${Platform.operatingSystem}');
    debugPrint('OllamaGrammarProvider: Tags endpoint: $ollamaUrl$_tagsEndpoint');
    debugPrint('OllamaGrammarProvider: Generate endpoint: $ollamaUrl$_generateEndpoint');
    debugPrint('=== End Initialization ===');
  }

  @override
  String get providerName => 'Ollama $modelName GEC';

  /// Check if Ollama server is reachable and model is available
  Future<bool> isServerHealthy() async {
    try {
      debugPrint('=== Ollama Health Check Start ===');
      debugPrint('OllamaGrammarProvider: Checking Ollama health at $ollamaUrl');
      debugPrint('OllamaGrammarProvider: Looking for model: $modelName');
      
      final uri = Uri.parse('$ollamaUrl$_tagsEndpoint');
      debugPrint('OllamaGrammarProvider: Full health check URL: $uri');
      debugPrint('OllamaGrammarProvider: URI host: ${uri.host}, port: ${uri.port}, scheme: ${uri.scheme}');
      debugPrint('OllamaGrammarProvider: URI path: ${uri.path}');
      
      // Check if URL is properly formatted
      if (uri.host.isEmpty) {
        debugPrint('OllamaGrammarProvider: ERROR - Invalid URL format: $ollamaUrl');
        return false;
      }
      
      debugPrint('OllamaGrammarProvider: Starting HTTP GET request...');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'DictationApp/1.0',
        },
      ).timeout(Duration(seconds: 10)); // Increased timeout for mobile
      
      debugPrint('OllamaGrammarProvider: Health check response status: ${response.statusCode}');
      debugPrint('OllamaGrammarProvider: Health check response headers: ${response.headers}');
      debugPrint('OllamaGrammarProvider: Health check response body length: ${response.body.length}');
      debugPrint('OllamaGrammarProvider: Health check response body: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          debugPrint('OllamaGrammarProvider: Successfully parsed JSON response');
          debugPrint('OllamaGrammarProvider: Response data keys: ${data.keys}');
          
          final models = data['models'] as List?;
          if (models != null) {
            debugPrint('OllamaGrammarProvider: Found ${models.length} models');
            for (int i = 0; i < models.length; i++) {
              final model = models[i];
              final modelName = model['name']?.toString() ?? 'Unknown';
              debugPrint('OllamaGrammarProvider: Model $i: $modelName');
            }
            
            final hasModel = models.any((model) {
              final name = model['name']?.toString() ?? '';
              final match = name.contains(modelName);
              debugPrint('OllamaGrammarProvider: Checking model "$name" contains "$modelName": $match');
              return match;
            });
            
            debugPrint('OllamaGrammarProvider: Model $modelName available: $hasModel');
            debugPrint('=== Ollama Health Check End: SUCCESS ===');
            return hasModel;
          } else {
            debugPrint('OllamaGrammarProvider: ERROR - No models field in response');
            return false;
          }
        } catch (jsonError) {
          debugPrint('OllamaGrammarProvider: ERROR - Failed to parse JSON: $jsonError');
          debugPrint('OllamaGrammarProvider: Raw response: ${response.body}');
          return false;
        }
      }
      
      debugPrint('OllamaGrammarProvider: Ollama health check failed with status ${response.statusCode}');
      debugPrint('=== Ollama Health Check End: FAILED ===');
      return false;
      
    } on SocketException catch (e) {
      debugPrint('OllamaGrammarProvider: SocketException - Network connectivity issue: $e');
      debugPrint('OllamaGrammarProvider: Error details: ${e.osError}');
      debugPrint('OllamaGrammarProvider: This usually means Ollama server is not running or not accessible');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('OllamaGrammarProvider: TimeoutException - Server took too long to respond: $e');
      debugPrint('OllamaGrammarProvider: Try increasing timeout or check server performance');
      return false;
    } on FormatException catch (e) {
      debugPrint('OllamaGrammarProvider: FormatException - Invalid URL format: $e');
      debugPrint('OllamaGrammarProvider: Check if URL is properly formatted: $ollamaUrl');
      return false;
    } catch (e) {
      debugPrint('OllamaGrammarProvider: Unexpected error during health check: $e');
      debugPrint('OllamaGrammarProvider: Error type: ${e.runtimeType}');
      debugPrint('OllamaGrammarProvider: Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('=== Ollama Text Correction Start ===');
    debugPrint('OllamaGrammarProvider: Starting Ollama correction');
    debugPrint('OllamaGrammarProvider: Text length: ${text.length}');
    debugPrint('OllamaGrammarProvider: Text preview: "${text.length > 100 ? text.substring(0, 100) + '...' : text}"');
    debugPrint('OllamaGrammarProvider: Using model: $modelName');
    debugPrint('OllamaGrammarProvider: Server URL: $ollamaUrl');
    
    if (text.trim().isEmpty) {
      debugPrint('OllamaGrammarProvider: Empty text provided, returning as-is');
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 1.0,
        errors: [],
        correctionMethod: providerName,
      );
    }

    try {
      final correctedText = await _performOllamaCorrection(text);
      final confidence = _calculateConfidence(text, correctedText);
      final errors = _generateErrorsFromDifference(text, correctedText);

      debugPrint('OllamaGrammarProvider: Ollama correction completed successfully');
      debugPrint('OllamaGrammarProvider: Original: "$text"');
      debugPrint('OllamaGrammarProvider: Corrected: "$correctedText"');
      debugPrint('OllamaGrammarProvider: Confidence: $confidence');
      debugPrint('OllamaGrammarProvider: Found ${errors.length} errors');
      debugPrint('=== Ollama Text Correction End: SUCCESS ===');

      return GrammarCorrectionResult(
        originalText: text,
        correctedText: correctedText,
        confidence: confidence,
        errors: errors,
        correctionMethod: providerName,
      );
      
    } catch (e) {
      debugPrint('OllamaGrammarProvider: Ollama correction failed: $e');
      debugPrint('OllamaGrammarProvider: Error type: ${e.runtimeType}');
      debugPrint('=== Ollama Text Correction End: FAILED ===');
      rethrow; // Let the hybrid service handle the fallback
    }
  }

  /// Perform the actual Ollama correction
  Future<String> _performOllamaCorrection(String text) async {
    debugPrint('=== Ollama Correction Request Start ===');
    final uri = Uri.parse('$ollamaUrl$_generateEndpoint');
    debugPrint('OllamaGrammarProvider: POST URL: $uri');
    
    final prompt = '''Prüfe die Rechtschreibung, Grammatik und die Wörter von dem folgenden deutschen Satz und korrigiere alle Fehler. Gib nur den korrigierten Satz zurück, ohne weitere Erklärungen oder Kommentare:

"$text"

Korrigierter Satz:''';

    final requestData = {
      'model': modelName,
      'prompt': prompt,
      'stream': false,
      'options': {
        'temperature': 0.1, // Low temperature for consistent corrections
        'top_p': 0.9,
        'num_predict': 256, // Changed from max_tokens to num_predict for Ollama
      },
    };

    final requestBody = json.encode(requestData);

    debugPrint('OllamaGrammarProvider: Request model: $modelName');
    debugPrint('OllamaGrammarProvider: Request prompt preview: "${prompt.length > 200 ? prompt.substring(0, 200) + '...' : prompt}"');
    debugPrint('OllamaGrammarProvider: Request body size: ${requestBody.length} bytes');
    debugPrint('OllamaGrammarProvider: Full request body: $requestBody');
    
    try {
      debugPrint('OllamaGrammarProvider: Sending POST request...');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'DictationApp/1.0',
        },
        body: requestBody,
      ).timeout(timeout);

      debugPrint('OllamaGrammarProvider: POST response status: ${response.statusCode}');
      debugPrint('OllamaGrammarProvider: POST response headers: ${response.headers}');
      debugPrint('OllamaGrammarProvider: POST response body length: ${response.body.length}');
      debugPrint('OllamaGrammarProvider: POST response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);
          debugPrint('OllamaGrammarProvider: Successfully parsed response JSON');
          debugPrint('OllamaGrammarProvider: Response keys: ${responseData.keys}');
          
          String correctedText = responseData['response']?.toString().trim() ?? text;
          debugPrint('OllamaGrammarProvider: Raw response text: "$correctedText"');
          
          // Clean up the response to extract just the corrected sentence
          correctedText = _cleanOllamaResponse(correctedText, text);
          debugPrint('OllamaGrammarProvider: Cleaned response text: "$correctedText"');
          debugPrint('=== Ollama Correction Request End: SUCCESS ===');
          
          return correctedText;
        } catch (jsonError) {
          debugPrint('OllamaGrammarProvider: ERROR - Failed to parse response JSON: $jsonError');
          debugPrint('OllamaGrammarProvider: Raw response: ${response.body}');
          throw Exception('Failed to parse Ollama response: $jsonError');
        }
      } else {
        debugPrint('OllamaGrammarProvider: ERROR - Server returned status ${response.statusCode}');
        debugPrint('OllamaGrammarProvider: Error response: ${response.body}');
        throw Exception('Ollama server returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('OllamaGrammarProvider: ERROR in _performOllamaCorrection: $e');
      debugPrint('=== Ollama Correction Request End: FAILED ===');
      rethrow;
    }
  }

  /// Clean up Ollama response to extract the corrected text
  String _cleanOllamaResponse(String response, String originalText) {
    // Remove common prefixes that Ollama might add
    final cleanPatterns = [
      r'Korrigierter Satz:\s*',
      r'Korrigiert:\s*',
      r'Antwort:\s*',
      r'Korrekt:\s*',
      r'"([^"]*)"', // Extract text from quotes
    ];
    
    String cleaned = response.trim();
    
    for (String pattern in cleanPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      final match = regex.firstMatch(cleaned);
      if (match != null) {
        if (match.groupCount > 0 && match.group(1) != null) {
          // If there's a capture group (quotes), use that
          cleaned = match.group(1)!.trim();
        } else {
          // Otherwise, remove the matched prefix
          cleaned = cleaned.replaceFirst(regex, '').trim();
        }
        break;
      }
    }
    
    // If the cleaned response is empty or looks wrong, return original
    if (cleaned.isEmpty || cleaned.length < originalText.length * 0.3) {
      return originalText;
    }
    
    // Remove quotes if they wrap the entire response
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    
    return cleaned;
  }

  /// Calculate confidence based on text changes
  double _calculateConfidence(String original, String corrected) {
    if (original == corrected) return 1.0;
    
    // Simple confidence calculation based on similarity
    final originalWords = original.toLowerCase().split(' ');
    final correctedWords = corrected.toLowerCase().split(' ');
    
    int matchingWords = 0;
    final minLength = originalWords.length < correctedWords.length 
        ? originalWords.length 
        : correctedWords.length;
    
    for (int i = 0; i < minLength; i++) {
      if (originalWords[i] == correctedWords[i]) {
        matchingWords++;
      }
    }
    
    // High confidence for Ollama corrections
    return 0.85 + (matchingWords / originalWords.length) * 0.15;
  }

  /// Generate grammar errors by comparing original and corrected text
  List<GrammarError> _generateErrorsFromDifference(String original, String corrected) {
    if (original == corrected) return [];
    
    final originalWords = original.split(' ');
    final correctedWords = corrected.split(' ');
    
    List<GrammarError> errors = [];
    int offset = 0;
    
    for (int i = 0; i < originalWords.length && i < correctedWords.length; i++) {
      if (originalWords[i] != correctedWords[i]) {
        errors.add(GrammarError(
          offset: offset,
          length: originalWords[i].length,
          message: 'Ollama AI grammar correction applied',
          category: 'Grammar/Spelling',
          replacements: [correctedWords[i]],
          ruleId: 'ollama_ai_correction',
        ));
      }
      offset += originalWords[i].length + 1; // +1 for space
    }
    
    return errors;
  }

  @override
  void dispose() {
    debugPrint('OllamaGrammarProvider: Disposed');
    // HTTP client is stateless, nothing to dispose
  }
} 