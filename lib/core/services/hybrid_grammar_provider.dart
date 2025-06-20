import 'package:flutter/foundation.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/online_grammar_provider.dart';
import 'package:dictation_app/core/services/ollama_grammar_provider.dart';
import 'package:dictation_app/core/services/settings_service.dart';

/// Callback for notifying about fallback events
typedef FallbackCallback = void Function(String message, bool isWarning);

/// Hybrid grammar correction provider that supports FastAPI, Ollama, and offline modes
class HybridGrammarProvider implements GrammarCorrectionProvider {
  final SettingsService _settingsService;
  final OfflineGECProvider _offlineProvider;
  OnlineGrammarProvider? _onlineProvider;
  OllamaGrammarProvider? _ollamaProvider;
  FallbackCallback? _onFallback;
  
  bool _lastServerHealthy = false;
  bool _lastOllamaHealthy = false;
  DateTime? _lastHealthCheck;
  DateTime? _lastOllamaHealthCheck;
  static const Duration _healthCheckInterval = Duration(minutes: 5);

  HybridGrammarProvider({
    required SettingsService settingsService,
    FallbackCallback? onFallback,
  }) : _settingsService = settingsService,
       _offlineProvider = OfflineGECProvider(),
       _onFallback = onFallback {
    _initializeProviders();
  }

  void _initializeProviders() {
    // Initialize FastAPI provider
    final serverUrl = _settingsService.serverUrl;
    _onlineProvider = OnlineGrammarProvider(serverUrl: serverUrl);
    debugPrint('HybridGrammarProvider: Initialized FastAPI with server URL: $serverUrl');
    
    // Initialize Ollama provider
    final ollamaUrl = _settingsService.ollamaUrl;
    final ollamaModel = _settingsService.ollamaModel;
    final ollamaPrompt = _settingsService.ollamaPrompt;
    _ollamaProvider = OllamaGrammarProvider(
      ollamaUrl: ollamaUrl,
      modelName: ollamaModel,
      customPrompt: ollamaPrompt,
    );
    debugPrint('HybridGrammarProvider: Initialized Ollama with URL: $ollamaUrl, Model: $ollamaModel, Prompt: ${ollamaPrompt.substring(0, ollamaPrompt.length > 50 ? 50 : ollamaPrompt.length)}...');
  }

