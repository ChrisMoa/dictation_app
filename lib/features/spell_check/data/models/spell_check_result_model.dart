import 'package:equatable/equatable.dart';

class SpellCheckResultModel extends Equatable {
  final String originalText;
  final String correctedText;
  final List<SpellCheckError> errors;
  final double confidence;

  const SpellCheckResultModel({
    required this.originalText,
    required this.correctedText,
    required this.errors,
    required this.confidence,
  });

  @override
  List<Object?> get props => [originalText, correctedText, errors, confidence];
}

class SpellCheckError extends Equatable {
  final String word;
  final String suggestion;
  final int startIndex;
  final int endIndex;
  final double confidence;

  const SpellCheckError({
    required this.word,
    required this.suggestion,
    required this.startIndex,
    required this.endIndex,
    required this.confidence,
  });

  @override
  List<Object?> get props => [word, suggestion, startIndex, endIndex, confidence];
} 