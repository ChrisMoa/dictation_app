import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/dictation/domain/repositories/speech_repository.dart';

class StopListening {
  final SpeechRepository repository;

  StopListening({required this.repository});

  Future<Either<Failure, void>> call() async {
    return repository.stopListening();
  }
}

