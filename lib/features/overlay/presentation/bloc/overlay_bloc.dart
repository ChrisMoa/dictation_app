import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dictation_app/features/overlay/domain/usecases/show_overlay.dart';
import 'package:dictation_app/features/overlay/domain/usecases/hide_overlay.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_event.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_state.dart';

class OverlayBloc extends Bloc<OverlayEvent, OverlayState> {
  final ShowOverlay showOverlay;
  final HideOverlay hideOverlay;

  OverlayBloc({
    required this.showOverlay,
    required this.hideOverlay,
  }) : super(OverlayInitial()) {
    on<ShowOverlayEvent>(_onShowOverlay);
    on<HideOverlayEvent>(_onHideOverlay);
    on<CheckOverlayStatusEvent>(_onCheckOverlayStatus);
  }

  Future<void> _onShowOverlay(
    ShowOverlayEvent event,
    Emitter<OverlayState> emit,
  ) async {
    emit(OverlayLoading());
    
    final result = await showOverlay(event.config);
    
    result.fold(
      (failure) => emit(OverlayError(message: failure.message)),
      (_) => emit(OverlayVisible()),
    );
  }

  Future<void> _onHideOverlay(
    HideOverlayEvent event,
    Emitter<OverlayState> emit,
  ) async {
    emit(OverlayLoading());
    
    final result = await hideOverlay();
    
    result.fold(
      (failure) => emit(OverlayError(message: failure.message)),
      (_) => emit(OverlayHidden()),
    );
  }

  void _onCheckOverlayStatus(
    CheckOverlayStatusEvent event,
    Emitter<OverlayState> emit,
  ) {
    emit(OverlayHidden());
  }
}

