import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dictation_app/core/services/ai_grammar_service.dart';

/// Online grammar correction provider that communicates with FastAPI server
class OnlineGrammarProvider implements GrammarCorrectionProvider {
  final String serverUrl;
  final Duration timeout;
  
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const String _correctEndpoint = '/api/v1/correct';
  static const String _healthEndpoint = '/api/v1/health';

  OnlineGrammarProvider({
    required this.serverUrl,
    this.timeout = _defaultTimeout,
  });

  @override
  String get providerName => 'Online mT5 GEC Server';

  /// Check if the server is reachable and healthy
  Future<bool> isServerHealthy() async {
    try {
      debugPrint('OnlineGrammarProvider: Checking server health at $serverUrl');
      
      final uri = Uri.parse('$serverUrl$_healthEndpoint');
      debugPrint('OnlineGrammarProvider: Full health check URL: $uri');
      debugPrint('OnlineGrammarProvider: URI host: ${uri.host}, port: ${uri.port}, scheme: ${uri.scheme}');
      
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5)); // Shorter timeout for health check
      
      debugPrint('OnlineGrammarProvider: Health check response status: ${response.statusCode}');
      debugPrint('OnlineGrammarProvider: Health check response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isHealthy = data['status'] == 'healthy' && data['model_loaded'] == true;
        debugPrint('OnlineGrammarProvider: Server health check result: $isHealthy');
        return isHealthy;
      }
      
      debugPrint('OnlineGrammarProvider: Server health check failed with status ${response.statusCode}');
      return false;
      
    } on SocketException catch (e) {
      debugPrint('OnlineGrammarProvider: SocketException - Network connectivity issue: $e');
      debugPrint('OnlineGrammarProvider: Error details: ${e.osError}');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('OnlineGrammarProvider: TimeoutException - Server took too long to respond: $e');
      return false;
    } on FormatException catch (e) {
      debugPrint('OnlineGrammarProvider: FormatException - Invalid URL format: $e');
      return false;
    } catch (e) {
      debugPrint('OnlineGrammarProvider: Unexpected error during health check: $e');
      debugPrint('OnlineGrammarProvider: Error type: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('OnlineGrammarProvider: Starting online correction for text: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
    
    if (text.trim().isEmpty) {
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 1.0,
        errors: [],
        correctionMethod: providerName,
      );
    }

    try {
      final correctedText = await _performOnlineCorrection(text);
      final confidence = _calculateConfidence(text, correctedText);
      final errors = _generateErrorsFromDifference(text, correctedText);

      debugPrint('OnlineGrammarProvider: Online correction completed successfully');
      debugPrint('OnlineGrammarProvider: Original: "$text"');
      debugPrint('OnlineGrammarProvider: Corrected: "$correctedText"');
      debugPrint('OnlineGrammarProvider: Confidence: $confidence');

      return GrammarCorrectionResult(
        originalText: text,
        correctedText: correctedText,
        confidence: confidence,
        errors: errors,
        correctionMethod: providerName,
      );
      
    } catch (e) {
      debugPrint('OnlineGrammarProvider: Online correction failed: $e');
      rethrow; // Let the hybrid service handle the fallback
    }
  }

  /// Perform the actual online correction
  Future<String> _performOnlineCorrection(String text) async {
    final uri = Uri.parse('$serverUrl$_correctEndpoint');
    
    // Increase max_length to handle longer texts properly
    final maxLength = text.length > 200 ? text.length + 50 : 512;
    
    final requestBody = json.encode({
      'text': text,
      'max_length': maxLength,
    });

    debugPrint('OnlineGrammarProvider: Sending request to $uri');
    debugPrint('OnlineGrammarProvider: Original text length: ${text.length}');
    debugPrint('OnlineGrammarProvider: Using max_length: $maxLength');
    debugPrint('OnlineGrammarProvider: Request body: $requestBody');
    
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: requestBody,
    ).timeout(timeout);

    debugPrint('OnlineGrammarProvider: POST response status: ${response.statusCode}');
    debugPrint('OnlineGrammarProvider: POST response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final correctedText = data['corrected_text'] as String? ?? text;
      
      debugPrint('OnlineGrammarProvider: Server response successful');
      debugPrint('OnlineGrammarProvider: Processing time: ${data['processing_time']}s');
      debugPrint('OnlineGrammarProvider: Corrected text length: ${correctedText.length}');
      
      return correctedText.trim();
      
    } else {
      final errorMessage = 'Server error: ${response.statusCode} - ${response.body}';
      debugPrint('OnlineGrammarProvider: $errorMessage');
      throw Exception(errorMessage);
    }
  }

  /// Calculate confidence based on the amount of changes made
  double _calculateConfidence(String original, String corrected) {
    if (original == corrected) {
      return 1.0; // Perfect confidence if no changes
    }
    
    final originalWords = original.split(' ');
    final correctedWords = corrected.split(' ');
    
    // Calculate similarity ratio
    final maxLength = originalWords.length > correctedWords.length 
        ? originalWords.length 
        : correctedWords.length;
    
    if (maxLength == 0) return 1.0;
    
    int matchingWords = 0;
    final minLength = originalWords.length < correctedWords.length 
        ? originalWords.length 
        : correctedWords.length;
    
    for (int i = 0; i < minLength; i++) {
      if (originalWords[i].toLowerCase() == correctedWords[i].toLowerCase()) {
        matchingWords++;
      }
    }
    
    // Base confidence on word similarity, but give credit for corrections
    final similarity = matchingWords / maxLength;
    return 0.8 + (similarity * 0.2); // Online corrections get high confidence (0.8-1.0)
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
          message: 'Online grammar correction applied',
          category: 'Grammar',
          replacements: [correctedWords[i]],
          ruleId: 'online_gec_correction',
        ));
      }
      offset += originalWords[i].length + 1; // +1 for space
    }
    
    return errors;
  }

  @override
  void dispose() {
    debugPrint('OnlineGrammarProvider: Disposed');
    // HTTP client is stateless, nothing to dispose
  }
} 