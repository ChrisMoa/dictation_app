import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/dictation/domain/entities/speech_result.dart';
import 'package:dictation_app/features/dictation/domain/repositories/speech_repository.dart';

class StartListening {
  final SpeechRepository repository;

  StartListening({required this.repository});

  Future<Either<Failure, Stream<SpeechResult>>> call({
    String localeId = 'de_DE',
  }) async {
    final permissionResult = await repository.checkPermissions();
    
    return permissionResult.fold(
      (failure) => Left(failure),
      (hasPermission) async {
        if (!hasPermission) {
          final requestResult = await repository.requestPermissions();
          return requestResult.fold(
            (failure) => Left(failure),
            (granted) async {
              if (!granted) {
                return const Left(PermissionFailure('Microphone permission denied'));
              }
              return repository.startListening(localeId: localeId);
            },
          );
        }
        return repository.startListening(localeId: localeId);
      },
    );
  }
}

