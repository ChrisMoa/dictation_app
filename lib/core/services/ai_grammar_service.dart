import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';

/// Abstract interface for grammar correction providers
abstract class GrammarCorrectionProvider {
  Future<GrammarCorrectionResult> correctText(String text);
  String get providerName;
}

/// SpaCy Mobile Model implementation using TensorFlow Lite
class SpacyProvider implements GrammarCorrectionProvider {
  static const String _modelPath = 'assets/ml/spacy_grammar_model.tflite';
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Model input/output specifications
  static const int _maxSequenceLength = 128;  // Maximum sentence length
  static const int _vocabSize = 50000;        // Vocabulary size
  static const int _embeddingDim = 300;       // Word embedding dimension

  @override
  String get providerName => 'SpaCy Mobile';

  Future<void> _initializeModel() async {
    if (_isInitialized) return;

    try {
      final interpreter = await Interpreter.fromAsset(_modelPath);
      _interpreter = interpreter;
      _isInitialized = true;
      debugPrint('SpacyProvider: Model initialized successfully');
    } catch (e) {
      debugPrint('SpacyProvider: Error initializing model: $e');
      rethrow;
    }
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    if (!_isInitialized) {
      await _initializeModel();
    }

    try {
      // Split text into sentences for processing
      final sentences = _splitIntoSentences(text);
      List<GrammarError> allErrors = [];
      String correctedText = '';
      double totalConfidence = 0.0;

      for (final sentence in sentences) {
        if (sentence.trim().isEmpty) continue;

        // Process each sentence
        final result = await _processSentence(sentence);
        allErrors.addAll(result.errors);
        
        // Adjust error offsets for the full text
        final adjustedErrors = result.errors.map((error) {
          return GrammarError(
            offset: error.offset + correctedText.length,
            length: error.length,
            message: error.message,
            category: error.category,
            replacements: error.replacements,
            ruleId: error.ruleId,
          );
        }).toList();
        
        allErrors.addAll(adjustedErrors);
        correctedText += result.correctedText;
        totalConfidence += result.confidence;

        // Add space between sentences if needed
        if (correctedText.isNotEmpty && !correctedText.endsWith(' ') && 
            !sentence.startsWith(' ')) {
          correctedText += ' ';
        }
      }

      final averageConfidence = sentences.isNotEmpty ? 
          totalConfidence / sentences.length : 1.0;

      return GrammarCorrectionResult(
        originalText: text,
        correctedText: correctedText.trim(),
        confidence: averageConfidence,
        errors: allErrors,
        correctionMethod: 'SpaCy Mobile',
      );
    } catch (e) {
      debugPrint('SpacyProvider: Error during correction: $e');
      rethrow;
    }
  }

  Future<GrammarCorrectionResult> _processSentence(String sentence) async {
    // Prepare input tensor for the model
    final inputShape = [1, _maxSequenceLength];  // Batch size 1, sequence length
    final inputBuffer = Float32List(_maxSequenceLength);
    
    // Tokenize and encode the sentence
    final tokens = _tokenize(sentence);
    final encodedTokens = _encodeTokens(tokens);
    
    // Fill input buffer with token encodings
    for (int i = 0; i < encodedTokens.length && i < _maxSequenceLength; i++) {
      inputBuffer[i] = encodedTokens[i].toDouble();
    }

    // Prepare output tensors
    final outputShape = [1, _maxSequenceLength, 2];  // [batch, sequence, [correct, incorrect]]
    final outputBuffer = Float32List(_maxSequenceLength * 2);

    // Run inference
    _interpreter?.run(inputBuffer.buffer, outputBuffer.buffer);

    // Process model output
    final corrections = _processModelOutput(tokens, outputBuffer);
    
    // Apply corrections and collect errors
    String correctedText = sentence;
    List<GrammarError> errors = [];
    int offset = 0;

    for (final correction in corrections) {
      if (correction.needsCorrection) {
        final error = GrammarError(
          offset: correction.offset + offset,
          length: correction.length,
          message: correction.message,
          category: correction.category,
          replacements: correction.suggestions,
          ruleId: 'spacy_grammar',
        );
        errors.add(error);

        if (correction.suggestions.isNotEmpty) {
          final bestSuggestion = correction.suggestions.first;
          final start = error.offset;
          final end = start + error.length;
          
          if (start >= 0 && end <= correctedText.length) {
            correctedText = correctedText.substring(0, start) + 
                          bestSuggestion + 
                          correctedText.substring(end);
            
            // Update offset for subsequent corrections
            offset += bestSuggestion.length - error.length;
          }
        }
      }
    }

    // Calculate confidence based on number of corrections
    final confidence = _calculateConfidence(errors.length, tokens.length);

    return GrammarCorrectionResult(
      originalText: sentence,
      correctedText: correctedText,
      confidence: confidence,
      errors: errors,
      correctionMethod: 'SpaCy Mobile',
    );
  }

