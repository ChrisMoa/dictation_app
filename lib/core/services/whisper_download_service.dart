import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for downloading Whisper models with progress tracking
class WhisperDownloadService {
  /// Download a Whisper model with progress callback
  /// Returns the path to the downloaded file
  static Future<String> downloadModel({
    required String modelName,
    required String destinationPath,
    required Function(double progress, int downloaded, int total) onProgress,
  }) async {
    final url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$modelName.bin';
    final filePath = '$destinationPath/ggml-$modelName.bin';
    
    debugPrint('WhisperDownload: Starting download from: $url');
    debugPrint('WhisperDownload: Destination: $filePath');
    
    try {
      // Create HTTP client with streaming
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ?? 0;
      debugPrint('WhisperDownload: Total size: ${(contentLength / 1024 / 1024).toStringAsFixed(1)} MB');
      
      // Create file
      final file = File(filePath);
      final sink = file.openWrite();
      
      int downloaded = 0;
      
      // Stream download with progress
      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        if (contentLength > 0) {
          final progress = downloaded / contentLength;
          onProgress(progress, downloaded, contentLength);
          
          if (downloaded % (5 * 1024 * 1024) == 0 || downloaded == contentLength) {
            debugPrint('WhisperDownload: Progress: ${(progress * 100).toStringAsFixed(1)}% '
                '(${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB / '
                '${(contentLength / 1024 / 1024).toStringAsFixed(1)} MB)');
          }
        }
      }
      
      await sink.close();
      client.close();
      
      debugPrint('WhisperDownload: ✅ Download complete: $filePath');
      return filePath;
      
    } catch (e) {
      debugPrint('WhisperDownload: ❌ Download failed: $e');
      rethrow;
    }
  }
  
  /// Check if model file exists
  static Future<bool> modelExists(String modelName, String modelDir) async {
    final filePath = '$modelDir/ggml-$modelName.bin';
    final file = File(filePath);
    return await file.exists();
  }
  
  /// Get model file size if it exists
  static Future<int?> getModelSize(String modelName, String modelDir) async {
    final filePath = '$modelDir/ggml-$modelName.bin';
    final file = File(filePath);
    if (await file.exists()) {
      return await file.length();
    }
    return null;
  }
}
