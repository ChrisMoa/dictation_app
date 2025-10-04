import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/whisper_download_service.dart';

/// Service for managing Whisper model and transcription
class WhisperService {
  static final WhisperService _instance = WhisperService._internal();
  factory WhisperService() => _instance;
  WhisperService._internal();

  Whisper? _whisper;
  bool _isInitialized = false;
  String? _currentModelPath;
  String? _localModelDir;
  BuildContext? _downloadContext;

  /// Convert WhisperModelSize to WhisperModel
  WhisperModel _getWhisperModel(WhisperModelSize size) {
    switch (size) {
      case WhisperModelSize.tiny:
        return WhisperModel.tiny;
      case WhisperModelSize.base:
        return WhisperModel.base;
      case WhisperModelSize.small:
        return WhisperModel.small;
    }
  }

  /// Set the context for showing download dialog
  void setDownloadContext(BuildContext context) {
    _downloadContext = context;
  }

  /// Download model with progress dialog
  Future<void> _downloadModelWithDialog(String modelName) async {
    if (_downloadContext == null || !_downloadContext!.mounted) {
      debugPrint('WhisperService: No context for dialog, skipping');
      return;
    }

    debugPrint('WhisperService: Showing download dialog for model: $modelName');
    
    // Show download dialog
    final result = await showDialog<bool>(
      context: _downloadContext!,
      barrierDismissible: false,
      builder: (context) => _WhisperDownloadDialog(
        modelName: modelName,
        destinationPath: _localModelDir!,
      ),
    );

    if (result == true) {
      debugPrint('WhisperService: ✅ Model download completed successfully');
    } else {
      debugPrint('WhisperService: ⚠️ Model download may have failed');
    }
  }

