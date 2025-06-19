import 'package:flutter/foundation.dart';
import '../ml/german_gec_service.dart';

/// Abstract interface for grammar correction providers
abstract class GrammarCorrectionProvider {
  Future<GrammarCorrectionResult> correctText(String text);
  String get providerName;
  void dispose();
}

/// TFLite-based German GEC provider using the optimized mT5 model
class OfflineGECProvider implements GrammarCorrectionProvider {
  final GermanGECService _gecService = GermanGECService();
  bool _isInitialized = false;

  @override
  String get providerName => 'Offline mT5 GEC';

  Future<void> _initializeIfNeeded() async {
    if (!_isInitialized) {
      await _gecService.initialize();
      _isInitialized = true;
    }
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('OfflineGECProvider: Starting grammar correction');
    
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
      await _initializeIfNeeded();
      
      // Check if text is too long for optimal processing
      if (text.length > 300 || text.split(' ').length > 40) {
        debugPrint('OfflineGECProvider: Text is long, using segmented processing');
        return await _processLongTextInSegments(text);
      }
      
      final gecResult = await _gecService.correctText(text);
      
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: gecResult.correctedText,
        confidence: gecResult.confidence,
        errors: _generateErrorsFromDifference(text, gecResult.correctedText),
        correctionMethod: '$providerName (${gecResult.inferenceTimeMs}ms)',
      );
      
    } catch (e) {
      debugPrint('OfflineGECProvider: Error during correction: $e');
      return _fallbackCorrection(text);
    }
  }

  /// Process very long texts by intelligently segmenting them
  Future<GrammarCorrectionResult> _processLongTextInSegments(String text) async {
    debugPrint('OfflineGECProvider: Segmenting long text for optimal processing');
    
    final segments = _intelligentTextSegmentation(text);
    debugPrint('OfflineGECProvider: Split into ${segments.length} segments');
    
    List<GrammarError> allErrors = [];
    String correctedText = '';
    double totalConfidence = 0.0;
    int processedSegments = 0;
    
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      debugPrint('OfflineGECProvider: Processing segment ${i + 1}/${segments.length}');
      
      try {
        final gecResult = await _gecService.correctText(segment);
        
        // Adjust error positions for the full text
        final segmentErrors = _generateErrorsFromDifference(segment, gecResult.correctedText);
        final adjustedErrors = segmentErrors.map((error) {
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
        correctedText += gecResult.correctedText;
        totalConfidence += gecResult.confidence;
        processedSegments++;
        
        // Add space between segments if needed
        if (i < segments.length - 1 && !correctedText.endsWith(' ') && !segments[i + 1].startsWith(' ')) {
          correctedText += ' ';
        }
        
        // Small delay to avoid overwhelming the model
        await Future.delayed(Duration(milliseconds: 100));
        
      } catch (e) {
        debugPrint('OfflineGECProvider: Error processing segment ${i + 1}: $e');
        // Add segment as-is if processing fails
        correctedText += segment;
        if (i < segments.length - 1) correctedText += ' ';
        processedSegments++;
      }
    }
    
    final averageConfidence = processedSegments > 0 ? totalConfidence / processedSegments : 0.7;
    
    return GrammarCorrectionResult(
      originalText: text,
      correctedText: correctedText.trim(),
      confidence: averageConfidence,
      errors: allErrors,
      correctionMethod: '$providerName (Segmented)',
    );
  }

  /// Generate grammar errors by comparing original and corrected text
  List<GrammarError> _generateErrorsFromDifference(String original, String corrected) {
    if (original == corrected) return [];
    
    // Simple difference detection - in production, use proper diff algorithm
    final originalWords = original.split(' ');
    final correctedWords = corrected.split(' ');
    
    List<GrammarError> errors = [];
    int offset = 0;
    
    for (int i = 0; i < originalWords.length && i < correctedWords.length; i++) {
      if (originalWords[i] != correctedWords[i]) {
        errors.add(GrammarError(
          offset: offset,
          length: originalWords[i].length,
          message: 'Grammar correction suggested',
          category: 'Grammar',
          replacements: [correctedWords[i]],
          ruleId: 'gec_correction',
        ));
      }
      offset += originalWords[i].length + 1; // +1 for space
    }
    
    return errors;
  }

  /// Fallback correction using basic rules
  GrammarCorrectionResult _fallbackCorrection(String text) {
    debugPrint('OfflineGECProvider: Using fallback local correction');
    
    String corrected = text.trim();
    
    // Capitalize first letter
    if (corrected.isNotEmpty) {
      corrected = corrected[0].toUpperCase() + corrected.substring(1);
    }
    
    // Basic German corrections
    corrected = corrected.replaceAll(RegExp(r'\bkeine ahnung ob\b'), 'Keine Ahnung, ob');
    corrected = corrected.replaceAll(RegExp(r'\boder nicht\b'), 'oder nicht.');
    
    return GrammarCorrectionResult(
      originalText: text,
      correctedText: corrected,
      confidence: 0.7,
      errors: _generateErrorsFromDifference(text, corrected),
      correctionMethod: 'Local Fallback',
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
        } else if ((currentSegment + ' ' + sentence).split(' ').length <= 30) {
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
      if (segment.split(' ').length > 40) {
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
        if (segment.split(' ').length > 20 && segment.contains(marker)) {
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
    
    for (int i = 0; i < words.length; i += 30) {
      final endIndex = (i + 30 < words.length) ? i + 30 : words.length;
      segments.add(words.sublist(i, endIndex).join(' '));
    }
    
    return segments;
  }

  @override
  void dispose() {
    _gecService.dispose();
    _isInitialized = false;
  }
}

/// Main service class for AI grammar correction
class AIGrammarService {
  static final AIGrammarService _instance = AIGrammarService._internal();
  factory AIGrammarService() => _instance;
  AIGrammarService._internal();

  GrammarCorrectionProvider _currentProvider = OfflineGECProvider();
  
  /// Set the grammar correction provider to use
  void setProvider(GrammarCorrectionProvider provider) {
    _currentProvider = provider;
  }

  /// Get the current provider name
  String get currentProviderName => _currentProvider.providerName;

  /// Corrects German text using the current provider
  Future<GrammarCorrectionResult> correctGermanText(String text) async {
    debugPrint('AIGrammarService: Starting grammar correction with ${_currentProvider.providerName}');
    
    if (text.trim().isEmpty) {
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 1.0,
        errors: [],
        correctionMethod: _currentProvider.providerName,
      );
    }
    
    try {
      return await _currentProvider.correctText(text);
    } catch (e) {
      debugPrint('AIGrammarService: Error with ${_currentProvider.providerName}: $e');
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 0.0,
        errors: [],
        correctionMethod: 'Error: ${e.toString()}',
      );
    }
  }

  void dispose() {
    _currentProvider.dispose();
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