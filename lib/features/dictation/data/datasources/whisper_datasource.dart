import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';
import 'package:dictation_app/core/services/whisper_service.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';

/// Whisper-based implementation of SpeechDatasource
class WhisperDatasourceImpl implements SpeechDatasource {
  final WhisperService whisperService;
  final AudioRecorder _audioRecorder = AudioRecorder();

  StreamController<SpeechResultModel>? _streamController;
  Timer? _transcriptionTimer;
  bool _isRecording = false;
  bool _shouldKeepListening = false;
  String? _currentRecordingPath;
  String _currentLocaleId = 'de_DE';
  int _recordingCounter = 0;
  bool _isTranscribing = false;
  final List<String> _accumulatedText = [];

  WhisperDatasourceImpl({required this.whisperService});

  @override
  Future<bool> initialize() async {
    debugPrint('WhisperDatasource: Initializing Whisper speech recognition');

    try {
      // Get model size from settings
      final settingsService = getIt<SettingsService>();
      final modelSize = settingsService.whisperModelSize;
      debugPrint('WhisperDatasource: Using model size from settings: ${modelSize.name}');
      
      // Initialize Whisper service with selected model
      await whisperService.initialize(modelSize: modelSize);
      debugPrint('WhisperDatasource: Whisper service initialized successfully');

      // Check if we have recording permission
      final hasPermission = await _audioRecorder.hasPermission();
      debugPrint('WhisperDatasource: Has recording permission: $hasPermission');

      return hasPermission;
    } catch (e) {
      debugPrint('WhisperDatasource: Initialization failed: $e');
      return false;
    }
  }

  @override
  Future<bool> checkPermissions() async {
    debugPrint('WhisperDatasource: Checking permissions');
    final hasPermission = await _audioRecorder.hasPermission();
    debugPrint('WhisperDatasource: Has permission: $hasPermission');
    return hasPermission;
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('WhisperDatasource: Requesting permissions');
    final hasPermission = await _audioRecorder.hasPermission();
    debugPrint('WhisperDatasource: Permission request result: $hasPermission');
    return hasPermission;
  }

