import 'package:equatable/equatable.dart';

abstract class DictationEvent extends Equatable {
  const DictationEvent();

  @override
  List<Object?> get props => [];
}

class StartDictationEvent extends DictationEvent {
  final String localeId;

  const StartDictationEvent({this.localeId = 'de_DE'});

  @override
  List<Object?> get props => [localeId];
}

class StopDictationEvent extends DictationEvent {}

class ClearTextEvent extends DictationEvent {}

class SaveToClipboardEvent extends DictationEvent {
  final String text;

  const SaveToClipboardEvent(this.text);

  @override
  List<Object?> get props => [text];
}

class SpeechResultReceivedEvent extends DictationEvent {
  final String recognizedWords;
  final bool finalResult;
  final double? soundLevel;

  const SpeechResultReceivedEvent({
    required this.recognizedWords,
    required this.finalResult,
    this.soundLevel,
  });

  @override
  List<Object?> get props => [recognizedWords, finalResult, soundLevel];
}

class SpellCheckRequestedEvent extends DictationEvent {
  final String text;
  const SpellCheckRequestedEvent(this.text);
  @override
  List<Object?> get props => [text];
}

class SpellCheckCompletedEvent extends DictationEvent {
  final String originalText;
  final String correctedText;
  final double confidence;
  const SpellCheckCompletedEvent({required this.originalText, required this.correctedText, required this.confidence});
  @override
  List<Object?> get props => [originalText, correctedText, confidence];
}

