import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';
import 'package:dictation_app/features/dictation/data/models/speech_result_model.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';

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
  final List<String> _accumulatedText = [];
  bool _isTranscribing = false;
  String _currentLocaleId = 'de_DE';

  // Transcription interval - balanced for context vs responsiveness
  // Reduced from 10s to 7s for more responsive capture while maintaining context
  static const Duration _transcriptionInterval = Duration(seconds: 7);

  /// Validates if transcribed text is actual speech or just noise/gibberish
  /// This filters out Whisper hallucinations like [MUSIK], [Musik], etc.
  /// Balanced between being lenient and filtering obvious noise
  bool _isValidSpeech(String text, {bool isFinalChunk = false}) {
    // Remove extra whitespace and [] annotations for validation
    final cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    
    // Reject pure punctuation (e.g. ".", "!", "?")
    final textWithoutPunctuation = cleanText.replaceAll(RegExp(r'[.,!?;:\-—…\s]'), '');
    if (textWithoutPunctuation.isEmpty) {
      debugPrint('WhisperCLI: Filtered pure punctuation: "$text"');
      return false;
    }
    
    // Minimum length: 2 chars for final chunk, 3 for regular chunks
    final minLength = isFinalChunk ? 2 : 3;
    if (cleanText.length < minLength) {
      return false;
    }
    
    // Check for repetitive characters (e.g. "aaaaa", "hhhh")
    // Only reject if 5+ consecutive identical chars
    if (RegExp(r'(.)\1{5,}').hasMatch(cleanText)) {
      return false;
    }
    
    // Check for common Whisper hallucinations/noise patterns
    final lowerText = cleanText.toLowerCase();
    
    // Filter obvious hallucinations - compact list
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
        debugPrint('WhisperCLI: Filtered hallucination pattern: "$pattern" in "$text"');
        return false;
      }
    }
    
    // Check if text has reasonable letter content
    // At least 50% should be letters/numbers (not too strict, not too lenient)
    final alphanumericCount = cleanText.replaceAll(RegExp(r'[^a-zA-ZäöüÄÖÜß0-9]'), '').length;
    if (alphanumericCount < cleanText.length * 0.5) {
      return false;
    }
    
    // Check for minimum word count
    final words = cleanText.split(RegExp(r'\s+'));
    final validWords = words.where((w) => w.length >= 2).toList();
    
    // Need at least 1 valid word
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
        debugPrint('WhisperCLI: Filtered completely repetitive text: "$text"');
        return false;
      }
    }
    
    return true;
  }

  // Path to whisper.cpp executable
  static const String _whisperPath = '/tmp/whisper.cpp/build/bin/whisper-cli';

  // Get model path based on settings
  static String _getModelPath(WhisperModelSize modelSize) {
    final homeDir = Platform.environment['HOME'] ?? '/home/${Platform.environment['USER']}';
    final modelDir = '$homeDir/Dokumente/whisper_models';

    // Map model size to filename
    String modelFile;
    switch (modelSize) {
      case WhisperModelSize.tiny:
        modelFile = 'ggml-tiny.bin';
        break;
      case WhisperModelSize.base:
        modelFile = 'ggml-base.bin';
        break;
      case WhisperModelSize.small:
        modelFile = 'ggml-small.bin';
        break;
    }

    return '$modelDir/$modelFile';
  }

  @override
  Future<bool> initialize() async {
    debugPrint('WhisperCLI: Checking whisper.cpp installation');

    // Check if whisper.cpp is installed
    final whisperExists = await File(_whisperPath).exists();

    if (!whisperExists) {
      debugPrint('WhisperCLI: ⚠️ whisper.cpp not found at $_whisperPath');
      debugPrint('WhisperCLI: Please install whisper.cpp');
      return false;
    }

    // Get model size from settings
    final settingsService = getIt<SettingsService>();
    final modelSize = settingsService.whisperModelSize;
    final modelPath = _getModelPath(modelSize);

    debugPrint('WhisperCLI: Using model size from settings: ${modelSize.name}');
    debugPrint('WhisperCLI: Model path: $modelPath');

    final modelExists = await File(modelPath).exists();

    if (!modelExists) {
      debugPrint('WhisperCLI: ⚠️ Model not found at $modelPath');
      debugPrint('WhisperCLI: Please run the installation script to download the model');
      return false;
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
    debugPrint('WhisperCLI: Starting continuous listening with locale: $localeId');

    _currentLocaleId = localeId;
    _isListening = true;
    _streamController = StreamController<SpeechResultModel>.broadcast();
    _accumulatedText.clear();

    // Start continuous recording
    await _startRecording();

    // Schedule periodic transcription with longer interval for better context
    _schedulePeriodicTranscription();

    return _streamController!.stream;
  }

  Future<void> _startRecording() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/whisper_recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Use improved audio config with noise suppression
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          // Enable audio processing for better quality
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _currentRecordingPath!,
      );

      debugPrint('WhisperCLI: Recording started with noise suppression: $_currentRecordingPath');
    } catch (e) {
      debugPrint('WhisperCLI: Failed to start recording: $e');
      _streamController?.addError(e);
    }
  }

  void _schedulePeriodicTranscription() {
    _transcriptionTimer?.cancel();

    // Use longer interval (10s) for better Whisper context
    _transcriptionTimer = Timer.periodic(_transcriptionInterval, (timer) async {
      if (_isListening && !_isTranscribing) {
        await _performTranscription();
      } else if (!_isListening) {
        timer.cancel();
      }
    });
  }

  Future<void> _performTranscription() async {
    if (!_isListening || _currentRecordingPath == null || _isTranscribing) return;

    _isTranscribing = true;
    debugPrint('WhisperCLI: 📸 Creating audio snapshot');

    try {
      // Stop current recording to create snapshot
      final path = await _audioRecorder.stop();

      // Immediately restart recording to minimize gap
      if (_isListening) {
        await _startRecording();
      }

      if (path != null && await File(path).exists()) {
        // Check file size - skip if too small (likely silence)
        final fileSize = await File(path).length();
        debugPrint('WhisperCLI: Audio file size: $fileSize bytes');
        
        // Reduced threshold from 2000 to 800 bytes to capture shorter utterances
        // ~0.05 seconds of audio at 16kHz mono WAV
        if (fileSize < 800) {
          debugPrint('WhisperCLI: Audio too small, likely silence - skipping');
          await File(path).delete();
          _isTranscribing = false;
          return;
        }

        // Emit progress indicator
        _streamController?.add(
          SpeechResultModel(
            recognizedWords: _accumulatedText.isEmpty
                ? '🎤 Transkribiere...'
                : '${_accumulatedText.join(' ')} 🎤',
            hasConfidenceRating: false,
            confidence: 0.0,
            finalResult: false,
          ),
        );

        // Transcribe the audio file
        final text = await _transcribeFile(path);

        if (text.isNotEmpty && _isValidSpeech(text)) {
          _accumulatedText.add(text);

          // Send partial result
          _streamController?.add(
            SpeechResultModel(
              recognizedWords: _accumulatedText.join(' '),
              hasConfidenceRating: false,
              confidence: 0.9,
              finalResult: false,
            ),
          );
          debugPrint('WhisperCLI: ✅ Valid speech added: "$text"');
        } else if (text.isNotEmpty) {
          debugPrint('WhisperCLI: ⚠️ Filtered invalid/hallucinated text: "$text"');
        }

        // Delete temporary file
        await File(path).delete();
      }
    } catch (e) {
      debugPrint('WhisperCLI: Transcription error: $e');
      // Try to restart recording on error
      if (_isListening) {
        await _startRecording();
      }
    } finally {
      _isTranscribing = false;
    }
  }

  Future<String> _transcribeFile(String audioPath) async {
    try {
      debugPrint('WhisperCLI: Transcribing: $audioPath');

      // Get current model path from settings
      final settingsService = getIt<SettingsService>();
      final modelSize = settingsService.whisperModelSize;
      final modelPath = _getModelPath(modelSize);

      // Extract language from locale (e.g., 'de' from 'de_DE')
      final language = _currentLocaleId.split('_')[0];

      // Build initial prompt based on language to guide transcription
      // This helps reduce hallucinations significantly
      String initialPrompt;
      if (language == 'de') {
        initialPrompt = 'Diktat auf Deutsch. Klare Aussprache.';
      } else {
        initialPrompt = 'Dictation in English. Clear speech.';
      }

      // Run whisper.cpp CLI with optimized parameters for better accuracy
      final result = await Process.run(
        _whisperPath,
        [
          '-m', modelPath,
          '-f', audioPath,
          '-l', language,
          '--no-timestamps',
          '--output-txt',
          // Optimized for better speech capture:
          '--prompt', initialPrompt,           // Guide the model with context
          '--suppress-nst',                     // Suppress non-speech tokens
          '--no-speech-thold', '0.4',          // More lenient than 0.5 but not too low
          '--entropy-thold', '2.5',            // Balanced uncertainty threshold
          '--best-of', '5',                    // Consider more candidates
          '--beam-size', '5',                  // Better beam search
          '-t', '4',                           // Use 4 threads for faster processing
        ],
      );

      debugPrint('WhisperCLI: Exit code: ${result.exitCode}');
      if (result.stdout.toString().isNotEmpty) {
        debugPrint('WhisperCLI: stdout: ${result.stdout}');
      }
      if (result.stderr.toString().isNotEmpty) {
        debugPrint('WhisperCLI: stderr: ${result.stderr}');
      }

      if (result.exitCode == 0) {
        // Parse output - whisper.cpp outputs to a .txt file
        final txtPath = '$audioPath.txt';
        if (await File(txtPath).exists()) {
          var text = await File(txtPath).readAsString();
          await File(txtPath).delete(); // Clean up
          
          // Post-process: remove common bracket annotations
          text = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
          // Remove multiple spaces
          text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
          
          debugPrint('WhisperCLI: ✅ Transcribed (cleaned): "$text"');
          return text;
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
    _transcriptionTimer = null;

    // Wait for any ongoing transcription to complete
    while (_isTranscribing) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Stop recording and get final audio
    try {
      final path = await _audioRecorder.stop();

      if (path != null && await File(path).exists()) {
        final fileSize = await File(path).length();
        debugPrint('WhisperCLI: Final chunk size: $fileSize bytes');

        // Only transcribe if there's meaningful audio (very low threshold for final chunk)
        // Reduced from 1000 to 500 bytes to ensure we never lose the last words
        if (fileSize >= 500) {
          debugPrint('WhisperCLI: Processing final audio chunk...');
          
          // Add timeout to prevent hanging on final transcription
          try {
            final text = await _transcribeFile(path).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                debugPrint('WhisperCLI: ⏰ Final chunk transcription timed out');
                return '';
              },
            );

            if (text.isNotEmpty) {
              // For final chunk, be VERY aggressive about preserving text
              // First try normal validation with lenient final chunk settings
              if (_isValidSpeech(text, isFinalChunk: true)) {
                _accumulatedText.add(text);
                debugPrint('WhisperCLI: ✅ Final chunk added: "$text"');
              } else {
                // Enhanced recovery: extract ANY recognizable words from the text
                final cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
                final words = cleanText.split(RegExp(r'\s+'));
                
                // Accept words with 1+ characters that contain at least some letters
                final realWords = words.where((w) => 
                  w.isNotEmpty && RegExp(r'[a-zA-ZäöüÄÖÜß]').hasMatch(w)
                ).toList();
                
                if (realWords.isNotEmpty) {
                  final recoveredText = realWords.join(' ');
                  _accumulatedText.add(recoveredText);
                  debugPrint('WhisperCLI: 🔄 Recovered final words from filtered text: "$recoveredText"');
                } else {
                  // Last resort: if there's ANY alphabetic content, keep it
                  if (RegExp(r'[a-zA-ZäöüÄÖÜß]{2,}').hasMatch(cleanText)) {
                    _accumulatedText.add(cleanText);
                    debugPrint('WhisperCLI: 🆘 Last resort - keeping final chunk: "$cleanText"');
                  } else {
                    debugPrint('WhisperCLI: ⚠️ Final chunk contains no valid text: "$text"');
                  }
                }
              }
            } else {
              debugPrint('WhisperCLI: Final chunk transcription was empty');
            }
          } catch (e) {
            debugPrint('WhisperCLI: Final chunk transcription error: $e');
          }
        } else {
          debugPrint('WhisperCLI: Final chunk too small ($fileSize bytes), skipping');
          // Even if file is too small, log it prominently so user knows
          if (fileSize > 0) {
            debugPrint('WhisperCLI: ⚠️ Note: Last $fileSize bytes of audio were not transcribed (below 500 byte threshold)');
          }
        }

        await File(path).delete();
      }
    } catch (e) {
      debugPrint('WhisperCLI: Error in final transcription: $e');
    }

    // Send final result - ensure stream is still open
    final finalText = _accumulatedText.join(' ');
    debugPrint('WhisperCLI: 📝 Accumulated ${_accumulatedText.length} text chunks');
    debugPrint('WhisperCLI: 📝 Final text length: ${finalText.length} characters');
    
    if (_streamController != null && !_streamController!.isClosed) {
      _streamController!.add(
        SpeechResultModel(
          recognizedWords: finalText,
          hasConfidenceRating: false,
          confidence: 0.95,
          finalResult: true,
        ),
      );
      debugPrint('WhisperCLI: ✅ Final result sent to bloc: "$finalText"');
      debugPrint('WhisperCLI: Final result: "$finalText"');  // Specific format for compare_transcription.py
      
      // Small delay to ensure the final result is processed before closing
      await Future.delayed(const Duration(milliseconds: 100));
    } else {
      debugPrint('WhisperCLI: ⚠️ Stream controller is null or closed, cannot send final result');
      debugPrint('WhisperCLI: Final result (unsent): "$finalText"');  // Log anyway for debugging
    }

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
