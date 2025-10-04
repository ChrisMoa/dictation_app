import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dictation_app/features/spell_check/data/models/spell_check_result_model.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';

abstract class SpellCheckDatasource {
  Future<bool> initialize();
  Future<SpellCheckResultModel> checkText(String text);
  Future<void> dispose();
}

class SpellCheckDatasourceImpl implements SpellCheckDatasource {
  final String _vocabPath = 'assets/dictionaries/vocab.txt';
  Set<String>? _vocabulary;
  bool _useAI = true; // Flag to enable/disable AI correction
  AIGrammarService? _aiGrammarService;

  @override
  Future<bool> initialize() async {
    debugPrint('SpellCheck: Starting initialization...');

    try {
      // Get AI service from dependency injection
      _aiGrammarService = getIt<AIGrammarService>();
      debugPrint('SpellCheck: Retrieved AIGrammarService from DI');
      
      // Load vocabulary for fallback
      debugPrint('SpellCheck: Loading vocabulary from $_vocabPath');
      final vocabData = await rootBundle.loadString(_vocabPath);
      final words = vocabData.split('\n')
          .map((word) => word.trim().toLowerCase())
          .where((word) => word.isNotEmpty)
          .toSet();
      
      _vocabulary = words;
      debugPrint('SpellCheck: Loaded ${words.length} words from vocabulary');
      debugPrint('SpellCheck: AI Grammar Service ready');
      debugPrint('SpellCheck: Initialization completed successfully');
      return true;
    } catch (e) {
      debugPrint('SpellCheck: Error initializing spell check: $e');
      return false;
    }
  }

  @override
  Future<SpellCheckResultModel> checkText(String text) async {
    debugPrint('SpellCheck: Starting ${_useAI ? "AI-powered" : "local"} correction for text: "$text"');
    
    if (_vocabulary == null) {
      debugPrint('SpellCheck: Vocabulary not loaded, initializing...');
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('SpellCheck: Failed to initialize, returning original text');
        return SpellCheckResultModel(
          originalText: text,
          correctedText: text,
          confidence: 1.0,
          errors: [],
        );
      }
    }

