import 'package:flutter/foundation.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/ollama_grammar_provider.dart';
import 'package:dictation_app/core/services/settings_service.dart';

/// Simple text processing provider that only uses Ollama
class TextProcessingProvider implements GrammarCorrectionProvider {
  final SettingsService _settingsService;
  OllamaGrammarProvider? _ollamaProvider;

  TextProcessingProvider({
    required SettingsService settingsService,
  }) : _settingsService = settingsService {
    _initializeProvider();
  }

  void _initializeProvider() {
    final ollamaUrl = _settingsService.ollamaUrl;
    final ollamaModel = _settingsService.ollamaModel;
    final ollamaPrompt = _settingsService.ollamaPrompt;

    _ollamaProvider = OllamaGrammarProvider(
      ollamaUrl: ollamaUrl,
      modelName: ollamaModel,
      customPrompt: ollamaPrompt,
    );

    debugPrint('TextProcessingProvider: Initialized with URL: $ollamaUrl, Model: $ollamaModel');
  }

  @override
  String get providerName {
    final mode = _settingsService.textProcessingMode;
    if (mode == TextProcessingMode.disabled) {
      return 'No Text Processing';
    }
    return 'Ollama ${_settingsService.ollamaModel}';
  }

  /// Update Ollama configuration and reinitialize provider
  void updateOllamaConfig(String newUrl, String newModel, {String? newPrompt}) {
    _ollamaProvider = OllamaGrammarProvider(
      ollamaUrl: newUrl,
      modelName: newModel,
      customPrompt: newPrompt ?? _settingsService.ollamaPrompt,
    );
    debugPrint('TextProcessingProvider: Ollama config updated to URL: $newUrl, Model: $newModel');
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('=== Text Processing Start ===');
    debugPrint('TextProcessingProvider: Mode: ${_settingsService.textProcessingMode.name}');
    debugPrint('TextProcessingProvider: Input text length: ${text.length}');

    final mode = _settingsService.textProcessingMode;

    if (mode == TextProcessingMode.disabled) {
      debugPrint('TextProcessingProvider: Text processing disabled, returning original text');
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 1.0,
        errors: [],
        correctionMethod: 'No Processing',
      );
    }

    // Re-initialize provider with current settings to ensure we use latest prompt/model/url
    final currentUrl = _settingsService.ollamaUrl;
    final currentModel = _settingsService.ollamaModel;
    final currentPrompt = _settingsService.ollamaPrompt;

    debugPrint('TextProcessingProvider: Current settings - URL: $currentUrl, Model: $currentModel, Prompt length: ${currentPrompt.length}');

    _ollamaProvider = OllamaGrammarProvider(
      ollamaUrl: currentUrl,
      modelName: currentModel,
      customPrompt: currentPrompt,
    );

    // Use Ollama
    try {
      debugPrint('TextProcessingProvider: Using Ollama for text processing');
      final result = await _ollamaProvider!.correctText(text);
      debugPrint('TextProcessingProvider: Ollama processing completed successfully');
      debugPrint('=== Text Processing End: SUCCESS ===');
      return result;
    } catch (e) {
      debugPrint('TextProcessingProvider: Ollama processing failed: $e');
      debugPrint('TextProcessingProvider: Returning original text');
      debugPrint('=== Text Processing End: FAILED ===');

      // Return original text if Ollama fails
      return GrammarCorrectionResult(
        originalText: text,
        correctedText: text,
        confidence: 0.0,
        errors: [],
        correctionMethod: 'Failed - Original Text',
      );
    }
  }

  /// Check if Ollama is healthy
  Future<bool> isOllamaHealthy() async {
    if (_ollamaProvider == null) return false;
    try {
      return await _ollamaProvider!.isServerHealthy();
    } catch (e) {
      debugPrint('TextProcessingProvider: Ollama health check failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    debugPrint('TextProcessingProvider: Disposing provider');
    _ollamaProvider?.dispose();
  }
}
