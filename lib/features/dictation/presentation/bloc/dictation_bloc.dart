import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipboard/clipboard.dart';
import 'package:dictation_app/features/dictation/domain/usecases/start_listening.dart';
import 'package:dictation_app/features/dictation/domain/usecases/stop_listening.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_event.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_state.dart';
import 'package:dictation_app/features/spell_check/data/datasources/spell_check_datasource.dart';

class DictationBloc extends Bloc<DictationEvent, DictationState> {
  final StartListening startListening;
  final StopListening stopListening;
  final SpellCheckDatasource spellCheckDatasource;
  
  StreamSubscription? _speechSubscription;
  String _currentText = '';
  String _partialText = '';

  DictationBloc({
    required this.startListening,
    required this.stopListening,
    required this.spellCheckDatasource,
  }) : super(DictationInitial()) {
    debugPrint('DictationBloc: Initializing DictationBloc');
    on<StartDictationEvent>(_onStartDictation);
    on<StopDictationEvent>(_onStopDictation);
    on<ClearTextEvent>(_onClearText);
    on<SaveToClipboardEvent>(_onSaveToClipboard);
    on<SpeechResultReceivedEvent>(_onSpeechResultReceived);
    on<SpellCheckRequestedEvent>(_onSpellCheckRequested);
    on<SpellCheckCompletedEvent>(_onSpellCheckCompleted);
    debugPrint('DictationBloc: DictationBloc initialized successfully');
  }

  Future<void> _onStartDictation(
    StartDictationEvent event,
    Emitter<DictationState> emit,
  ) async {
    debugPrint('DictationBloc: Starting dictation with locale: ${event.localeId}');
    emit(DictationLoading());
    
    final result = await startListening(localeId: event.localeId);
    
    result.fold(
      (failure) {
        debugPrint('DictationBloc: Failed to start dictation: ${failure.message}');
        emit(DictationError(message: failure.message));
      },
      (stream) {
        debugPrint('DictationBloc: Successfully started dictation, setting up speech stream');
        _speechSubscription = stream.listen(
          (speechResult) {
            debugPrint('DictationBloc: Received speech result - Words: "${speechResult.recognizedWords}", Final: ${speechResult.finalResult}');
            add(SpeechResultReceivedEvent(
              recognizedWords: speechResult.recognizedWords,
              finalResult: speechResult.finalResult,
            ));
          },
          onError: (error) {
            debugPrint('DictationBloc: Speech recognition error: $error');
            // Only use add() in stream listeners, never emit() directly
            add(StopDictationEvent());
          },
        );
        
        debugPrint('DictationBloc: Emitting DictationListening state');
        emit(DictationListening(
          currentText: _currentText,
          partialText: _partialText,
        ));
      },
    );
  }

  Future<void> _onStopDictation(
    StopDictationEvent event,
    Emitter<DictationState> emit,
  ) async {
    debugPrint('DictationBloc: Stopping dictation');
    await _speechSubscription?.cancel();
    _speechSubscription = null;
    debugPrint('DictationBloc: Speech subscription cancelled');
    
    final result = await stopListening();
    
    result.fold(
      (failure) {
        debugPrint('DictationBloc: Failed to stop dictation: ${failure.message}');
        emit(DictationError(message: failure.message));
      },
      (_) {
        final finalText = _currentText + _partialText;
        debugPrint('DictationBloc: Dictation stopped successfully. Final text: "$finalText"');
        _currentText = finalText;
        _partialText = '';
        
        // Always emit DictationStopped first to update UI
        emit(DictationStopped(finalText: finalText));
        
        // Then run spell check if there's text to check
        if (finalText.trim().isNotEmpty) {
          debugPrint('DictationBloc: Requesting spell check for final text');
          add(SpellCheckRequestedEvent(finalText));
        } else {
          debugPrint('DictationBloc: No text to spell check');
        }
      },
    );
  }

