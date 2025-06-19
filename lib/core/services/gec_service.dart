import 'dart:convert';
import 'package:http/http.dart' as http;

class CorrectionRequest {
  final String text;
  final int? maxLength;

  CorrectionRequest({
    required this.text,
    this.maxLength = 64,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'max_length': maxLength,
  };
}

class CorrectionResponse {
  final String originalText;
  final String correctedText;
  final double processingTime;
  final double? confidence;

  CorrectionResponse({
    required this.originalText,
    required this.correctedText,
    required this.processingTime,
    this.confidence,
  });

  factory CorrectionResponse.fromJson(Map<String, dynamic> json) {
    return CorrectionResponse(
      originalText: json['original_text'],
      correctedText: json['corrected_text'],
      processingTime: json['processing_time'].toDouble(),
      confidence: json['confidence']?.toDouble(),
    );
  }
}

class ModelInfo {
  final String modelType;
  final String modelSize;
  final int maxLength;
  final String supportedLanguage;

  ModelInfo({
    required this.modelType,
    required this.modelSize,
    required this.maxLength,
    required this.supportedLanguage,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      modelType: json['model_type'],
      modelSize: json['model_size'],
      maxLength: json['max_length'],
      supportedLanguage: json['supported_language'],
    );
  }
}

class GECService {
  static const String _baseUrl = 'http://localhost:8000';
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client = http.Client();

  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/v1/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['model_loaded'] == true;
      }
      return false;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }

  Future<ModelInfo?> getModelInfo() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/v1/models/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return ModelInfo.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      print('Model info request failed: $e');
      return null;
    }
  }

  Future<CorrectionResponse?> correctText(String text, {int? maxLength}) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    if (text.length > 1000) {
      throw ArgumentError('Text too long (max 1000 characters)');
    }

    try {
      final request = CorrectionRequest(
        text: text,
        maxLength: maxLength ?? 64,
      );

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/correct'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(request.toJson()),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return CorrectionResponse.fromJson(json.decode(response.body));
      } else if (response.statusCode == 400) {
        throw Exception('Bad request: ${response.body}');
      } else if (response.statusCode == 503) {
        throw Exception('Service unavailable: Model not loaded');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Text correction failed: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}