  /// Initialize Whisper with model from settings
  /// Note: medium and larger models crash in whisper_flutter_new v1.0.1
  Future<void> initialize({WhisperModelSize? modelSize, BuildContext? context}) async {
    if (context != null) {
      _downloadContext = context;
    }
    
    // Get model from settings if not provided
    final model = modelSize != null 
        ? _getWhisperModel(modelSize)
        : WhisperModel.base;
    if (_isInitialized && _currentModelPath == model.toString()) {
      debugPrint('WhisperService: Already initialized with model: $model');
      return;
    }

    debugPrint('WhisperService: Initializing with model: $model');

    try {
      // Get app's document directory for storing the model
      final appDir = await getApplicationDocumentsDirectory();
      _localModelDir = '${appDir.path}/whisper_models';

      debugPrint('WhisperService: Model directory: $_localModelDir');

      // Create models directory if it doesn't exist
      final modelDir = Directory(_localModelDir!);
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
        debugPrint('WhisperService: Created model directory');
      }

      // Check if model needs to be downloaded BEFORE initializing Whisper
      final modelPath = model.getPath(_localModelDir!);
      final modelFile = File(modelPath);
      
      if (!await modelFile.exists()) {
        debugPrint('WhisperService: ⚠️ Model not found, starting download...');
        
        // Download with progress dialog if context is available
        if (_downloadContext != null && _downloadContext!.mounted) {
          debugPrint('WhisperService: Showing download dialog');
          try {
            await _downloadModelWithDialog(model.modelName);
            debugPrint('WhisperService: ✅ Model download completed');
          } catch (e) {
            debugPrint('WhisperService: ❌ Model download failed: $e');
            rethrow;
          }
        } else {
          debugPrint('WhisperService: ⚠️ No context available for dialog');
          debugPrint('WhisperService: Model will be downloaded by whisper_flutter_new (no progress)');
        }
      } else {
        final fileSize = await modelFile.length();
        debugPrint('WhisperService: ✅ Model already exists (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');
      }

      // Initialize Whisper (model should exist now)
      debugPrint('WhisperService: Initializing Whisper with model: $model');
      _whisper = Whisper(
        model: model,
        modelDir: _localModelDir,
      );

      _currentModelPath = model.toString();
      _isInitialized = true;

      debugPrint('WhisperService: Initialization successful with model: $model');
      
      // Try to get Whisper version to verify library is working
      try {
        final version = await _whisper!.getVersion();
        debugPrint('WhisperService: ✅ Whisper library version: $version');
      } catch (e) {
        debugPrint('WhisperService: ⚠️ Could not get Whisper version: $e');
      }
    } catch (e) {
      debugPrint('WhisperService: Initialization failed: $e');
      debugPrint('WhisperService: Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Transcribe audio file to text
  Future<WhisperTranscriptionResult> transcribe({
    required String audioPath,
    bool isTranslate = false,
    bool isNoTimestamps = true,
    bool splitOnWord = true,
    String language = 'de',
  }) async {
    if (!_isInitialized || _whisper == null) {
      debugPrint('WhisperService: Not initialized, initializing now...');
      await initialize();
    }

    debugPrint('WhisperService: Starting transcription for audio: $audioPath');
    debugPrint('WhisperService: Parameters - translate: $isTranslate, noTimestamps: $isNoTimestamps, splitOnWord: $splitOnWord, language: $language');

    final stopwatch = Stopwatch()..start();

    try {
      // Check audio file size for performance analysis
      final audioFile = File(audioPath);
      final audioSize = await audioFile.length();
      debugPrint('WhisperService: Audio file size: ${audioSize} bytes (${(audioSize / 1024).toStringAsFixed(2)} KB)');
      
      debugPrint('WhisperService: Starting transcription (model: $_currentModelPath)...');
      final response = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          isTranslate: isTranslate,
          isNoTimestamps: isNoTimestamps,
          splitOnWord: splitOnWord,
          language: language,
        ),
      );

      stopwatch.stop();

      final transcribedText = response.text;
      final processingSpeed = audioSize / stopwatch.elapsedMilliseconds; // bytes per ms

      debugPrint('WhisperService: ✅ Transcription completed in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('WhisperService: Processing speed: ${(processingSpeed * 1000 / 1024).toStringAsFixed(2)} KB/s');
      debugPrint('WhisperService: Result: "$transcribedText"');
      debugPrint('WhisperService: Result length: ${transcribedText.length} characters');

      return WhisperTranscriptionResult(
        text: transcribedText,
        elapsedTimeMs: stopwatch.elapsedMilliseconds,
        success: true,
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('WhisperService: ❌ Transcription failed after ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('WhisperService: Error type: ${e.runtimeType}');
      debugPrint('WhisperService: Error message: $e');
      debugPrint('WhisperService: Stack trace: ${StackTrace.current}');
      
      // Check if it's a timeout or memory issue
      if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
        debugPrint('WhisperService: ⚠️ Possible timeout issue detected');
      }
      if (e.toString().contains('memory') || e.toString().contains('Memory')) {
        debugPrint('WhisperService: ⚠️ Possible memory issue detected');
      }

      return WhisperTranscriptionResult(
        text: '',
        elapsedTimeMs: stopwatch.elapsedMilliseconds,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get current model path
  String? get currentModelPath => _currentModelPath;

  /// Dispose resources
  void dispose() {
    debugPrint('WhisperService: Disposing resources');
    _whisper = null;
    _isInitialized = false;
    _currentModelPath = null;
  }
}

/// Dialog widget for showing download progress
class _WhisperDownloadDialog extends StatefulWidget {
  final String modelName;
  final String destinationPath;
  
  const _WhisperDownloadDialog({
    required this.modelName,
    required this.destinationPath,
  });

  @override
  State<_WhisperDownloadDialog> createState() => _WhisperDownloadDialogState();
}

class _WhisperDownloadDialogState extends State<_WhisperDownloadDialog> {
  double _progress = 0.0;
  int _downloaded = 0;
  int _total = 0;
  String _status = 'Starte Download...';
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      await WhisperDownloadService.downloadModel(
        modelName: widget.modelName,
        destinationPath: widget.destinationPath,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _downloaded = downloaded;
              _total = total;
              _status = 'Lade Whisper ${widget.modelName} Modell...';
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _isComplete = true;
          _status = 'Download abgeschlossen!';
        });
        
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = 'Download fehlgeschlagen';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => _isComplete || _error != null,
      child: AlertDialog(
        title: Row(
          children: [
            if (_isComplete)
              const Icon(Icons.check_circle, color: Colors.green)
            else if (_error != null)
              const Icon(Icons.error, color: Colors.red)
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isComplete ? 'Fertig!' : _error != null ? 'Fehler' : 'Download läuft',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            if (_error == null) ...[
              LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _isComplete ? Colors.green : Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_total > 0)
                    Text(
                      '${_formatBytes(_downloaded)} / ${_formatBytes(_total)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ] else ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Result of Whisper transcription
class WhisperTranscriptionResult {
  final String text;
  final int elapsedTimeMs;
  final bool success;
  final String? error;

  const WhisperTranscriptionResult({
    required this.text,
    required this.elapsedTimeMs,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    return 'WhisperTranscriptionResult(text: "$text", time: ${elapsedTimeMs}ms, success: $success${error != null ? ', error: $error' : ''})';
  }
}