  List<String> _splitIntoSentences(String text) {
    // Split text into sentences using German sentence boundaries
    final sentenceEndings = RegExp(r'[.!?]+');
    return text.split(sentenceEndings)
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
  }

  List<String> _tokenize(String text) {
    // Basic tokenization - in production, use a proper German tokenizer
    return text.split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  List<int> _encodeTokens(List<String> tokens) {
    // Convert tokens to numerical encodings
    // In production, use a proper vocabulary mapping
    return tokens.map((token) {
      // Simple hash-based encoding for demonstration
      return token.codeUnits.fold(0, (sum, code) => sum + code) % _vocabSize;
    }).toList();
  }

  List<Correction> _processModelOutput(List<String> tokens, Float32List outputBuffer) {
    List<Correction> corrections = [];
    
    for (int i = 0; i < tokens.length; i++) {
      final correctProb = outputBuffer[i * 2];
      final incorrectProb = outputBuffer[i * 2 + 1];
      
      if (incorrectProb > 0.7) {  // Threshold for considering a token incorrect
        final token = tokens[i];
        final suggestions = _getSuggestions(token, tokens, i);
        
        corrections.add(Correction(
          offset: _getTokenOffset(tokens, i),
          length: token.length,
          needsCorrection: true,
          message: 'Possible grammar error detected',
          category: _determineErrorCategory(token, tokens, i),
          suggestions: suggestions,
        ));
      }
    }
    
    return corrections;
  }

  int _getTokenOffset(List<String> tokens, int index) {
    int offset = 0;
    for (int i = 0; i < index; i++) {
      offset += tokens[i].length + 1;  // +1 for space
    }
    return offset;
  }

  String _determineErrorCategory(String token, List<String> context, int position) {
    // Determine error category based on token and context
    if (position == 0 && token[0].toLowerCase() == token[0]) {
      return 'Capitalization';
    }
    
    // Add more sophisticated category detection based on context
    return 'Grammar';
  }

  List<String> _getSuggestions(String token, List<String> context, int position) {
    // Get context-aware suggestions based on the token and its context
    final suggestions = <String>[];
    
    // Capitalization correction
    if (position == 0 && token[0].toLowerCase() == token[0]) {
      suggestions.add(token[0].toUpperCase() + token.substring(1));
    }
    
    // Common German verb corrections
    if (_isVerb(token)) {
      suggestions.addAll(_getVerbSuggestions(token, context, position));
    }
    
    // Common German noun corrections
    if (_isNoun(token)) {
      suggestions.addAll(_getNounSuggestions(token, context, position));
    }
    
    // If no specific suggestions, return the original token
    if (suggestions.isEmpty) {
      suggestions.add(token);
    }
    
    return suggestions;
  }

  bool _isVerb(String token) {
    // Simple verb detection - in production, use proper POS tagging
    final commonVerbs = ['ist', 'wird', 'hat', 'haben', 'gehen', 'kommen'];
    return commonVerbs.contains(token.toLowerCase());
  }

  bool _isNoun(String token) {
    // Simple noun detection - in production, use proper POS tagging
    final commonNouns = ['hund', 'katze', 'haus', 'stadt', 'park'];
    return commonNouns.contains(token.toLowerCase());
  }

  List<String> _getVerbSuggestions(String token, List<String> context, int position) {
    // Get context-aware verb suggestions
    final suggestions = <String>[];
    
    // Example verb corrections
    if (token.toLowerCase() == 'gehen' && position > 0 && 
        context[position - 1].toLowerCase() == 'ich') {
      suggestions.add('gehe');
    }
    
    return suggestions;
  }

  List<String> _getNounSuggestions(String token, List<String> context, int position) {
    // Get context-aware noun suggestions
    final suggestions = <String>[];
    
    // Capitalize nouns
    if (token[0].toLowerCase() == token[0]) {
      suggestions.add(token[0].toUpperCase() + token.substring(1));
    }
    
    return suggestions;
  }

  double _calculateConfidence(int errorCount, int tokenCount) {
    if (tokenCount == 0) return 1.0;
    final errorRatio = errorCount / tokenCount;
    return (1.0 - errorRatio).clamp(0.0, 1.0);
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}

/// Represents a single correction suggestion
class Correction {
  final int offset;
  final int length;
  final bool needsCorrection;
  final String message;
  final String category;
  final List<String> suggestions;

  Correction({
    required this.offset,
    required this.length,
    required this.needsCorrection,
    required this.message,
    required this.category,
    required this.suggestions,
  });
}

/// Local fallback implementation using basic rules
class LocalFallbackProvider implements GrammarCorrectionProvider {
  @override
  String get providerName => 'Local Fallback';

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('AIGrammarService: Using fallback local correction');
    
    // Apply basic German grammar rules
    String corrected = text.trim();
    
    // Capitalize first letter
    if (corrected.isNotEmpty) {
      corrected = corrected[0].toUpperCase() + corrected.substring(1);
    }
    
    // Basic German corrections
    corrected = corrected.replaceAll(RegExp(r'\bwird es (\w+)te ist\b'), 'wird \$1');
    corrected = corrected.replaceAll(RegExp(r'\bkeine Ahnung ob\b'), 'Keine Ahnung, ob');
    corrected = corrected.replaceAll(RegExp(r'\boder nicht\b'), 'oder nicht.');
    
    return GrammarCorrectionResult(
      originalText: text,
      correctedText: corrected,
      confidence: 0.7,
      errors: [],
      correctionMethod: 'Local Fallback',
    );
  }
}

/// Main service class that can use different providers
class AIGrammarService {
  static final AIGrammarService _instance = AIGrammarService._internal();
  factory AIGrammarService() => _instance;
  AIGrammarService._internal();

