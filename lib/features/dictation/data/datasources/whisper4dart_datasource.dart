import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper4dart/whisper4dart.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';

/// Whisper4Dart-based implementation of SpeechDatasource for Linux
class Whisper4DartDatasource implements SpeechDatasource {
  final AudioRecorder _audioRecorder = AudioRecorder();

  StreamController<SpeechResultModel>? _streamController;
  Timer? _transcriptionTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  bool _isRecording = false;
  bool _shouldKeepListening = false;
  String? _currentRecordingPath;
  int _recordingCounter = 0;
  bool _isTranscribing = false;
  final List<String> _accumulatedText = [];

  Whisper? _whisper;
  bool _isInitialized = false;

  /// Path to the Whisper model
  static String get _modelPath {
    final homeDir = Platform.environment['HOME'] ?? '/home/${Platform.environment['USER']}';
    return '$homeDir/Dokumente/whisper_models/ggml-base.bin';
  }

  @override
  Future<bool> initialize() async {
    debugPrint('Whisper4Dart: Initializing Whisper speech recognition');

    try {
      // Check if model exists
      if (!await File(_modelPath).exists()) {
        debugPrint('Whisper4Dart: ❌ Model not found at: $_modelPath');
        return false;
      }

      debugPrint('Whisper4Dart: Model found at: $_modelPath');

      // Create context parameters with CPU-only mode (no GPU)
      var cparams = createContextDefaultParams();
      // Note: whisper4dart doesn't expose GPU settings directly in params
      // The whisper.cpp library defaults to CPU when GPU is not available

      // Initialize Whisper with model
      _whisper = Whisper(_modelPath, cparams, outputMode: "plaintext");
      _isInitialized = true;

      debugPrint('Whisper4Dart: ✅ Initialization successful');

      // Check if we have recording permission
      final hasPermission = await _audioRecorder.hasPermission();
      debugPrint('Whisper4Dart: Has recording permission: $hasPermission');

      return hasPermission;
    } catch (e) {
      debugPrint('Whisper4Dart: ❌ Initialization failed: $e');
      debugPrint('Whisper4Dart: Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  @override
  Future<bool> checkPermissions() async {
    debugPrint('Whisper4Dart: Checking permissions');
    final hasPermission = await _audioRecorder.hasPermission();
    debugPrint('Whisper4Dart: Has permission: $hasPermission');
    return hasPermission;
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('Whisper4Dart: Requesting permissions');
    final hasPermission = await _audioRecorder.hasPermission();
    debugPrint('Whisper4Dart: Permission request result: $hasPermission');
    return hasPermission;
  }

  @override
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  }) async {
    debugPrint('Whisper4Dart: Starting continuous listening with locale: $localeId');

    // Initialize if not already done
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('Failed to initialize Whisper4Dart');
      }
    }

