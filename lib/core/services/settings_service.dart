import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GrammarCorrectionMode {
  onlineOnly,
  offlineOnly,
  ollamaOnly,    // New: Ollama only mode
  hybrid,        // Try online first, fallback to offline
  hybridOllama,  // Try Ollama first, fallback to offline
}

enum SttEngine {
  whisper,      // Local Whisper model
  googleStt,    // Google Speech-to-Text (online)
}

enum WhisperModelSize {
  tiny,    // ~75 MB - Schnell, niedrige Qualität
  base,    // ~150 MB - Gut, empfohlen
  small,   // ~500 MB - Sehr gut (könnte crashen)
}

class SettingsService {
  static const String _grammarModeKey = 'grammar_correction_mode';
  static const String _serverUrlKey = 'grammar_server_url';
  static const String _ollamaUrlKey = 'ollama_server_url';
  static const String _ollamaModelKey = 'ollama_model_name';
  static const String _ollamaPromptKey = 'ollama_custom_prompt';
  static const String _sttEngineKey = 'stt_engine';
  static const String _whisperModelKey = 'whisper_model_size';
  
  static const String _defaultServerUrl = 'http://localhost:8000';
  static const String _defaultOllamaUrl = 'http://localhost:11434';
  static const String _defaultOllamaModel = 'gemma3:1b';
  static const String _defaultOllamaPrompt = 'Schreib den folgenden Text mit korrekter deutscher Grammatik und Rechtschreibung neu. Verändere dabei nicht die Bedeutung. Gib nur den korrigierten Text zurück, ohne zusätzliche Erklärungen:\n\n{TEXT}';

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

  /// Get the current grammar correction mode
  GrammarCorrectionMode get grammarCorrectionMode {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, returning default mode');
      return GrammarCorrectionMode.hybrid;
    }

    final modeIndex = _prefs.getInt(_grammarModeKey) ?? GrammarCorrectionMode.hybrid.index;
    // Ensure the index is valid for current enum values
    if (modeIndex >= GrammarCorrectionMode.values.length) {
      return GrammarCorrectionMode.hybrid;
    }
    return GrammarCorrectionMode.values[modeIndex];
  }

  /// Set the grammar correction mode
  Future<void> setGrammarCorrectionMode(GrammarCorrectionMode mode) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save mode');
      return;
    }

    try {
      await _prefs.setInt(_grammarModeKey, mode.index);
      debugPrint('SettingsService: Grammar mode set to ${mode.name}');
    } catch (e) {
      debugPrint('SettingsService: Failed to save grammar mode: $e');
    }
  }

  /// Get the server URL
  String get serverUrl {
    if (!_isInitialized) {
      return _defaultServerUrl;
    }

    return _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
  }

  /// Set the server URL
  Future<void> setServerUrl(String url) async {
    if (!_isInitialized) {
      debugPrint('SettingsService: Not initialized, cannot save server URL');
      return;
    }

    try {
      // Ensure URL format is correct
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      
      await _prefs.setString(_serverUrlKey, url);
      debugPrint('SettingsService: Server URL set to $url');
    } catch (e) {
      debugPrint('SettingsService: Failed to save server URL: $e');
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

  /// Check if settings are initialized
  bool get isInitialized => _isInitialized;

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    if (!_isInitialized) return;

    try {
      await _prefs.remove(_grammarModeKey);
      await _prefs.remove(_serverUrlKey);
      await _prefs.remove(_ollamaUrlKey);
      await _prefs.remove(_ollamaModelKey);
      await _prefs.remove(_ollamaPromptKey);
      await _prefs.remove(_sttEngineKey);
      await _prefs.remove(_whisperModelKey);
      debugPrint('SettingsService: Settings reset to defaults');
    } catch (e) {
      debugPrint('SettingsService: Failed to reset settings: $e');
    }
  }
} 