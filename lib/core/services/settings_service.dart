import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextProcessingMode {
  disabled,      // No text processing after STT
  ollamaEnabled, // Use Ollama for text processing
}

enum SttEngine {
  whisper,      // Local Whisper model
  googleStt,    // Google Speech-to-Text (online)
}

enum WhisperModelSize {
  tiny,    // ~75 MB - Schnell, niedrige Qualität
  base,    // ~150 MB - Gut, empfohlen für Mobile
  small,   // ~500 MB - Sehr gut
  medium,  // ~1.5 GB - Beste Qualität, empfohlen für Desktop
}

enum OllamaPromptTemplate {
  speechRecognition,  // Optimiert für Spracherkennung (Default)
  grammarCorrection,  // Grammatik- und Rechtschreibkorrektur
  styleFormal,        // Formeller Schreibstil
  styleInformal,      // Informeller Schreibstil
  styleAcademic,      // Akademischer Schreibstil
  translationDeEn,    // Übersetzung Deutsch → Englisch
  translationEnDe,    // Übersetzung Englisch → Deutsch
  summarization,      // Zusammenfassung
  custom,             // Benutzerdefiniert
}

class SettingsService {
  static const String _textProcessingModeKey = 'text_processing_mode';
  static const String _ollamaUrlKey = 'ollama_server_url';
  static const String _ollamaModelKey = 'ollama_model_name';
  static const String _ollamaPromptKey = 'ollama_custom_prompt';
  static const String _ollamaPromptTemplateKey = 'ollama_prompt_template';
  static const String _ollamaContextLengthKey = 'ollama_context_length';
  static const String _ollamaTemperatureKey = 'ollama_temperature';
  static const String _sttEngineKey = 'stt_engine';
  static const String _whisperModelKey = 'whisper_model_size';

  static const String _defaultOllamaUrl = 'http://localhost:11434';
  static const String _defaultOllamaModel = 'gemma3:1b';
  static const int _defaultContextLength = 8192; // Larger context for better understanding
  static const double _defaultTemperature = 0.4; // Slightly higher for better reformulation
  
  // Default to speech recognition optimized prompt
  static const String _defaultOllamaPrompt = '''Du bist ein intelligenter Textverbesserungs-Assistent für Spracherkennung. Analysiere den transkribierten Text als Ganzes und verbessere ihn kontextbasiert.

AUFGABEN:
1. Analysiere den gesamten Kontext und erkenne die Themen/Abschnitte
2. Korrigiere Fehler der Spracherkennung (falsch erkannte Wörter, die keinen Sinn ergeben)
3. Korrigiere Grammatik, Rechtschreibung und Zeichensetzung
4. Optimiere Satzstruktur und Formulierungen für bessere Lesbarkeit
5. Entferne Füllwörter, Wiederholungen und typische Sprachfehler
6. Verbessere Satzübergänge bei Themenwechseln
7. Behalte die ursprüngliche Bedeutung und Intention bei

WICHTIG:
- Gib NUR den verbesserten Text zurück, keine Erklärungen
- Behalte alle wichtigen Informationen bei
- Verwende natürliches, flüssiges Deutsch
- Bei Themenwechseln: Sorge für klare Absätze
- Korrigiere auch Wörter, die die Spracherkennung falsch verstanden hat

TEXT:
{TEXT}''';

