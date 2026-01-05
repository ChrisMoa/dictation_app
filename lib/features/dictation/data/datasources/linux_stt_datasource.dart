import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';

/// Linux-specific STT implementation (Legacy/Fallback)
///
/// NOTE: This is now a fallback implementation. Linux is now supported via whisper4dart.
/// The app will use WhisperDatasourceImpl for Linux by default (see dependency_injection.dart).
///
/// This mock implementation remains for compatibility but should not be used in production.
class LinuxSttDatasource implements SpeechDatasource {
  StreamController<SpeechResultModel>? _streamController;
  bool _isListening = false;

  @override
  Future<bool> initialize() async {
    debugPrint('LinuxSTT: Initializing (mock implementation)');
    return true;
  }

  @override
  Future<bool> checkPermissions() async {
    debugPrint('LinuxSTT: Checking permissions (always true on Linux)');
    return true;
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('LinuxSTT: Requesting permissions (always true on Linux)');
    return true;
  }

  @override
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  }) async {
    debugPrint('LinuxSTT: Starting listening (mock implementation)');

    _isListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();

    // Inform user that STT is not available on Linux
    _streamController?.add(
      SpeechResultModel(
        recognizedWords: '⚠️ STT nicht verfügbar auf Linux. Bitte verwenden Sie die App auf Android/iOS.',
        hasConfidenceRating: false,
        confidence: 0.0,
        finalResult: true,
      ),
    );

    return _streamController!.stream;
  }

  @override
  Future<void> stopListening() async {
    debugPrint('LinuxSTT: Stopping listening');
    _isListening = false;
    await _streamController?.close();
    _streamController = null;
  }

  @override
  Future<bool> isListening() async {
    return _isListening;
  }

  @override
  Future<List<String>> getAvailableLocales() async {
    return ['de_DE', 'en_US'];
  }
}
