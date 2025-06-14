import 'package:equatable/equatable.dart';
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';

abstract class OverlayEvent extends Equatable {
  const OverlayEvent();

  @override
  List<Object> get props => [];
}

class ShowOverlayEvent extends OverlayEvent {
  final OverlayConfig config;

  const ShowOverlayEvent(this.config);

  @override
  List<Object> get props => [config];
}

class HideOverlayEvent extends OverlayEvent {}

class CheckOverlayStatusEvent extends OverlayEvent {}