  GrammarCorrectionProvider _currentProvider = SpacyProvider();
  
  /// Set the grammar correction provider to use
  void setProvider(GrammarCorrectionProvider provider) {
    _currentProvider = provider;
  }

  /// Get the current provider name
  String get currentProviderName => _currentProvider.providerName;

  /// Corrects German text using the current provider
  Future<GrammarCorrectionResult> correctGermanText(String text) async {
    debugPrint('AIGrammarService: Starting grammar correction with ${_currentProvider.providerName}');
    
    // Check if text is too long for optimal processing
    if (text.length > 300 || text.split(' ').length > 50) {
      debugPrint('AIGrammarService: Text is very long (${text.split(' ').length} words), using segmented processing');
      return await _processLongTextInSegments(text);
    }
    
    try {
      return await _currentProvider.correctText(text);
    } catch (e) {
      debugPrint('AIGrammarService: Error with ${_currentProvider.providerName}, falling back to local correction');
      return await LocalFallbackProvider().correctText(text);
    }
  }

  /// Process very long texts by intelligently segmenting them
  Future<GrammarCorrectionResult> _processLongTextInSegments(String text) async {
    debugPrint('AIGrammarService: Segmenting long text for optimal processing');
    
    // Split text into intelligent segments
    final segments = _intelligentTextSegmentation(text);
    debugPrint('AIGrammarService: Split into ${segments.length} segments');
    
    List<GrammarError> allErrors = [];
    String correctedText = '';
    double totalConfidence = 0.0;
    int processedSegments = 0;
    
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      debugPrint('AIGrammarService: Processing segment ${i + 1}/${segments.length}: "${segment.substring(0, segment.length > 50 ? 50 : segment.length)}..."');
      
      try {
        // Process each segment individually using direct API call
        final segmentResult = await _currentProvider.correctText(segment);
        
        // Adjust error positions for the full text
        final adjustedErrors = segmentResult.errors.map((error) {
          return GrammarError(
            offset: error.offset + correctedText.length,
            length: error.length,
            message: error.message,
            category: error.category,
            replacements: error.replacements,
            ruleId: error.ruleId,
          );
        }).toList();
        
        allErrors.addAll(adjustedErrors);
        correctedText += segmentResult.correctedText;
        totalConfidence += segmentResult.confidence;
        processedSegments++;
        
        // Add space between segments if needed
        if (i < segments.length - 1 && !correctedText.endsWith(' ') && !segments[i + 1].startsWith(' ')) {
          correctedText += ' ';
        }
        
        // Small delay to avoid overwhelming the API
        await Future.delayed(Duration(milliseconds: 200));
        
      } catch (e) {
        debugPrint('AIGrammarService: Error processing segment ${i + 1}: $e');
        // Add segment as-is if processing fails
        correctedText += segment;
        if (i < segments.length - 1) correctedText += ' ';
        processedSegments++;
      }
    }
    
    final averageConfidence = processedSegments > 0 ? totalConfidence / processedSegments : 0.7;
    
