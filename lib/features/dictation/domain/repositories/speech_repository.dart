import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/dictation/domain/entities/speech_result.dart';

abstract class SpeechRepository {
  Future<Either<Failure, bool>> initialize();
  Future<Either<Failure, bool>> checkPermissions();
  Future<Either<Failure, bool>> requestPermissions();
  Future<Either<Failure, Stream<SpeechResult>>> startListening({
    String localeId = 'de_DE',
  });
  Future<Either<Failure, void>> stopListening();
  Future<Either<Failure, bool>> isListening();
  Future<Either<Failure, List<String>>> getAvailableLocales();
}

