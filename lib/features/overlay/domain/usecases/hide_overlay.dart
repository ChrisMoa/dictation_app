import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/overlay/domain/repositories/overlay_repository.dart';

class HideOverlay {
  final OverlayRepository repository;

  HideOverlay({required this.repository});

  Future<Either<Failure, void>> call() async {
    return repository.hideOverlay();
  }
}

