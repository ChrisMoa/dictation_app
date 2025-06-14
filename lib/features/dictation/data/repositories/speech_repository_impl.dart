import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/dictation/domain/entities/speech_result.dart';
import 'package:dictation_app/features/dictation/domain/repositories/speech_repository.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';

class SpeechRepositoryImpl implements SpeechRepository {
  final SpeechDatasource datasource;

  SpeechRepositoryImpl({required this.datasource});

  @override
  Future<Either<Failure, bool>> initialize() async {
    try {
      final result = await datasource.initialize();
      return Right(result);
    } catch (e) {
      return Left(SpeechFailure('Failed to initialize speech recognition: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> checkPermissions() async {
    try {
      final result = await datasource.checkPermissions();
      return Right(result);
    } catch (e) {
      return Left(SpeechFailure('Failed to check permissions: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> requestPermissions() async {
    try {
      final result = await datasource.requestPermissions();
      return Right(result);
    } catch (e) {
      return Left(SpeechFailure('Failed to request permissions: $e'));
    }
  }

  @override
  Future<Either<Failure, Stream<SpeechResult>>> startListening({
    String localeId = 'de_DE',
  }) async {
    try {
      final stream = await datasource.startListening(localeId: localeId);
      return Right(stream);
    } catch (e) {
      return Left(SpeechFailure('Failed to start listening: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> stopListening() async {
    try {
      await datasource.stopListening();
      return const Right(null);
    } catch (e) {
      return Left(SpeechFailure('Failed to stop listening: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> isListening() async {
    try {
      final result = await datasource.isListening();
      return Right(result);
    } catch (e) {
      return Left(SpeechFailure('Failed to check listening status: $e'));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getAvailableLocales() async {
    try {
      final result = await datasource.getAvailableLocales();
      return Right(result);
    } catch (e) {
      return Left(SpeechFailure('Failed to get available locales: $e'));
    }
  }
}