    debugPrint('AIGrammarService: Segmented processing completed');
    debugPrint('AIGrammarService: Total errors found: ${allErrors.length}');
    debugPrint('AIGrammarService: Average confidence: $averageConfidence');
    
    return GrammarCorrectionResult(
      originalText: text,
      correctedText: correctedText.trim(),
      confidence: averageConfidence,
      errors: allErrors,
      correctionMethod: '${_currentProvider.providerName} (Segmented)',
    );
  }

  /// Intelligently segment text at natural break points
  List<String> _intelligentTextSegmentation(String text) {
    List<String> segments = [];
    
    // First, try to split at sentence boundaries
    final sentences = text.split(RegExp(r'[.!?]+\s+'));
    
    if (sentences.length > 1) {
      // Group sentences into segments of reasonable length
      String currentSegment = '';
      
      for (final sentence in sentences) {
        if (currentSegment.isEmpty) {
          currentSegment = sentence;
        } else if ((currentSegment + ' ' + sentence).split(' ').length <= 40) {
          currentSegment += '. ' + sentence;
        } else {
          segments.add(currentSegment.trim());
          currentSegment = sentence;
        }
      }
      
      if (currentSegment.isNotEmpty) {
        segments.add(currentSegment.trim());
      }
    } else {
      // No clear sentence boundaries, split at clause boundaries
      segments = _splitAtClauseBoundaries(text);
    }
    
    // Ensure no segment is too long
    List<String> finalSegments = [];
    for (final segment in segments) {
      if (segment.split(' ').length > 50) {
        finalSegments.addAll(_splitLongSegment(segment));
      } else {
        finalSegments.add(segment);
      }
    }
    
    return finalSegments.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Split at German clause boundaries (conjunctions, relative pronouns)
  List<String> _splitAtClauseBoundaries(String text) {
    final clauseMarkers = [
      ' aber ', ' und ', ' oder ', ' denn ', ' sondern ',
      ' weil ', ' da ', ' obwohl ', ' wenn ', ' falls ',
      ' dass ', ' damit ', ' so dass ', ' nachdem ', ' bevor ',
      ' während ', ' seit ', ' bis ', ' als ', ' wie '
    ];
    
    List<String> segments = [text];
    
    for (final marker in clauseMarkers) {
      List<String> newSegments = [];
      
      for (final segment in segments) {
        if (segment.split(' ').length > 30 && segment.contains(marker)) {
          final parts = segment.split(marker);
          if (parts.length > 1) {
            newSegments.add(parts[0].trim());
            for (int i = 1; i < parts.length; i++) {
              newSegments.add((marker.trim() + ' ' + parts[i]).trim());
            }
          } else {
            newSegments.add(segment);
          }
        } else {
          newSegments.add(segment);
        }
      }
      
      segments = newSegments;
    }
    
    return segments;
  }

  /// Split very long segments at word boundaries
  List<String> _splitLongSegment(String segment) {
    final words = segment.split(' ');
    List<String> segments = [];
    
    for (int i = 0; i < words.length; i += 40) {
      final endIndex = (i + 40 < words.length) ? i + 40 : words.length;
      segments.add(words.sublist(i, endIndex).join(' '));
    }
    
    return segments;
  }
}

/// Result of AI grammar correction
class GrammarCorrectionResult {
  final String originalText;
  final String correctedText;
  final double confidence;
  final List<GrammarError> errors;
  final String correctionMethod;

  GrammarCorrectionResult({
    required this.originalText,
    required this.correctedText,
    required this.confidence,
    required this.errors,
    required this.correctionMethod,
  });

  bool get hasCorrections => originalText != correctedText;
}

/// Grammar error detected by AI
class GrammarError {
  final int offset;
  final int length;
  final String message;
  final String category;
  final List<String> replacements;
  final String ruleId;

  GrammarError({
    required this.offset,
    required this.length,
    required this.message,
    required this.category,
    required this.replacements,
    required this.ruleId,
  });

  factory GrammarError.fromLanguageTool(Map<String, dynamic> match, int offsetAdjustment) {
    final replacements = (match['replacements'] as List<dynamic>?)
        ?.map((r) => r['value'] as String)
        .toList() ?? [];

    return GrammarError(
      offset: (match['offset'] as int) + offsetAdjustment,
      length: match['length'] as int,
      message: match['message'] as String,
      category: match['rule']?['category']?['name'] as String? ?? 'Unknown',
      replacements: replacements,
      ruleId: match['rule']?['id'] as String? ?? 'unknown',
    );
  }
} 