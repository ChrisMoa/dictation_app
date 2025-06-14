import 'package:dartz/dartz.dart';
import 'package:dictation_app/core/error/failures.dart';
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';
import 'package:dictation_app/features/overlay/domain/repositories/overlay_repository.dart';
import 'package:dictation_app/features/overlay/data/datasources/overlay_datasource.dart';
import 'package:dictation_app/features/overlay/data/models/overlay_config_model.dart';

class OverlayRepositoryImpl implements OverlayRepository {
  final OverlayDatasource datasource;

  OverlayRepositoryImpl({required this.datasource});

  @override
  Future<Either<Failure, bool>> checkPermissions() async {
    try {
      final result = await datasource.checkPermissions();
      return Right(result);
    } catch (e) {
      return Left(OverlayFailure('Failed to check overlay permissions: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> requestPermissions() async {
    try {
      final result = await datasource.requestPermissions();
      return Right(result);
    } catch (e) {
      return Left(OverlayFailure('Failed to request overlay permissions: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> showOverlay(OverlayConfig config) async {
    try {
      final configModel = OverlayConfigModel.fromEntity(config);
      await datasource.showOverlay(configModel);
      return const Right(null);
    } catch (e) {
      return Left(OverlayFailure('Failed to show overlay: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> hideOverlay() async {
    try {
      await datasource.hideOverlay();
      return const Right(null);
    } catch (e) {
      return Left(OverlayFailure('Failed to hide overlay: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> isOverlayVisible() async {
    try {
      final result = await datasource.isOverlayVisible();
      return Right(result);
    } catch (e) {
      return Left(OverlayFailure('Failed to check overlay visibility: $e'));
    }
  }
}

