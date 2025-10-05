import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';

/// Linux STT implementation using Whisper.cpp CLI
///
/// This uses the whisper.cpp command-line tool for speech-to-text
/// which needs to be installed separately:
/// ```bash
/// # Install whisper.cpp
/// git clone https://github.com/ggerganov/whisper.cpp.git
/// cd whisper.cpp
/// make
/// # Download model
/// bash ./models/download-ggml-model.sh base
/// ```
class WhisperCliLinuxDatasource implements SpeechDatasource {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamController<SpeechResultModel>? _streamController;
  bool _isListening = false;
  Timer? _transcriptionTimer;
  String? _currentRecordingPath;
  final StringBuffer _accumulatedText = StringBuffer();

  // Path to whisper.cpp executable
  static const String _whisperPath = '/tmp/whisper.cpp/build/bin/whisper-cli';
  // Path to model
  static const String _modelPath = '/home/chris/Dokumente/whisper_models/ggml-base.bin';

  @override
  Future<bool> initialize() async {
    debugPrint('WhisperCLI: Checking whisper.cpp installation');

    // Check if whisper.cpp is installed
    final whisperExists = await File(_whisperPath).exists();
    final modelExists = await File(_modelPath).exists();

    if (!whisperExists) {
      debugPrint('WhisperCLI: ⚠️ whisper.cpp not found at $_whisperPath');
      debugPrint('WhisperCLI: Please install whisper.cpp');
      return false;
    }

    if (!modelExists) {
      debugPrint('WhisperCLI: ⚠️ Model not found at $_modelPath');
      debugPrint('WhisperCLI: Using existing model from whisper_flutter_new');
      // Model exists from previous download, continue
    }

    debugPrint('WhisperCLI: Initialization successful');
    return true;
  }

  @override
  Future<bool> checkPermissions() async {
    return true; // No permissions needed on Linux
  }

  @override
  Future<bool> requestPermissions() async {
    return true;
  }

  @override
  Future<Stream<SpeechResultModel>> startListening({
    String localeId = 'de_DE',
  }) async {
    debugPrint('WhisperCLI: Starting continuous listening');

    _isListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();
    _accumulatedText.clear();

    // Start continuous recording
    await _startRecording();

    // Schedule periodic transcription every 5 seconds
    _schedulePeriodicTranscription();

    return _streamController!.stream;
  }

  Future<void> _startRecording() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/whisper_recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      debugPrint('WhisperCLI: Recording started: $_currentRecordingPath');
    } catch (e) {
      debugPrint('WhisperCLI: Failed to start recording: $e');
      _streamController?.addError(e);
    }
  }

  void _schedulePeriodicTranscription() {
    _transcriptionTimer?.cancel();

    _transcriptionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isListening) {
        await _performTranscription();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _performTranscription() async {
    if (!_isListening || _currentRecordingPath == null) return;

    debugPrint('WhisperCLI: 📸 Creating audio snapshot');

    try {
      // Stop current recording to create snapshot
      final path = await _audioRecorder.stop();

      if (path != null && await File(path).exists()) {
        // Transcribe the audio file
        final text = await _transcribeFile(path);

        if (text.isNotEmpty) {
          _accumulatedText.write(text);
          _accumulatedText.write(' ');

          // Send partial result
          _streamController?.add(
            SpeechResultModel(
              recognizedWords: _accumulatedText.toString().trim(),
              hasConfidenceRating: false,
              confidence: 0.9,
              finalResult: false,
            ),
          );
        }

        // Delete temporary file
        await File(path).delete();
      }

      // Restart recording if still listening
      if (_isListening) {
        await _startRecording();
      }
    } catch (e) {
      debugPrint('WhisperCLI: Transcription error: $e');
    }
  }

  Future<String> _transcribeFile(String audioPath) async {
    try {
      debugPrint('WhisperCLI: Transcribing: $audioPath');

      // Run whisper.cpp CLI
      final result = await Process.run(
        _whisperPath,
        [
          '-m', _modelPath,
          '-f', audioPath,
          '-l', 'de', // German language
          '--no-timestamps',
          '--output-txt', // Output as text
        ],
      );

      debugPrint('WhisperCLI: Exit code: ${result.exitCode}');
      debugPrint('WhisperCLI: stdout: ${result.stdout}');
      debugPrint('WhisperCLI: stderr: ${result.stderr}');

      if (result.exitCode == 0) {
        // Parse output - whisper.cpp outputs to a .txt file (appends .txt to original filename)
        final txtPath = '$audioPath.txt';
        debugPrint('WhisperCLI: Looking for output at: $txtPath');
        if (await File(txtPath).exists()) {
          final text = await File(txtPath).readAsString();
          await File(txtPath).delete(); // Clean up
          debugPrint('WhisperCLI: ✅ Transcribed: ${text.trim()}');
          return text.trim();
        } else {
          debugPrint('WhisperCLI: ⚠️ Output file not found');
        }
      } else {
        debugPrint('WhisperCLI: ❌ Whisper failed: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('WhisperCLI: Error transcribing: $e');
    }

    return '';
  }

  @override
  Future<void> stopListening() async {
    debugPrint('WhisperCLI: Stopping listening');

    _isListening = false;
    _transcriptionTimer?.cancel();

    // Stop recording and get final audio
    final path = await _audioRecorder.stop();

    if (path != null && await File(path).exists()) {
      // Transcribe final audio
      final text = await _transcribeFile(path);

      if (text.isNotEmpty) {
        _accumulatedText.write(text);
      }

      await File(path).delete();
    }

    // Send final result
    _streamController?.add(
      SpeechResultModel(
        recognizedWords: _accumulatedText.toString().trim(),
        hasConfidenceRating: false,
        confidence: 0.95,
        finalResult: true,
      ),
    );

    await _streamController?.close();
    _streamController = null;
    _accumulatedText.clear();
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