    // Ensure we have permission
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      debugPrint('Whisper4Dart: No recording permission');
      throw Exception('Recording permission denied');
    }

    _shouldKeepListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();

    await _startRecordingSession();
    _startAmplitudeMonitoring();

    return _streamController!.stream;
  }

  void _startAmplitudeMonitoring() {
    if (_amplitudeSubscription != null) return;

    try {
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 150))
          .listen((amplitude) {
        if (_shouldKeepListening) {
          _streamController?.add(SpeechResultModel(
            recognizedWords: '',
            hasConfidenceRating: false,
            confidence: 0.0,
            finalResult: false,
            soundLevel: amplitude.current,
          ));
        }
      });
    } catch (e) {
      debugPrint('Whisper4Dart: Failed to start amplitude monitoring: $e');
    }
  }

  Future<void> _startRecordingSession() async {
    if (!_shouldKeepListening || _isRecording) return;

    debugPrint('Whisper4Dart: Starting continuous recording session #${++_recordingCounter}');

    try {
      // Create temporary file for recording
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('Whisper4Dart: Recording to: $_currentRecordingPath');

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _accumulatedText.clear();
      debugPrint('Whisper4Dart: Continuous recording started successfully');

      // Schedule periodic transcription every 5 seconds
      _schedulePeriodicTranscription();

    } catch (e) {
      debugPrint('Whisper4Dart: Failed to start recording: $e');
      debugPrint('Whisper4Dart: Stack trace: ${StackTrace.current}');
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
    debugPrint('Whisper4Dart: 📸 Creating audio snapshot for periodic transcription');

    try {
      // Pause recording temporarily to create a snapshot
      final path = await _audioRecorder.stop();

      if (path == null || path.isEmpty) {
        debugPrint('Whisper4Dart: No recording path available for snapshot');
        _isTranscribing = false;
        if (_shouldKeepListening) {
          await _restartRecording();
        }
        return;
      }

      debugPrint('Whisper4Dart: Audio snapshot saved at: $path');

      // Immediately restart recording to minimize gap
      await _restartRecording();

      // Check if file exists and has content
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('Whisper4Dart: Snapshot file does not exist');
        _isTranscribing = false;
        return;
      }

      final fileSize = await file.length();
      debugPrint('Whisper4Dart: Snapshot file size: $fileSize bytes');

      if (fileSize < 1000) {
        debugPrint('Whisper4Dart: Snapshot too small, likely silence');
        await file.delete();
        _isTranscribing = false;
        return;
      }

      // Transcribe snapshot with Whisper4Dart
      debugPrint('Whisper4Dart: 🎤 Starting Whisper transcription of snapshot');
      final transcribeStart = DateTime.now();

      // Use whisper4dart to transcribe
      final result = await _whisper!.infer(
        path, // First positional parameter: input audio path
        numProcessors: 1, // Single processor for streaming mode
        translate: false, // Don't translate, keep original language
      );

      final transcribeDuration = DateTime.now().difference(transcribeStart);

      debugPrint('Whisper4Dart: Transcription completed in ${transcribeDuration.inMilliseconds}ms');
      debugPrint('Whisper4Dart: Result: "${result.trim()}"');

      if (result.trim().isNotEmpty) {
        final transcribedText = result.trim();

        // Add to accumulated text
        _accumulatedText.add(transcribedText);

        // Emit partial result with accumulated text
        _streamController?.add(SpeechResultModel(
          recognizedWords: _accumulatedText.join(' '),
          hasConfidenceRating: false,
          confidence: 0.8,
          finalResult: false,
        ));

        debugPrint('Whisper4Dart: ✅ Emitted partial result: "${_accumulatedText.join(' ')}"');
        debugPrint('Whisper4Dart: Accumulated segments: ${_accumulatedText.length}');
      } else {
        debugPrint('Whisper4Dart: ⚠️ Transcription returned empty result');
      }

      // Clean up snapshot file
      await file.delete();
      debugPrint('Whisper4Dart: Cleaned up snapshot file');

    } catch (e) {
      debugPrint('Whisper4Dart: ❌ Periodic transcription error: $e');
      debugPrint('Whisper4Dart: Error type: ${e.runtimeType}');
      debugPrint('Whisper4Dart: Stack trace: ${StackTrace.current}');

      // Try to restart recording if it stopped
      if (_shouldKeepListening && !_isRecording) {
        debugPrint('Whisper4Dart: Attempting to restart recording after error');
        await _restartRecording();
      }
    } finally {
      transcriptionStopwatch.stop();
      debugPrint('Whisper4Dart: 📊 Total periodic transcription cycle: ${transcriptionStopwatch.elapsedMilliseconds}ms');
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
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('Whisper4Dart: Recording restarted after snapshot');
    } catch (e) {
      debugPrint('Whisper4Dart: Failed to restart recording: $e');
      _isRecording = false;
    }
  }

  @override
  Future<void> stopListening() async {
    debugPrint('Whisper4Dart: Stopping listening');
    _shouldKeepListening = false;

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    // Cancel timers
    _transcriptionTimer?.cancel();
    _transcriptionTimer = null;

    // Stop recording if active and transcribe final chunk
    if (_isRecording) {
      try {
        final path = await _audioRecorder.stop();
        _isRecording = false;

        debugPrint('Whisper4Dart: Final recording stopped at: $path');

        // Transcribe the final chunk if it has content
        if (path != null && path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint('Whisper4Dart: Final chunk size: $fileSize bytes');

            if (fileSize >= 1000) {
              // Transcribe final chunk
              debugPrint('Whisper4Dart: Transcribing final chunk');
              final result = await _whisper!.infer(
                path, // First positional parameter: input audio path
                numProcessors: 1,
                translate: false,
              );

              if (result.trim().isNotEmpty) {
                _accumulatedText.add(result.trim());
                debugPrint('Whisper4Dart: Final chunk transcribed: "${result.trim()}"');
              }
            }

            await file.delete();
            debugPrint('Whisper4Dart: Cleaned up final recording');
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
          debugPrint('Whisper4Dart: Emitted final accumulated result: "$finalText"');
        }

      } catch (e) {
        debugPrint('Whisper4Dart: Error stopping recording: $e');
      }
    }

    await _streamController?.close();
    _streamController = null;
    debugPrint('Whisper4Dart: Listening stopped successfully');
  }

  @override
  Future<bool> isListening() async {
    final listening = _shouldKeepListening;
    debugPrint('Whisper4Dart: Is listening: $listening');
    return listening;
  }

  @override
  Future<List<String>> getAvailableLocales() async {
    debugPrint('Whisper4Dart: Getting available locales');
    final locales = ['de_DE', 'en_US', 'en_GB'];
    debugPrint('Whisper4Dart: Available locales: $locales');
    return locales;
  }

  /// Dispose resources
  Future<void> dispose() async {
    debugPrint('Whisper4Dart: Disposing resources');
    await stopListening();
    await _audioRecorder.dispose();
    _whisper = null;
    _isInitialized = false;
  }
}
