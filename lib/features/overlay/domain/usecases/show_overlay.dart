import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';
import 'package:dictation_app/features/overlay/domain/repositories/overlay_repository.dart';

class ShowOverlay {
  final OverlayRepository repository;

  ShowOverlay({required this.repository});

  Future<Either<Failure, void>> call(OverlayConfig config) async {
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
                return const Left(PermissionFailure('Overlay permission denied'));
              }
              return repository.showOverlay(config);
            },
          );
        }
        return repository.showOverlay(config);
      },
    );
  }
}

