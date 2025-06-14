import 'package:equatable/equatable.dart';

abstract class OverlayState extends Equatable {
  const OverlayState();

  @override
  List<Object> get props => [];
}

class OverlayInitial extends OverlayState {}

class OverlayLoading extends OverlayState {}

class OverlayVisible extends OverlayState {}

class OverlayHidden extends OverlayState {}

class OverlayError extends OverlayState {
  final String message;

  const OverlayError({required this.message});

  @override
  List<Object> get props => [message];
}

