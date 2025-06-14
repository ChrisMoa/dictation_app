import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';

class OverlayConfigModel extends OverlayConfig {
  const OverlayConfigModel({
    required super.width,
    required super.height,
    required super.flag,
  });

  factory OverlayConfigModel.fromEntity(OverlayConfig entity) {
    return OverlayConfigModel(
      width: entity.width,
      height: entity.height,
      flag: entity.flag,
    );
  }

  factory OverlayConfigModel.defaultConfig() {
    return const OverlayConfigModel(
      width: 120,
      height: 60,
      flag: OverlayFlag.defaultFlag,
    );
  }
}