  // Prompt templates
  static const Map<OllamaPromptTemplate, String> _promptTemplates = {
    OllamaPromptTemplate.speechRecognition: '''Du bist ein intelligenter Textverbesserungs-Assistent für Spracherkennung. Analysiere den transkribierten Text als Ganzes und verbessere ihn kontextbasiert.

AUFGABEN:
1. Analysiere den gesamten Kontext und erkenne die Themen/Abschnitte
2. Korrigiere Fehler der Spracherkennung (falsch erkannte Wörter, die keinen Sinn ergeben)
3. Korrigiere Grammatik, Rechtschreibung und Zeichensetzung
4. Optimiere Satzstruktur und Formulierungen für bessere Lesbarkeit
5. Entferne Füllwörter, Wiederholungen und typische Sprachfehler
6. Verbessere Satzübergänge bei Themenwechseln
7. Behalte die ursprüngliche Bedeutung und Intention bei

WICHTIG:
- Gib NUR den verbesserten Text zurück, keine Erklärungen
- Behalte alle wichtigen Informationen bei
- Verwende natürliches, flüssiges Deutsch
- Bei Themenwechseln: Sorge für klare Absätze
- Korrigiere auch Wörter, die die Spracherkennung falsch verstanden hat

TEXT:
{TEXT}''',
    OllamaPromptTemplate.grammarCorrection: 'Schreib den folgenden Text mit korrekter deutscher Grammatik und Rechtschreibung neu. Verändere dabei nicht die Bedeutung. Gib nur den korrigierten Text zurück, ohne zusätzliche Erklärungen:\n\n{TEXT}',
    OllamaPromptTemplate.styleFormal: 'Formuliere den folgenden Text in einem formellen, professionellen Stil um. Verwende höfliche Anrede und sachliche Sprache. Gib nur den umformulierten Text zurück:\n\n{TEXT}',
    OllamaPromptTemplate.styleInformal: 'Formuliere den folgenden Text in einem lockeren, informellen Stil um. Verwende eine freundliche, persönliche Sprache. Gib nur den umformulierten Text zurück:\n\n{TEXT}',
    OllamaPromptTemplate.styleAcademic: 'Formuliere den folgenden Text in einem wissenschaftlichen, akademischen Stil um. Verwende Fachsprache und präzise Formulierungen. Gib nur den umformulierten Text zurück:\n\n{TEXT}',
    OllamaPromptTemplate.translationDeEn: 'Translate the following German text to English. Provide only the translation without explanations:\n\n{TEXT}',
    OllamaPromptTemplate.translationEnDe: 'Übersetze den folgenden englischen Text ins Deutsche. Gib nur die Übersetzung ohne Erklärungen zurück:\n\n{TEXT}',
    OllamaPromptTemplate.summarization: 'Fasse den folgenden Text in 2-3 prägnanten Sätzen zusammen. Gib nur die Zusammenfassung zurück:\n\n{TEXT}',
    OllamaPromptTemplate.custom: '', // Will be filled with user's custom prompt
  };

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  /// Initialize the settings service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('SettingsService: Initialized successfully');
    } catch (e) {
      debugPrint('SettingsService: Failed to initialize: $e');
      rethrow;
    }
  }

  /// Get the current text processing mode
  TextProcessingMode get textProcessingMode {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, returning default mode');
      return TextProcessingMode.disabled;
    }

    final modeIndex = _prefs.getInt(_textProcessingModeKey) ?? TextProcessingMode.disabled.index;
    // Ensure the index is valid for current enum values
    if (modeIndex >= TextProcessingMode.values.length) {
      return TextProcessingMode.disabled;
    }
    return TextProcessingMode.values[modeIndex];
  }

  /// Set the text processing mode
  Future<void> setTextProcessingMode(TextProcessingMode mode) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save mode');
      return;
    }

    try {
      await _prefs.setInt(_textProcessingModeKey, mode.index);
      debugPrint('SettingsService: Text processing mode set to ${mode.name}');
    } catch (e) {
      debugPrint('SettingsService: Failed to save text processing mode: $e');
    }
  }

  /// Get the Ollama server URL
  String get ollamaUrl {
    if (!_isInitialized) {
      return _defaultOllamaUrl;
    }

    return _prefs.getString(_ollamaUrlKey) ?? _defaultOllamaUrl;
  }

  /// Set the Ollama server URL
  Future<void> setOllamaUrl(String url) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama URL');
      return;
    }

    try {
      // Ensure URL format is correct
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      
      await _prefs.setString(_ollamaUrlKey, url);
      debugPrint('SettingsService: Ollama URL set to $url');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama URL: $e');
    }
  }

  /// Get the Ollama model name
  String get ollamaModel {
    if (!_isInitialized) {
      return _defaultOllamaModel;
    }

    return _prefs.getString(_ollamaModelKey) ?? _defaultOllamaModel;
  }

  /// Set the Ollama model name
  Future<void> setOllamaModel(String modelName) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama model');
      return;
    }

    try {
      await _prefs.setString(_ollamaModelKey, modelName.trim());
      debugPrint('SettingsService: Ollama model set to $modelName');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama model: $e');
    }
  }

  /// Get the custom Ollama prompt
  String get ollamaPrompt {
    if (!_isInitialized) {
      return _defaultOllamaPrompt;
    }

    return _prefs.getString(_ollamaPromptKey) ?? _defaultOllamaPrompt;
  }

  /// Set the custom Ollama prompt
  Future<void> setOllamaPrompt(String prompt) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama prompt');
      return;
    }

    try {
      await _prefs.setString(_ollamaPromptKey, prompt.trim());
      debugPrint('SettingsService: Ollama prompt set (${prompt.length} chars)');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama prompt: $e');
    }
  }

  /// Get the current Ollama prompt template
  OllamaPromptTemplate get ollamaPromptTemplate {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, returning default template');
      return OllamaPromptTemplate.speechRecognition;
    }

    final templateIndex = _prefs.getInt(_ollamaPromptTemplateKey) ?? OllamaPromptTemplate.speechRecognition.index;
    // Ensure the index is valid for current enum values
    if (templateIndex >= OllamaPromptTemplate.values.length) {
      return OllamaPromptTemplate.speechRecognition;
    }
    return OllamaPromptTemplate.values[templateIndex];
  }

  /// Set the Ollama prompt template
  Future<void> setOllamaPromptTemplate(OllamaPromptTemplate template) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama template');
      return;
    }

    try {
      await _prefs.setInt(_ollamaPromptTemplateKey, template.index);
      debugPrint('SettingsService: Ollama template set to ${template.name}');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama template: $e');
    }
  }

  /// Get prompt text for a specific template
  String getPromptForTemplate(OllamaPromptTemplate template) {
    if (template == OllamaPromptTemplate.custom) {
      // Return user's custom prompt
      return ollamaPrompt;
    }
    return _promptTemplates[template] ?? _defaultOllamaPrompt;
  }

  /// Get display name for a template
  String getTemplateDisplayName(OllamaPromptTemplate template) {
    switch (template) {
      case OllamaPromptTemplate.speechRecognition:
        return 'Spracherkennung (empfohlen)';
      case OllamaPromptTemplate.grammarCorrection:
        return 'Grammatik- & Rechtschreibkorrektur';
      case OllamaPromptTemplate.styleFormal:
        return 'Formeller Schreibstil';
      case OllamaPromptTemplate.styleInformal:
        return 'Informeller Schreibstil';
      case OllamaPromptTemplate.styleAcademic:
        return 'Akademischer Schreibstil';
      case OllamaPromptTemplate.translationDeEn:
        return 'Übersetzung Deutsch → Englisch';
      case OllamaPromptTemplate.translationEnDe:
        return 'Übersetzung Englisch → Deutsch';
      case OllamaPromptTemplate.summarization:
        return 'Zusammenfassung';
      case OllamaPromptTemplate.custom:
        return 'Benutzerdefiniert';
    }
  }

  /// Get description for a template
  String getTemplateDescription(OllamaPromptTemplate template) {
    switch (template) {
      case OllamaPromptTemplate.speechRecognition:
        return 'Intelligente Textverbesserung: Korrigiert Spracherkennungsfehler, optimiert Formulierungen, verbessert Kontext';
      case OllamaPromptTemplate.grammarCorrection:
        return 'Korrigiert Grammatik und Rechtschreibung';
      case OllamaPromptTemplate.styleFormal:
        return 'Ändert den Text in einen formellen, professionellen Stil';
      case OllamaPromptTemplate.styleInformal:
        return 'Ändert den Text in einen lockeren, freundlichen Stil';
      case OllamaPromptTemplate.styleAcademic:
        return 'Ändert den Text in einen wissenschaftlichen Stil';
      case OllamaPromptTemplate.translationDeEn:
        return 'Übersetzt deutschen Text ins Englische';
      case OllamaPromptTemplate.translationEnDe:
        return 'Übersetzt englischen Text ins Deutsche';
      case OllamaPromptTemplate.summarization:
        return 'Fasst den Text zusammen (2-3 Sätze)';
      case OllamaPromptTemplate.custom:
        return 'Eigener Prompt mit {TEXT} Platzhalter';
    }
  }

  /// Get the current STT engine
  SttEngine get sttEngine {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, returning default STT engine');
      return SttEngine.whisper;
    }

    final engineIndex = _prefs.getInt(_sttEngineKey) ?? SttEngine.whisper.index;
    // Ensure the index is valid for current enum values
    if (engineIndex >= SttEngine.values.length) {
      return SttEngine.whisper;
    }
    return SttEngine.values[engineIndex];
  }

  /// Set the STT engine
  Future<void> setSttEngine(SttEngine engine) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save STT engine');
      return;
    }

    try {
      await _prefs.setInt(_sttEngineKey, engine.index);
      debugPrint('SettingsService: STT engine set to ${engine.name}');
    } catch (e) {
      debugPrint('SettingsService: Failed to save STT engine: $e');
    }
  }

  /// Get the current Whisper model size
  WhisperModelSize get whisperModelSize {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, returning default Whisper model');
      return WhisperModelSize.base;
    }

    final modelIndex = _prefs.getInt(_whisperModelKey) ?? WhisperModelSize.base.index;
    if (modelIndex >= WhisperModelSize.values.length) {
      return WhisperModelSize.base;
    }
    return WhisperModelSize.values[modelIndex];
  }

  /// Set the Whisper model size
  Future<void> setWhisperModelSize(WhisperModelSize modelSize) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Whisper model');
      return;
    }

    try {
      await _prefs.setInt(_whisperModelKey, modelSize.index);
      debugPrint('SettingsService: Whisper model size set to ${modelSize.name}');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Whisper model: $e');
    }
  }

  /// Get the Ollama context length
  int get ollamaContextLength {
    if (!_isInitialized) {
      return _defaultContextLength;
    }

    return _prefs.getInt(_ollamaContextLengthKey) ?? _defaultContextLength;
  }

  /// Set the Ollama context length
  Future<void> setOllamaContextLength(int contextLength) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama context length');
      return;
    }

    try {
      // Clamp context length between 512 and 32768
      final clampedLength = contextLength.clamp(512, 32768);
      await _prefs.setInt(_ollamaContextLengthKey, clampedLength);
      debugPrint('SettingsService: Ollama context length set to $clampedLength');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama context length: $e');
    }
  }

  /// Get the Ollama temperature
  double get ollamaTemperature {
    if (!_isInitialized) {
      return _defaultTemperature;
    }

    return _prefs.getDouble(_ollamaTemperatureKey) ?? _defaultTemperature;
  }

  /// Set the Ollama temperature
  Future<void> setOllamaTemperature(double temperature) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save Ollama temperature');
      return;
    }

    try {
      // Clamp temperature between 0.0 and 2.0
      final clampedTemp = temperature.clamp(0.0, 2.0);
      await _prefs.setDouble(_ollamaTemperatureKey, clampedTemp);
      debugPrint('SettingsService: Ollama temperature set to $clampedTemp');
    } catch (e) {
      debugPrint('SettingsService: Failed to save Ollama temperature: $e');
    }
  }

  /// Check if settings are initialized
  bool get isInitialized => _isInitialized;

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    if (!_isInitialized) return;

    try {
      await _prefs.remove(_textProcessingModeKey);
      await _prefs.remove(_ollamaUrlKey);
      await _prefs.remove(_ollamaModelKey);
      await _prefs.remove(_ollamaPromptKey);
      await _prefs.remove(_ollamaPromptTemplateKey);
      await _prefs.remove(_ollamaContextLengthKey);
      await _prefs.remove(_ollamaTemperatureKey);
      await _prefs.remove(_sttEngineKey);
      await _prefs.remove(_whisperModelKey);
      debugPrint('SettingsService: Settings reset to defaults');
    } catch (e) {
      debugPrint('SettingsService: Failed to reset settings: $e');
    }
  }
} 