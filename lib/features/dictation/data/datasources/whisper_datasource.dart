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
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  bool _isRecording = false;
  bool _shouldKeepListening = false;
  String? _currentRecordingPath;
  String _currentLocaleId = 'de_DE';
  int _recordingCounter = 0;
  bool _isTranscribing = false;
  final List<String> _accumulatedText = [];

  WhisperDatasourceImpl({required this.whisperService});

  /// Validates if transcribed text is actual speech or just noise/gibberish
  /// Balanced between being lenient and filtering obvious noise
  bool _isValidSpeech(String text, {bool isFinalChunk = false}) {
    // Remove extra whitespace and [] annotations for validation
    final cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    
    // Reject pure punctuation (e.g. ".", "!", "?")
    final textWithoutPunctuation = cleanText.replaceAll(RegExp(r'[.,!?;:\-—…\s]'), '');
    if (textWithoutPunctuation.isEmpty) {
      debugPrint('WhisperDatasource: Filtered pure punctuation: "$text"');
      return false;
    }
    
    // Minimum length: 2 chars for final chunk, 3 for regular chunks
    final minLength = isFinalChunk ? 2 : 3;
    if (cleanText.length < minLength) {
      return false;
    }
    
    // Check for repetitive characters (e.g. "aaaaa", "hhhh")
    if (RegExp(r'(.)\1{5,}').hasMatch(cleanText)) {
      return false;
    }
    
    // Check for common Whisper hallucinations/noise patterns
    final lowerText = cleanText.toLowerCase();
    
    // Filter obvious hallucinations
    final noisePatterns = [
      'untertitel',
      'subtitle',
      'thanks for watching',
      'danke fürs zuschauen',
      'subscribe',
      'abonnieren',
      '♪',
      '♫',
      'youtube',
      '[musik]',
      '[music]',
      '[applaus]',
      '[applause]',
    ];
    
    // Reject if the ENTIRE text is a noise pattern
    for (final pattern in noisePatterns) {
      if (lowerText == pattern || lowerText == '[$pattern]') {
        debugPrint('WhisperDatasource: Filtered hallucination pattern: "$pattern"');
        return false;
      }
    }
    
    // Check if text has reasonable letter content (at least 50%)
    final alphanumericCount = cleanText.replaceAll(RegExp(r'[^a-zA-ZäöüÄÖÜß0-9]'), '').length;
    if (alphanumericCount < cleanText.length * 0.5) {
      return false;
    }
    
    // Check for minimum word count
    final words = cleanText.split(RegExp(r'\s+'));
    final validWords = words.where((w) => w.length >= 2).toList();
    
    if (validWords.isEmpty) {
      return false;
    }
    
    // For final chunks, be very lenient - accept any single word of 3+ letters
    if (isFinalChunk && validWords.length == 1 && validWords.first.length >= 3) {
      return true;
    }
    
    // Reject completely repetitive text (same word 4+ times)
    if (!isFinalChunk && validWords.length >= 4) {
      final uniqueWords = validWords.toSet();
      if (uniqueWords.length == 1) {
        debugPrint('WhisperDatasource: Filtered completely repetitive text: "$text"');
        return false;
      }
    }
    
    return true;
  }

  String _buildInitialPrompt({int maxWords = 20}) {
    if (_accumulatedText.isEmpty) return '';
    final words = _accumulatedText
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length <= maxWords) {
      return words.join(' ');
    }
    return words.sublist(words.length - maxWords).join(' ');
  }

  /// Remove duplicate words at chunk boundaries to prevent repetition from overlapping chunks
  String _deduplicateChunkBoundary(String newChunk) {
    if (_accumulatedText.isEmpty || newChunk.trim().isEmpty) {
      return newChunk;
    }

    final previousText = _accumulatedText.join(' ');
    final prevWords = previousText.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final newWords = newChunk.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (prevWords.isEmpty || newWords.isEmpty) {
      return newChunk;
    }

    // Check for overlap: see if the beginning of newChunk matches the end of previous text
    // We check up to the last 5 words of previous chunk
    final checkWindow = prevWords.length < 5 ? prevWords.length : 5;

    for (int overlapSize = checkWindow; overlapSize >= 2; overlapSize--) {
      final prevEnding = prevWords.sublist(prevWords.length - overlapSize);
      final newBeginning = newWords.length >= overlapSize
          ? newWords.sublist(0, overlapSize)
          : newWords;

      // Case-insensitive comparison for better matching
      bool matches = true;
      for (int i = 0; i < prevEnding.length && i < newBeginning.length; i++) {
        if (prevEnding[i].toLowerCase() != newBeginning[i].toLowerCase()) {
          matches = false;
          break;
        }
      }

      if (matches && prevEnding.length == newBeginning.length) {
        // Found overlap - remove the duplicate words from the beginning of new chunk
        final deduplicatedWords = newWords.sublist(overlapSize);
        final result = deduplicatedWords.join(' ');
        debugPrint('WhisperDatasource: Detected ${overlapSize}-word overlap, removed duplicates');
        debugPrint('WhisperDatasource: Original new chunk: "$newChunk"');
        debugPrint('WhisperDatasource: Deduplicated: "$result"');
        return result;
      }
    }

    return newChunk;
  }

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
      debugPrint('WhisperDatasource: Failed to start amplitude monitoring: $e');
    }
  }

  Future<void> _startRecordingSession() async {
    if (!_shouldKeepListening || _isRecording) return;

    debugPrint('WhisperDatasource: Starting continuous recording session #${++_recordingCounter}');

    try {
      // Create temporary file for recording
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('WhisperDatasource: Recording to: $_currentRecordingPath');

      // Start recording with noise suppression
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          // Enable noise suppression and echo cancellation
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
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

      // Reduced threshold from 1000 to 600 bytes to capture shorter utterances
      if (fileSize < 600) {
        debugPrint('WhisperDatasource: Snapshot too small, likely silence');
        await file.delete();
        _isTranscribing = false;
        return;
      }

      // Transcribe snapshot with Whisper in background
      debugPrint('WhisperDatasource: 🎤 Starting Whisper transcription of snapshot');
      final language = _currentLocaleId.split('_')[0]; // 'de' from 'de_DE'
      final prompt = _buildInitialPrompt();
      
      final transcribeStart = DateTime.now();
      final result = await whisperService.transcribe(
        audioPath: path,
        language: language,
        isTranslate: false,
        isNoTimestamps: true,
        splitOnWord: true,
        initialPrompt: prompt.isEmpty ? null : prompt,
      );
      final transcribeDuration = DateTime.now().difference(transcribeStart);

      debugPrint('WhisperDatasource: Snapshot transcription result: $result');
      debugPrint('WhisperDatasource: Total transcription time: ${transcribeDuration.inMilliseconds}ms');

      if (result.success && result.text.trim().isNotEmpty) {
        final transcribedText = result.text.trim();

        // Filter out gibberish/noise - only accept meaningful speech
        if (_isValidSpeech(transcribedText)) {
          // Remove any duplicate words at chunk boundaries
          final deduplicatedText = _deduplicateChunkBoundary(transcribedText);

          // Only add if there's still text after deduplication
          if (deduplicatedText.trim().isNotEmpty) {
            // Add to accumulated text
            _accumulatedText.add(deduplicatedText);

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
            debugPrint('WhisperDatasource: ⚠️ Chunk was completely deduplicated, skipping');
          }
        } else {
          debugPrint('WhisperDatasource: ⚠️ Filtered out invalid/noise text: "$transcribedText"');
        }
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
          // Enable noise suppression and echo cancellation
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
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

        debugPrint('WhisperDatasource: Final recording stopped at: $path');

        // Transcribe the final chunk if it has content
        if (path != null && path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint('WhisperDatasource: Final chunk size: $fileSize bytes');

            // Reduced threshold from 1000 to 500 bytes for final chunk
            if (fileSize >= 500) {
              // Transcribe final chunk with aggressive preservation
              debugPrint('WhisperDatasource: Transcribing final chunk');
              final language = _currentLocaleId.split('_')[0];
              final prompt = _buildInitialPrompt();
              final result = await whisperService.transcribe(
                audioPath: path,
                language: language,
                isTranslate: false,
                isNoTimestamps: true,
                splitOnWord: true,
                initialPrompt: prompt.isEmpty ? null : prompt,
              );

              if (result.success && result.text.trim().isNotEmpty) {
                final text = result.text.trim();

                // Aggressive final chunk preservation
                if (_isValidSpeech(text, isFinalChunk: true)) {
                  // Remove any duplicate words at chunk boundaries
                  final deduplicatedText = _deduplicateChunkBoundary(text);

                  if (deduplicatedText.trim().isNotEmpty) {
                    _accumulatedText.add(deduplicatedText);
                    debugPrint('WhisperDatasource: ✅ Final chunk added: "$deduplicatedText"');
                  } else {
                    debugPrint('WhisperDatasource: ⚠️ Final chunk was completely deduplicated');
                  }
                } else {
                  // Recovery: extract ANY recognizable words
                  final cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
                  final words = cleanText.split(RegExp(r'\s+'));
                  final realWords = words.where((w) =>
                    w.isNotEmpty && RegExp(r'[a-zA-ZäöüÄÖÜß]').hasMatch(w)
                  ).toList();

                  if (realWords.isNotEmpty) {
                    final recoveredText = realWords.join(' ');
                    final deduplicatedRecoveredText = _deduplicateChunkBoundary(recoveredText);
                    if (deduplicatedRecoveredText.trim().isNotEmpty) {
                      _accumulatedText.add(deduplicatedRecoveredText);
                      debugPrint('WhisperDatasource: 🔄 Recovered final words: "$deduplicatedRecoveredText"');
                    }
                  } else if (RegExp(r'[a-zA-ZäöüÄÖÜß]{2,}').hasMatch(cleanText)) {
                    final deduplicatedCleanText = _deduplicateChunkBoundary(cleanText);
                    if (deduplicatedCleanText.trim().isNotEmpty) {
                      _accumulatedText.add(deduplicatedCleanText);
                      debugPrint('WhisperDatasource: 🆘 Last resort - keeping final chunk: "$deduplicatedCleanText"');
                    }
                  }
                }
              }
            } else {
              debugPrint('WhisperDatasource: ⚠️ Final chunk too small ($fileSize bytes)');
            }

            await file.delete();
            debugPrint('WhisperDatasource: Cleaned up final recording');
          }
        }

        // Emit final accumulated result
        final finalText = _accumulatedText.join(' ');
        debugPrint('WhisperDatasource: 📝 Accumulated ${_accumulatedText.length} text chunks');
        debugPrint('WhisperDatasource: 📝 Final text length: ${finalText.length} characters');
        
        if (_accumulatedText.isNotEmpty) {
          _streamController?.add(SpeechResultModel(
            recognizedWords: finalText,
            hasConfidenceRating: false,
            confidence: 1.0,
            finalResult: true,
          ));
          debugPrint('WhisperDatasource: ✅ Emitted final accumulated result: "$finalText"');
          debugPrint('WhisperDatasource: Final result: "$finalText"');  // For compare_transcription.py
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
