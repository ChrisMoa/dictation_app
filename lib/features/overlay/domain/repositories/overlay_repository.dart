import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';

abstract class OverlayRepository {
  Future<Either<Failure, bool>> checkPermissions();
  Future<Either<Failure, bool>> requestPermissions();
  Future<Either<Failure, void>> showOverlay(OverlayConfig config);
  Future<Either<Failure, void>> hideOverlay();
  Future<Either<Failure, bool>> isOverlayVisible();
}

