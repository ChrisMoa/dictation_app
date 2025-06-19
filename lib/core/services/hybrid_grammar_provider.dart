import 'package:flutter/foundation.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/online_grammar_provider.dart';
import 'package:dictation_app/core/services/settings_service.dart';

/// Callback for notifying about fallback events
typedef FallbackCallback = void Function(String message, bool isWarning);

/// Hybrid grammar correction provider that tries online first, then falls back to offline
class HybridGrammarProvider implements GrammarCorrectionProvider {
  final SettingsService _settingsService;
  final OfflineGECProvider _offlineProvider;
  OnlineGrammarProvider? _onlineProvider;
  FallbackCallback? _onFallback;
  
  bool _lastServerHealthy = false;
  DateTime? _lastHealthCheck;
  static const Duration _healthCheckInterval = Duration(minutes: 5);

  HybridGrammarProvider({
    required SettingsService settingsService,
    FallbackCallback? onFallback,
  }) : _settingsService = settingsService,
       _offlineProvider = OfflineGECProvider(),
       _onFallback = onFallback {
    _initializeOnlineProvider();
  }

  void _initializeOnlineProvider() {
    final serverUrl = _settingsService.serverUrl;
    _onlineProvider = OnlineGrammarProvider(serverUrl: serverUrl);
    debugPrint('HybridGrammarProvider: Initialized with server URL: $serverUrl');
  }

  @override
  String get providerName {
    final mode = _settingsService.grammarCorrectionMode;
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'Online Only mT5 GEC';
      case GrammarCorrectionMode.offlineOnly:
        return 'Offline Only mT5 GEC';
      case GrammarCorrectionMode.hybrid:
        return 'Hybrid mT5 GEC (Online + Offline)';
    }
  }

  /// Update server URL and reinitialize online provider
  void updateServerUrl(String newUrl) {
    _initializeOnlineProvider();
    _lastServerHealthy = false; // Reset health status
    _lastHealthCheck = null;
    debugPrint('HybridGrammarProvider: Server URL updated to $newUrl');
  }

  /// Set fallback callback for notifications
  void setFallbackCallback(FallbackCallback callback) {
    _onFallback = callback;
  }

  @override
  Future<GrammarCorrectionResult> correctText(String text) async {
    final mode = _settingsService.grammarCorrectionMode;
    
    debugPrint('HybridGrammarProvider: Starting correction with mode: ${mode.name}');
    
    switch (mode) {
      case GrammarCorrectionMode.offlineOnly:
        return await _useOfflineOnly(text);
        
      case GrammarCorrectionMode.onlineOnly:
        return await _useOnlineOnly(text);
        
      case GrammarCorrectionMode.hybrid:
        return await _useHybridMode(text);
    }
  }

  /// Use offline correction only
  Future<GrammarCorrectionResult> _useOfflineOnly(String text) async {
    debugPrint('HybridGrammarProvider: Using offline-only mode');
    return await _offlineProvider.correctText(text);
  }

  /// Use online correction only
  Future<GrammarCorrectionResult> _useOnlineOnly(String text) async {
    debugPrint('HybridGrammarProvider: Using online-only mode');
    
    if (_onlineProvider == null) {
      throw Exception('Online provider not initialized');
    }

    // Check server health first
    if (!await _isServerHealthy()) {
      _notifyFallback('Server not reachable in online-only mode', true);
      throw Exception('Server not reachable and offline mode disabled');
    }

    try {
      final result = await _onlineProvider!.correctText(text);
      _notifyFallback('Online correction successful', false);
      return result;
    } catch (e) {
      _notifyFallback('Online correction failed in online-only mode', true);
      rethrow;
    }
  }

  /// Use hybrid mode: try online first, fallback to offline
  Future<GrammarCorrectionResult> _useHybridMode(String text) async {
    debugPrint('HybridGrammarProvider: Using hybrid mode');
    
    if (_onlineProvider == null) {
      debugPrint('HybridGrammarProvider: Online provider not initialized, using offline');
      _notifyFallback('Using offline mode (online provider not configured)', false);
      return await _offlineProvider.correctText(text);
    }

    // Check server health
    if (!await _isServerHealthy()) {
      debugPrint('HybridGrammarProvider: Server not healthy, using offline fallback');
      _notifyFallback('Server not reachable, using offline mode', true);
      return await _offlineProvider.correctText(text);
    }

    // Try online correction first
    try {
      debugPrint('HybridGrammarProvider: Attempting online correction');
      final result = await _onlineProvider!.correctText(text);
      debugPrint('HybridGrammarProvider: Online correction successful');
      return result;
      
    } catch (e) {
      debugPrint('HybridGrammarProvider: Online correction failed: $e, falling back to offline');
      _notifyFallback('Online correction failed, using offline mode', true);
      
      // Fallback to offline
      try {
        final result = await _offlineProvider.correctText(text);
        // Modify the result to indicate it's a fallback
        return GrammarCorrectionResult(
          originalText: result.originalText,
          correctedText: result.correctedText,
          confidence: result.confidence * 0.9, // Slightly lower confidence for fallback
          errors: result.errors,
          correctionMethod: '${result.correctionMethod} (Fallback)',
        );
      } catch (offlineError) {
        debugPrint('HybridGrammarProvider: Both online and offline correction failed');
        _notifyFallback('Both online and offline correction failed', true);
        rethrow;
      }
    }
  }

  /// Check if server is healthy with caching
  Future<bool> _isServerHealthy() async {
    final now = DateTime.now();
    
    // Use cached result if recent
    if (_lastHealthCheck != null && 
        now.difference(_lastHealthCheck!) < _healthCheckInterval) {
      debugPrint('HybridGrammarProvider: Using cached health status: $_lastServerHealthy');
      return _lastServerHealthy;
    }

    // Perform new health check
    try {
      _lastServerHealthy = await _onlineProvider!.isServerHealthy();
      _lastHealthCheck = now;
      debugPrint('HybridGrammarProvider: Fresh health check result: $_lastServerHealthy');
      return _lastServerHealthy;
    } catch (e) {
      debugPrint('HybridGrammarProvider: Health check failed: $e');
      _lastServerHealthy = false;
      _lastHealthCheck = now;
      return false;
    }
  }

  /// Notify about fallback events
  void _notifyFallback(String message, bool isWarning) {
    debugPrint('HybridGrammarProvider: $message');
    _onFallback?.call(message, isWarning);
  }

  /// Get current provider status
  Future<Map<String, dynamic>> getProviderStatus() async {
    final mode = _settingsService.grammarCorrectionMode;
    
    if (mode == GrammarCorrectionMode.offlineOnly) {
      return {
        'mode': mode.name,
        'online_available': false,
        'offline_available': true,
        'current_provider': 'offline',
      };
    }

    final onlineHealthy = _onlineProvider != null ? await _isServerHealthy() : false;
    
    return {
      'mode': mode.name,
      'online_available': onlineHealthy,
      'offline_available': true,
      'current_provider': onlineHealthy && mode != GrammarCorrectionMode.offlineOnly 
          ? 'online' 
          : 'offline',
      'server_url': _settingsService.serverUrl,
    };
  }

  @override
  void dispose() {
    debugPrint('HybridGrammarProvider: Disposing');
    _onlineProvider?.dispose();
    _offlineProvider.dispose();
  }
} 