import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';

abstract class SpeechDatasource {
  Future<bool> initialize();
  Future<bool> checkPermissions();
  Future<bool> requestPermissions();
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  });
  Future<void> stopListening();
  Future<bool> isListening();
  Future<List<String>> getAvailableLocales();
}

class SpeechDatasourceImpl implements SpeechDatasource {
  final SpeechToText speechToText;
  StreamController<SpeechResultModel>? _streamController;
  Timer? _restartTimer;
  bool _shouldKeepListening = false;
  String _currentLocaleId = 'de_DE';

  SpeechDatasourceImpl({required this.speechToText});

  @override
  Future<bool> initialize() async {
    debugPrint('SpeechDatasource: Initializing speech recognition');
    final result = await speechToText.initialize();
    debugPrint('SpeechDatasource: Initialization result: $result');
    return result;
  }

  @override
  Future<bool> checkPermissions() async {
    debugPrint('SpeechDatasource: Checking permissions');

    // On Linux, skip permission check as speech_to_text doesn't support it
    if (Platform.isLinux) {
      debugPrint('SpeechDatasource: Linux detected - skipping permission check');
      return true;
    }

    final hasPermission = await speechToText.hasPermission;
    debugPrint('SpeechDatasource: Has permission: $hasPermission');
    return hasPermission;
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('SpeechDatasource: Requesting permissions');
    final result = await speechToText.initialize();
    debugPrint('SpeechDatasource: Permission request result: $result');
    return result;
  }

  @override
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  }) async {
    debugPrint('SpeechDatasource: Starting continuous listening with locale: $localeId');
    
    // Ensure speech recognition is initialized before starting
    if (!speechToText.isAvailable) {
      debugPrint('SpeechDatasource: Speech recognition not available, initializing...');
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('SpeechDatasource: Failed to initialize speech recognition');
        throw Exception('Failed to initialize speech recognition');
      }
    }
    
    _currentLocaleId = localeId;
    _shouldKeepListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();
    
    await _startListeningSession();
    
    return _streamController!.stream;
  }

  Future<void> _startListeningSession() async {
    if (!_shouldKeepListening) return;
    
    debugPrint('SpeechDatasource: Starting new listening session');
    
    await speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        debugPrint('SpeechDatasource: Received result - Words: "${result.recognizedWords}", Final: ${result.finalResult}, Confidence: ${result.confidence}');
        
        final speechResult = SpeechResultModel(
          recognizedWords: result.recognizedWords,
          hasConfidenceRating: result.hasConfidenceRating,
          confidence: result.confidence,
          finalResult: result.finalResult,
        );
        _streamController?.add(speechResult);
        
        // If this is a final result and we should keep listening, restart after a short delay
        if (result.finalResult && _shouldKeepListening) {
          debugPrint('SpeechDatasource: Final result received, scheduling restart in 500ms');
          _scheduleRestart();
        }
      },
      onSoundLevelChange: (level) {
        // Emit sound level changes for visual feedback
        if (_shouldKeepListening) {
          _streamController?.add(SpeechResultModel(
            recognizedWords: '',
            hasConfidenceRating: false,
            confidence: 0.0,
            finalResult: false,
            soundLevel: level,
          ));
        }
      },
      localeId: _currentLocaleId,
      listenOptions: SpeechListenOptions(
        onDevice: false, // Use cloud recognition for better accuracy
        cancelOnError: false,
        partialResults: true,
        autoPunctuation: true,
        enableHapticFeedback: true,
        listenMode: ListenMode.dictation, // Changed to dictation mode for continuous listening
      ),
    );
    
    // Set up multiple safety mechanisms
    _setupSafetyTimers();
  }
  
  void _setupSafetyTimers() {
    _restartTimer?.cancel();
    
    // Safety timer 1: Check if still listening every 10 seconds
    _restartTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_shouldKeepListening) {
        timer.cancel();
        return;
      }
      
      debugPrint('SpeechDatasource: Periodic check - isListening: ${speechToText.isListening}, shouldKeepListening: $_shouldKeepListening');
      
      // If we should be listening but aren't, restart
      if (_shouldKeepListening && !speechToText.isListening) {
        debugPrint('SpeechDatasource: Periodic check detected listening stopped, restarting...');
        timer.cancel();
        _restartListening();
      }
    });
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (_shouldKeepListening) {
        _restartListening();
      }
    });
  }

  Future<void> _restartListening() async {
    if (!_shouldKeepListening) return;
    
    debugPrint('SpeechDatasource: Restarting listening session');
    try {
      if (speechToText.isListening) {
        await speechToText.stop();
      }
      // Small delay before restarting
      await Future.delayed(const Duration(milliseconds: 200));
      await _startListeningSession();
    } catch (e) {
      debugPrint('SpeechDatasource: Error restarting listening: $e');
      // Try again after a longer delay
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(seconds: 2), () {
        if (_shouldKeepListening) {
          _restartListening();
        }
      });
    }
  }

  @override
  Future<void> stopListening() async {
    debugPrint('SpeechDatasource: Stopping listening');
    _shouldKeepListening = false;
    
    // Cancel all timers
    _restartTimer?.cancel();
    _restartTimer = null;
    
    try {
      if (speechToText.isListening) {
        await speechToText.stop();
      }
    } catch (e) {
      debugPrint('SpeechDatasource: Error stopping speech recognition: $e');
    }
    
    await _streamController?.close();
    _streamController = null;
    debugPrint('SpeechDatasource: Listening stopped successfully');
  }

  @override
  Future<bool> isListening() async {
    // Return true if we should be listening (even if temporarily paused)
    final shouldListen = _shouldKeepListening;
    final actuallyListening = speechToText.isListening;
    debugPrint('SpeechDatasource: Should be listening: $shouldListen, Actually listening: $actuallyListening');
    return shouldListen;
  }

  @override
  Future<List<String>> getAvailableLocales() async {
    debugPrint('SpeechDatasource: Getting available locales');
    final locales = await speechToText.locales();
    final localeIds = locales.map((locale) => locale.localeId).toList();
    debugPrint('SpeechDatasource: Available locales: $localeIds');
    return localeIds;
  }
}

