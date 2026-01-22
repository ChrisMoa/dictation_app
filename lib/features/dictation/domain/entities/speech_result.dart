import 'package:equatable/equatable.dart';

class SpeechResult extends Equatable {
  final String recognizedWords;
  final bool hasConfidenceRating;
  final double confidence;
  final bool finalResult;
  final double? soundLevel;

  const SpeechResult({
    required this.recognizedWords,
    required this.hasConfidenceRating,
    required this.confidence,
    required this.finalResult,
    this.soundLevel,
  });

  @override
  List<Object?> get props => [recognizedWords, hasConfidenceRating, confidence, finalResult, soundLevel];
}

