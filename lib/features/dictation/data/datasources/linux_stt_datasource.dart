import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';

/// Linux-specific STT implementation
///
/// Since neither speech_to_text nor whisper_flutter_new support Linux,
/// this implementation provides a workaround using mock data for now.
///
/// Future implementation could use:
/// - Vosk for offline STT
/// - Web Speech API via webview
/// - Direct integration with cloud STT services
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