  @override
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  }) async {
    debugPrint('WhisperDatasource: Starting continuous listening with locale: $localeId');

    // Ensure we have permission
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      debugPrint('WhisperDatasource: No recording permission, requesting...');
      final granted = await _audioRecorder.hasPermission();
      if (!granted) {
        debugPrint('WhisperDatasource: Permission denied');
        throw Exception('Recording permission denied');
      }
    }

    _currentLocaleId = localeId;
    _shouldKeepListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();

    await _startRecordingSession();

    return _streamController!.stream;
  }

  Future<void> _startRecordingSession() async {
    if (!_shouldKeepListening || _isRecording) return;

    debugPrint('WhisperDatasource: Starting continuous recording session #${++_recordingCounter}');

    try {
      // Create temporary file for recording
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('WhisperDatasource: Recording to: $_currentRecordingPath');

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _accumulatedText.clear();
      debugPrint('WhisperDatasource: Continuous recording started successfully');

      // Schedule periodic transcription every 5 seconds
      _schedulePeriodicTranscription();

    } catch (e) {
      debugPrint('WhisperDatasource: Failed to start recording: $e');
      debugPrint('WhisperDatasource: Stack trace: ${StackTrace.current}');
      _streamController?.addError(e);
    }
  }

  void _schedulePeriodicTranscription() {
    _transcriptionTimer?.cancel();

    // Transcribe every 5 seconds for near real-time feedback
    _transcriptionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_shouldKeepListening && _isRecording && !_isTranscribing) {
        await _performPeriodicTranscription();
      } else if (!_shouldKeepListening || !_isRecording) {
        timer.cancel();
      }
    });
  }

  Future<void> _performPeriodicTranscription() async {
    if (!_isRecording || _currentRecordingPath == null || _isTranscribing) return;

    _isTranscribing = true;
    final transcriptionStopwatch = Stopwatch()..start();
    debugPrint('WhisperDatasource: 📸 Creating audio snapshot for periodic transcription');

    try {
      // Pause recording temporarily to create a snapshot
      final path = await _audioRecorder.stop();

      if (path == null || path.isEmpty) {
        debugPrint('WhisperDatasource: No recording path available for snapshot');
        _isTranscribing = false;
        if (_shouldKeepListening) {
          await _restartRecording();
        }
        return;
      }

      debugPrint('WhisperDatasource: Audio snapshot saved at: $path');

      // Immediately restart recording to minimize gap
      await _restartRecording();

      // Check if file exists and has content
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('WhisperDatasource: Snapshot file does not exist');
        _isTranscribing = false;
        return;
      }

      final fileSize = await file.length();
      debugPrint('WhisperDatasource: Snapshot file size: $fileSize bytes');

      if (fileSize < 1000) {
        debugPrint('WhisperDatasource: Snapshot too small, likely silence');
        await file.delete();
        _isTranscribing = false;
        return;
      }

      // Emit feedback that transcription is in progress
      _streamController?.add(SpeechResultModel(
        recognizedWords: _accumulatedText.isEmpty
            ? '🎤 Transkribiere...'
            : '${_accumulatedText.join(' ')} 🎤',
        hasConfidenceRating: false,
        confidence: 0.0,
        finalResult: false,
      ));

      // Transcribe snapshot with Whisper in background
      debugPrint('WhisperDatasource: 🎤 Starting Whisper transcription of snapshot');
      final language = _currentLocaleId.split('_')[0]; // 'de' from 'de_DE'
      
      final transcribeStart = DateTime.now();
      final result = await whisperService.transcribe(
        audioPath: path,
        language: language,
        isTranslate: false,
        isNoTimestamps: true,
        splitOnWord: true,
      );
      final transcribeDuration = DateTime.now().difference(transcribeStart);

      debugPrint('WhisperDatasource: Snapshot transcription result: $result');
      debugPrint('WhisperDatasource: Total transcription time: ${transcribeDuration.inMilliseconds}ms');

      if (result.success && result.text.trim().isNotEmpty) {
        // Add to accumulated text
        _accumulatedText.add(result.text.trim());

        // Emit partial result with accumulated text
        _streamController?.add(SpeechResultModel(
          recognizedWords: _accumulatedText.join(' '),
          hasConfidenceRating: false,
          confidence: 0.8,
          finalResult: false,
        ));

        debugPrint('WhisperDatasource: ✅ Emitted partial result: "${_accumulatedText.join(' ')}"');
        debugPrint('WhisperDatasource: Accumulated segments: ${_accumulatedText.length}');
      } else {
        debugPrint('WhisperDatasource: ❌ Snapshot transcription failed or empty: ${result.error}');
      }

      // Clean up snapshot file
      await file.delete();
      debugPrint('WhisperDatasource: Cleaned up snapshot file');

    } catch (e) {
      debugPrint('WhisperDatasource: ❌ Periodic transcription error: $e');
      debugPrint('WhisperDatasource: Error type: ${e.runtimeType}');
      debugPrint('WhisperDatasource: Stack trace: ${StackTrace.current}');

      // Try to restart recording if it stopped
      if (_shouldKeepListening && !_isRecording) {
        debugPrint('WhisperDatasource: Attempting to restart recording after error');
        await _restartRecording();
      }
    } finally {
      transcriptionStopwatch.stop();
      debugPrint('WhisperDatasource: 📊 Total periodic transcription cycle: ${transcriptionStopwatch.elapsedMilliseconds}ms');
      _isTranscribing = false;
    }
  }

  Future<void> _restartRecording() async {
    if (!_shouldKeepListening) return;

    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('WhisperDatasource: Recording restarted after snapshot');
    } catch (e) {
      debugPrint('WhisperDatasource: Failed to restart recording: $e');
      _isRecording = false;
    }
  }

  @override
  Future<void> stopListening() async {
    debugPrint('WhisperDatasource: Stopping listening');
    _shouldKeepListening = false;

    // Cancel timers
    _transcriptionTimer?.cancel();
    _transcriptionTimer = null;

    // Stop recording if active and transcribe final chunk
    if (_isRecording) {
      try {
        final path = await _audioRecorder.stop();
        _isRecording = false;

        debugPrint('WhisperDatasource: Final recording stopped at: $path');

        // Transcribe the final chunk if it has content
        if (path != null && path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint('WhisperDatasource: Final chunk size: $fileSize bytes');

            if (fileSize >= 1000) {
              // Transcribe final chunk
              debugPrint('WhisperDatasource: Transcribing final chunk');
              final language = _currentLocaleId.split('_')[0];
              final result = await whisperService.transcribe(
                audioPath: path,
                language: language,
                isTranslate: false,
                isNoTimestamps: true,
                splitOnWord: true,
              );

              if (result.success && result.text.trim().isNotEmpty) {
                _accumulatedText.add(result.text.trim());
                debugPrint('WhisperDatasource: Final chunk transcribed: "${result.text.trim()}"');
              }
            }

            await file.delete();
            debugPrint('WhisperDatasource: Cleaned up final recording');
          }
        }

        // Emit final accumulated result
        if (_accumulatedText.isNotEmpty) {
          final finalText = _accumulatedText.join(' ');
          _streamController?.add(SpeechResultModel(
            recognizedWords: finalText,
            hasConfidenceRating: false,
            confidence: 1.0,
            finalResult: true,
          ));
          debugPrint('WhisperDatasource: Emitted final accumulated result: "$finalText"');
        }

      } catch (e) {
        debugPrint('WhisperDatasource: Error stopping recording: $e');
      }
    }

    await _streamController?.close();
    _streamController = null;
    debugPrint('WhisperDatasource: Listening stopped successfully');
  }

  @override
  Future<bool> isListening() async {
    final listening = _shouldKeepListening;
    debugPrint('WhisperDatasource: Is listening: $listening');
    return listening;
  }

  @override
  Future<List<String>> getAvailableLocales() async {
    debugPrint('WhisperDatasource: Getting available locales');
    // Whisper supports many languages, but we'll focus on German for now
    final locales = ['de_DE', 'en_US', 'en_GB'];
    debugPrint('WhisperDatasource: Available locales: $locales');
    return locales;
  }

  /// Dispose resources
  Future<void> dispose() async {
    debugPrint('WhisperDatasource: Disposing resources');
    await stopListening();
    await _audioRecorder.dispose();
  }
}