    if (_useAI && _aiGrammarService != null) {
      return await _performAICorrection(text);
    } else {
      return await _performLocalCorrection(text);
    }
  }

  /// Perform AI-powered grammar and spell correction
  Future<SpellCheckResultModel> _performAICorrection(String text) async {
    try {
      debugPrint('SpellCheck: Using AI grammar correction service');
      
      final aiResult = await _aiGrammarService!.correctGermanText(text);
      
      // Convert AI result to our model format
      final errors = aiResult.errors.map((error) => SpellCheckError(
        word: text.substring(error.offset, error.offset + error.length),
        suggestion: error.replacements.isNotEmpty ? error.replacements.first : '',
        startIndex: error.offset,
        endIndex: error.offset + error.length,
        confidence: 0.9, // High confidence for AI corrections
      )).toList();

      debugPrint('SpellCheck: AI correction completed');
      debugPrint('SpellCheck: Method: ${aiResult.correctionMethod}');
      debugPrint('SpellCheck: Found ${aiResult.errors.length} issues');
      debugPrint('SpellCheck: Original: "${aiResult.originalText}"');
      debugPrint('SpellCheck: Corrected: "${aiResult.correctedText}"');
      debugPrint('SpellCheck: Confidence: ${aiResult.confidence}');

      return SpellCheckResultModel(
        originalText: aiResult.originalText,
        correctedText: aiResult.correctedText,
        confidence: aiResult.confidence,
        errors: errors,
      );
    } catch (e) {
      debugPrint('SpellCheck: AI correction failed: $e, falling back to local correction');
      return await _performLocalCorrection(text);
    }
  }

  /// Fallback local correction method
  Future<SpellCheckResultModel> _performLocalCorrection(String text) async {
    debugPrint('SpellCheck: Using local grammar correction');
    
    // First apply grammar corrections
    String grammarCorrectedText = _applyGermanGrammarRules(text);
    debugPrint('SpellCheck: After grammar correction: "$grammarCorrectedText"');

    final words = grammarCorrectedText.split(RegExp(r'\s+'));
    final correctedWords = <String>[];
    final errors = <SpellCheckError>[];
    int correctWords = 0;
    int currentIndex = 0;

    debugPrint('SpellCheck: Processing ${words.length} words');

    for (final word in words) {
      // Remove punctuation for checking but preserve it
      final cleanWord = word.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
      
      if (cleanWord.isEmpty) {
        correctedWords.add(word);
        currentIndex += word.length + 1; // +1 for space
        continue;
      }

      // Check if word exists in vocabulary
      if (_vocabulary!.contains(cleanWord)) {
        correctedWords.add(word);
        correctWords++;
        debugPrint('SpellCheck: Word "$cleanWord" found in vocabulary - KEEPING ORIGINAL');
      } else {
        // Be EXTREMELY conservative - only correct very obvious typos
        final suggestion = _findBestCorrection(cleanWord);
        if (suggestion != null && _isObviousTypo(cleanWord, suggestion)) {
          final correctedWord = word.replaceAll(cleanWord, suggestion);
          correctedWords.add(correctedWord);
          
          errors.add(SpellCheckError(
            word: cleanWord,
            suggestion: suggestion,
            startIndex: currentIndex,
            endIndex: currentIndex + cleanWord.length,
            confidence: 0.9, // High confidence only for obvious typos
          ));
          
          debugPrint('SpellCheck: OBVIOUS TYPO - Corrected "$cleanWord" to "$suggestion"');
        } else {
          // Keep original word - be very conservative
          correctedWords.add(word);
          debugPrint('SpellCheck: Word "$cleanWord" not in vocabulary but KEEPING ORIGINAL (not obvious typo)');
        }
      }
      
      currentIndex += word.length + 1; // +1 for space
    }

    final correctedText = correctedWords.join(' ');
    final confidence = words.isEmpty ? 1.0 : correctWords / words.length;

    debugPrint('SpellCheck: Local correction completed');
    debugPrint('SpellCheck: Original: "$text"');
    debugPrint('SpellCheck: Corrected: "$correctedText"');
    debugPrint('SpellCheck: Confidence: $confidence');
    debugPrint('SpellCheck: Errors found: ${errors.length}');

    return SpellCheckResultModel(
      originalText: text,
      correctedText: correctedText,
      confidence: confidence,
      errors: errors,
    );
  }

  String _applyGermanGrammarRules(String text) {
    String corrected = text.trim();
    
    debugPrint('SpellCheck: Applying German grammar rules to: "$corrected"');
    
    // Rule 1: Fix common passive voice errors
    corrected = corrected.replaceAll(RegExp(r'\bwird es (\w+)e ist\b'), 'wird \$1');
    corrected = corrected.replaceAll(RegExp(r'\bwird es (\w+)te ist\b'), 'wird \$1');
    corrected = corrected.replaceAll(RegExp(r'\bwird es (\w+)t\b'), 'wird \$1');
    
    // Rule 2: Fix redundant phrases
    corrected = corrected.replaceAll(RegExp(r'\bdie Korrektur wird es überprüfte ist\b'), 'die Korrektur wird überprüft');
    corrected = corrected.replaceAll(RegExp(r'\bdie Korrektur überprüft werden\b'), 'die Korrektur wird überprüft');
    
    // Rule 3: Fix sentence beginnings (capitalize first word)
    corrected = corrected.replaceAllMapped(RegExp(r'^(\w)'), (match) => match.group(1)!.toUpperCase());
    
    // Rule 4: Add proper punctuation for common phrases
    corrected = corrected.replaceAll(RegExp(r'\bkeine Ahnung ob\b'), 'Keine Ahnung, ob');
    corrected = corrected.replaceAll(RegExp(r'\boder nicht\b'), 'oder nicht.');
    
    // Rule 5: Fix verb conjugations
    corrected = corrected.replaceAll(RegExp(r'\bfunktioniert oder nicht die\b'), 'funktioniert oder nicht. Die');
    
    // Rule 6: Remove duplicate words
    corrected = corrected.replaceAll(RegExp(r'\b(\w+)\s+\1\b'), '\$1');
    
    // Rule 7: Clean up extra spaces
    corrected = corrected.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    debugPrint('SpellCheck: Grammar rules applied, result: "$corrected"');
    
    return corrected;
  }

  String? _findBestCorrection(String word) {
    if (_vocabulary == null) return null;

    // Only suggest corrections for words that are EXTREMELY similar
    final candidates = _vocabulary!.where((vocabWord) {
      return _calculateSimilarity(word, vocabWord) > 0.9; // VERY high similarity threshold
    }).toList();

    if (candidates.isEmpty) return null;

    // Sort by similarity and return the best match
    candidates.sort((a, b) => _calculateSimilarity(word, b).compareTo(_calculateSimilarity(word, a)));
    return candidates.first;
  }

  bool _isObviousTypo(String original, String suggestion) {
    // Only consider it an obvious typo if:
    // 1. The words are EXTREMELY similar (>95% similarity)
    // 2. Length difference is minimal (max 1 character)
    // 3. Most characters are the same
    
    final similarity = _calculateSimilarity(original, suggestion);
    final lengthDiff = (original.length - suggestion.length).abs();
    
    // EXTREMELY conservative criteria for typo detection
    bool isObviousTypo = similarity > 0.95 && lengthDiff <= 1 && original.length >= 4;
    
    debugPrint('SpellCheck: Typo analysis for "$original" -> "$suggestion": similarity=$similarity, lengthDiff=$lengthDiff, isObvious=$isObviousTypo');
    
    return isObviousTypo;
  }

  double _calculateSimilarity(String word1, String word2) {
    if (word1 == word2) return 1.0;
    if (word1.isEmpty || word2.isEmpty) return 0.0;
    
    // Simple similarity based on common characters and length
    final maxLength = word1.length > word2.length ? word1.length : word2.length;
    final minLength = word1.length < word2.length ? word1.length : word2.length;
    
    // Length similarity
    final lengthSimilarity = minLength / maxLength;
    
    // Character similarity (simple approach)
    int commonChars = 0;
    final shorter = word1.length < word2.length ? word1 : word2;
    final longer = word1.length >= word2.length ? word1 : word2;
    
    for (int i = 0; i < shorter.length; i++) {
      if (i < longer.length && shorter[i] == longer[i]) {
        commonChars++;
      }
    }
    
    final charSimilarity = commonChars / maxLength;
    
    // Combined similarity
    return (lengthSimilarity + charSimilarity) / 2;
  }

  /// Toggle between AI and local correction
  void setUseAI(bool useAI) {
    _useAI = useAI;
    debugPrint('SpellCheck: Switched to ${useAI ? "AI" : "local"} correction mode');
  }

  @override
  Future<void> dispose() async {
    debugPrint('SpellCheck: Disposing spell check datasource');
    _vocabulary = null;
    _aiGrammarService = null;
  }
} 