  void _onClearText(
    ClearTextEvent event,
    Emitter<DictationState> emit,
  ) {
    debugPrint('DictationBloc: Clearing text');
    _currentText = '';
    _partialText = '';
    emit(DictationStopped(finalText: ''));
    debugPrint('DictationBloc: Text cleared successfully');
  }

  Future<void> _onSaveToClipboard(
    SaveToClipboardEvent event,
    Emitter<DictationState> emit,
  ) async {
    debugPrint('DictationBloc: Saving text to clipboard: "${event.text}"');
    try {
      await FlutterClipboard.copy(event.text);
      debugPrint('DictationBloc: Text saved to clipboard successfully');
      emit(DictationTextSavedToClipboard(text: event.text));
    } catch (e) {
      debugPrint('DictationBloc: Failed to save to clipboard: $e');
      emit(DictationError(message: 'Failed to save to clipboard: $e'));
    }
  }

  void _onSpeechResultReceived(
    SpeechResultReceivedEvent event,
    Emitter<DictationState> emit,
  ) {
    debugPrint('DictationBloc: Processing speech result - Words: "${event.recognizedWords}", Final: ${event.finalResult}');
    
    if (event.finalResult) {
      _currentText = '$_currentText${event.recognizedWords} ';
      _partialText = '';
      debugPrint('DictationBloc: Final result processed. Current text: "$_currentText"');
    } else {
      _partialText = event.recognizedWords;
      debugPrint('DictationBloc: Partial result processed. Partial text: "$_partialText"');
    }
    
    emit(DictationListening(
      currentText: _currentText,
      partialText: _partialText,
    ));
  }

  Future<void> _onSpellCheckRequested(
    SpellCheckRequestedEvent event,
    Emitter<DictationState> emit,
  ) async {
    debugPrint('DictationBloc: Spell check requested for text: "${event.text}"');
    
    // Emit a loading state for spell check
    emit(SpellCheckLoading(originalText: event.text));
    
    try {
      debugPrint('DictationBloc: Initializing spell check datasource');
      final initResult = await spellCheckDatasource.initialize();
      
      if (!initResult) {
        debugPrint('DictationBloc: Spell check initialization failed');
        // Fall back to showing the original text without spell check
        emit(DictationStopped(finalText: event.text));
        return;
      }
      
      debugPrint('DictationBloc: Spell check initialized successfully, running check');
      final result = await spellCheckDatasource.checkText(event.text);
      
      debugPrint('DictationBloc: Spell check completed successfully');
      debugPrint('DictationBloc: Original: "${result.originalText}"');
      debugPrint('DictationBloc: Corrected: "${result.correctedText}"');
      debugPrint('DictationBloc: Confidence: ${result.confidence}');
      debugPrint('DictationBloc: Errors found: ${result.errors.length}');
      
      // Update the current text with the corrected version
      _currentText = result.correctedText;
      
      emit(SpellCheckResultState(
        originalText: result.originalText,
        correctedText: result.correctedText,
        confidence: result.confidence,
      ));
    } catch (e) {
      debugPrint('DictationBloc: Spell check failed with error: $e');
      debugPrint('DictationBloc: Stack trace: ${StackTrace.current}');
      // Fall back to showing the original text
      emit(DictationStopped(finalText: event.text));
    }
  }

  void _onSpellCheckCompleted(
    SpellCheckCompletedEvent event,
    Emitter<DictationState> emit,
  ) {
    debugPrint('DictationBloc: Spell check completed event received');
    debugPrint('DictationBloc: Original: "${event.originalText}"');
    debugPrint('DictationBloc: Corrected: "${event.correctedText}"');
    debugPrint('DictationBloc: Confidence: ${event.confidence}');
    
    emit(SpellCheckResultState(
      originalText: event.originalText,
      correctedText: event.correctedText,
      confidence: event.confidence,
    ));
  }

  @override
  Future<void> close() {
    debugPrint('DictationBloc: Closing DictationBloc');
    _speechSubscription?.cancel();
    return super.close();
  }
}

