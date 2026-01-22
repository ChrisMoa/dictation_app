import 'package:dictation_app/features/dictation/domain/entities/speech_result.dart';

class SpeechResultModel extends SpeechResult {
  const SpeechResultModel({
    required super.recognizedWords,
    required super.hasConfidenceRating,
    required super.confidence,
    required super.finalResult,
    super.soundLevel,
  });

  factory SpeechResultModel.fromEntity(SpeechResult entity) {
    return SpeechResultModel(
      recognizedWords: entity.recognizedWords,
      hasConfidenceRating: entity.hasConfidenceRating,
      confidence: entity.confidence,
      finalResult: entity.finalResult,
      soundLevel: entity.soundLevel,
    );
  }
}

