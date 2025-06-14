import 'package:equatable/equatable.dart';

abstract class DictationState extends Equatable {
  const DictationState();

  @override
  List<Object> get props => [];
}

class DictationInitial extends DictationState {}

class DictationLoading extends DictationState {}

class DictationListening extends DictationState {
  final String currentText;
  final String partialText;

  const DictationListening({
    required this.currentText,
    required this.partialText,
  });

  @override
  List<Object> get props => [currentText, partialText];
}

class DictationStopped extends DictationState {
  final String finalText;

  const DictationStopped({required this.finalText});

  @override
  List<Object> get props => [finalText];
}

class DictationError extends DictationState {
  final String message;

  const DictationError({required this.message});

  @override
  List<Object> get props => [message];
}

class DictationTextSavedToClipboard extends DictationState {
  final String text;

  const DictationTextSavedToClipboard({required this.text});

  @override
  List<Object> get props => [text];
}

class SpellCheckLoading extends DictationState {
  final String originalText;

  const SpellCheckLoading({required this.originalText});

  @override
  List<Object> get props => [originalText];
}

class SpellCheckResultState extends DictationState {
  final String originalText;
  final String correctedText;
  final double confidence;
  const SpellCheckResultState({required this.originalText, required this.correctedText, required this.confidence});
  @override
  List<Object> get props => [originalText, correctedText, confidence];
}