  @override
  String get providerName {
    final mode = _settingsService.grammarCorrectionMode;
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'Online Only mT5 GEC';
      case GrammarCorrectionMode.offlineOnly:
        return 'Offline Only mT5 GEC';
      case GrammarCorrectionMode.ollamaOnly:
        return 'Ollama Only ${_settingsService.ollamaModel} GEC';
      case GrammarCorrectionMode.hybrid:
        return 'Hybrid mT5 GEC (FastAPI + Offline)';
      case GrammarCorrectionMode.hybridOllama:
        return 'Hybrid Ollama GEC (Ollama + Offline)';
    }
  }

  /// Update server URL and reinitialize online provider
  void updateServerUrl(String newUrl) {
    _onlineProvider = OnlineGrammarProvider(serverUrl: newUrl);
    _lastServerHealthy = false;
    _lastHealthCheck = null;
    debugPrint('HybridGrammarProvider: Server URL updated to $newUrl');
  }

  /// Update Ollama configuration and reinitialize provider
  void updateOllamaConfig(String newUrl, String newModel, {String? newPrompt}) {
    _ollamaProvider = OllamaGrammarProvider(
      ollamaUrl: newUrl,
      modelName: newModel,
      customPrompt: newPrompt ?? _settingsService.ollamaPrompt,
    );
    _lastOllamaHealthy = false;
    _lastOllamaHealthCheck = null;
    debugPrint('HybridGrammarProvider: Ollama config updated to URL: $newUrl, Model: $newModel');
  }

  /// Check if cached health status is still valid
  bool _isHealthCheckValid(DateTime? lastCheck) {
    if (lastCheck == null) return false;
    return DateTime.now().difference(lastCheck) < _healthCheckInterval;
  }

  /// Perform health check with caching
  Future<bool> _checkServerHealth() async {
    if (_isHealthCheckValid(_lastHealthCheck)) {
      debugPrint('HybridGrammarProvider: Using cached health status: $_lastServerHealthy');
      return _lastServerHealthy;
    }

    _lastServerHealthy = await _onlineProvider!.isServerHealthy();
    _lastHealthCheck = DateTime.now();
    debugPrint('HybridGrammarProvider: Fresh health check result: $_lastServerHealthy');
    return _lastServerHealthy;
  }

  /// Perform Ollama health check with caching
  Future<bool> _checkOllamaHealth() async {
    if (_isHealthCheckValid(_lastOllamaHealthCheck)) {
      debugPrint('HybridGrammarProvider: Using cached Ollama health status: $_lastOllamaHealthy');
      return _lastOllamaHealthy;
    }

    _lastOllamaHealthy = await _ollamaProvider!.isServerHealthy();
    _lastOllamaHealthCheck = DateTime.now();
    debugPrint('HybridGrammarProvider: Fresh Ollama health check result: $_lastOllamaHealthy');
    return _lastOllamaHealthy;
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    debugPrint('=== Hybrid Grammar Correction Start ===');
    debugPrint('HybridGrammarProvider: Starting correction with mode: ${_settingsService.grammarCorrectionMode.name}');
    debugPrint('HybridGrammarProvider: Input text length: ${text.length}');
    debugPrint('HybridGrammarProvider: Input text preview: "${text.length > 100 ? text.substring(0, 100) + '...' : text}"');
    
    final mode = _settingsService.grammarCorrectionMode;
    
    GrammarCorrectionResult result;
    
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        result = await _correctOnlineOnly(text);
        break;
      case GrammarCorrectionMode.offlineOnly:
        result = await _correctOfflineOnly(text);
        break;
      case GrammarCorrectionMode.ollamaOnly:
        result = await _correctOllamaOnly(text);
        break;
      case GrammarCorrectionMode.hybrid:
        result = await _correctHybridFastAPI(text);
        break;
      case GrammarCorrectionMode.hybridOllama:
        result = await _correctHybridOllama(text);
        break;
    }
    
    debugPrint('=== Hybrid Grammar Correction End ===');
    debugPrint('HybridGrammarProvider: Final result:');
    debugPrint('HybridGrammarProvider: - Method: ${result.correctionMethod}');
    debugPrint('HybridGrammarProvider: - Confidence: ${result.confidence}');
    debugPrint('HybridGrammarProvider: - Has corrections: ${result.hasCorrections}');
    debugPrint('HybridGrammarProvider: - Errors found: ${result.errors.length}');
    debugPrint('HybridGrammarProvider: - Original: "${result.originalText}"');
    debugPrint('HybridGrammarProvider: - Corrected: "${result.correctedText}"');
    
    return result;
  }

  /// Online-only correction using FastAPI
  Future<GrammarCorrectionResult> _correctOnlineOnly(String text) async {
    debugPrint('HybridGrammarProvider: Using online-only mode');
    
    final isHealthy = await _checkServerHealth();
    if (!isHealthy) {
      debugPrint('HybridGrammarProvider: Server not reachable in online-only mode');
      throw Exception('Server not reachable and offline mode disabled');
    }
    
    debugPrint('HybridGrammarProvider: FastAPI server is healthy, proceeding with correction');
    return await _onlineProvider!.correctText(text);
  }

  /// Ollama-only correction
  Future<GrammarCorrectionResult> _correctOllamaOnly(String text) async {
    debugPrint('HybridGrammarProvider: Using Ollama-only mode');
    
    final isHealthy = await _checkOllamaHealth();
    if (!isHealthy) {
      debugPrint('HybridGrammarProvider: Ollama not reachable in Ollama-only mode');
      throw Exception('Ollama not reachable and offline mode disabled');
    }
    
    debugPrint('HybridGrammarProvider: Ollama is healthy, proceeding with correction');
    return await _ollamaProvider!.correctText(text);
  }

  /// Offline-only correction
  Future<GrammarCorrectionResult> _correctOfflineOnly(String text) async {
    debugPrint('HybridGrammarProvider: Using offline-only mode');
    return await _offlineProvider.correctText(text);
  }

  /// Hybrid correction: FastAPI first, then offline fallback
  Future<GrammarCorrectionResult> _correctHybridFastAPI(String text) async {
    debugPrint('HybridGrammarProvider: Using hybrid FastAPI mode');
    
    try {
      final isHealthy = await _checkServerHealth();
      if (isHealthy) {
        debugPrint('HybridGrammarProvider: FastAPI server is healthy, trying online correction first');
        return await _onlineProvider!.correctText(text);
      } else {
        debugPrint('HybridGrammarProvider: FastAPI server not available, falling back to offline');
        _notifyFallback('FastAPI server not available, using offline mode', false);
        return await _offlineProvider.correctText(text);
      }
    } catch (e) {
      debugPrint('HybridGrammarProvider: FastAPI failed: $e, falling back to offline');
      _notifyFallback('FastAPI correction failed, using offline mode', true);
      return await _offlineProvider.correctText(text);
    }
  }

  /// Hybrid correction: Ollama first, then offline fallback
  Future<GrammarCorrectionResult> _correctHybridOllama(String text) async {
    debugPrint('HybridGrammarProvider: Using hybrid Ollama mode');
    
    try {
      final isHealthy = await _checkOllamaHealth();
      if (isHealthy) {
        debugPrint('HybridGrammarProvider: Ollama is healthy, trying Ollama correction first');
        return await _ollamaProvider!.correctText(text);
      } else {
        debugPrint('HybridGrammarProvider: Ollama not available, falling back to offline');
        _notifyFallback('Ollama not available, using offline mode', false);
        return await _offlineProvider.correctText(text);
      }
    } catch (e) {
      debugPrint('HybridGrammarProvider: Ollama failed: $e, falling back to offline');
      _notifyFallback('Ollama correction failed, using offline mode', true);
      return await _offlineProvider.correctText(text);
    }
  }

  /// Notify about fallback events
  void _notifyFallback(String message, bool isWarning) {
    _onFallback?.call(message, isWarning);
  }

  /// Set fallback callback
  void setFallbackCallback(FallbackCallback callback) {
    _onFallback = callback;
  }

  /// Get current provider status for UI
  Future<Map<String, bool>> getProviderStatus() async {
    return {
      'fastapi': await _checkServerHealth(),
      'ollama': await _checkOllamaHealth(),
      'offline': true, // Always available
    };
  }

  @override
  void dispose() {
    debugPrint('HybridGrammarProvider: Disposing providers');
    _onlineProvider?.dispose();
    _ollamaProvider?.dispose();
    _offlineProvider.dispose();
  }
} 