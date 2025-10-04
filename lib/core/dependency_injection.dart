import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/ollama_grammar_provider.dart';
import 'package:dictation_app/core/services/whisper_service.dart';
import 'package:dictation_app/features/dictation/data/repositories/speech_repository_impl.dart';
import 'package:dictation_app/features/dictation/data/datasources/speech_datasource.dart';
import 'package:dictation_app/features/dictation/data/datasources/whisper_datasource.dart';
import 'package:dictation_app/features/dictation/domain/repositories/speech_repository.dart';
import 'package:dictation_app/features/dictation/domain/usecases/start_listening.dart';
import 'package:dictation_app/features/dictation/domain/usecases/stop_listening.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_bloc.dart';
import 'package:dictation_app/features/overlay/data/repositories/overlay_repository_impl.dart';
import 'package:dictation_app/features/overlay/data/datasources/overlay_datasource.dart';
import 'package:dictation_app/features/overlay/domain/repositories/overlay_repository.dart';
import 'package:dictation_app/features/overlay/domain/usecases/show_overlay.dart';
import 'package:dictation_app/features/overlay/domain/usecases/hide_overlay.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_bloc.dart';
import 'package:dictation_app/features/spell_check/data/datasources/spell_check_datasource.dart';

final getIt = GetIt.instance;

Future<void> setupDependencyInjection() async {
  debugPrint('DI: Starting dependency injection setup');
  
  try {
    // External Dependencies
    debugPrint('DI: Registering external dependencies');
    getIt.registerLazySingleton<SpeechToText>(() => SpeechToText());
    debugPrint('DI: SpeechToText registered');

    // Whisper Service
    debugPrint('DI: Registering Whisper Service');
    getIt.registerLazySingleton<WhisperService>(() => WhisperService());
    debugPrint('DI: WhisperService registered');

    // Settings Service (initialize first)
    debugPrint('DI: Registering Settings Service');
    getIt.registerLazySingleton<SettingsService>(() => SettingsService());
    debugPrint('DI: SettingsService registered');
    
    // AI Grammar Service with Ollama Provider only (GEC removed)
    debugPrint('DI: Registering AI Grammar Service');
    getIt.registerLazySingleton<AIGrammarService>(() {
      final aiService = AIGrammarService();
      final settingsService = getIt<SettingsService>();
      final ollamaProvider = OllamaGrammarProvider(
        ollamaUrl: settingsService.ollamaUrl,
        modelName: settingsService.ollamaModel,
        customPrompt: settingsService.ollamaPrompt,
      );
      aiService.setProvider(ollamaProvider);
      return aiService;
    });
    debugPrint('DI: AIGrammarService with Ollama Provider registered (GEC removed)');
    
    // Data Sources
    debugPrint('DI: Registering data sources');
    // Register both STT datasources as singletons
    getIt.registerLazySingleton<WhisperDatasourceImpl>(
      () {
        debugPrint('DI: Creating WhisperDatasourceImpl instance');
        return WhisperDatasourceImpl(whisperService: getIt());
      },
    );
    debugPrint('DI: WhisperDatasourceImpl registered');
    
    getIt.registerLazySingleton<SpeechDatasourceImpl>(
      () {
        debugPrint('DI: Creating SpeechDatasourceImpl instance');
        return SpeechDatasourceImpl(speechToText: getIt());
      },
    );
    debugPrint('DI: SpeechDatasourceImpl registered');
    
    // Register the active STT datasource based on settings
    // IMPORTANT: This is evaluated ONCE at startup based on initial settings
    // App restart required after changing STT engine in settings
    getIt.registerLazySingleton<SpeechDatasource>(
      () {
        final settingsService = getIt<SettingsService>();
        final sttEngine = settingsService.sttEngine;
        debugPrint('DI: ⚙️ Selecting STT engine: ${sttEngine.name}');
        
        if (sttEngine == SttEngine.whisper) {
          debugPrint('DI: ✅ Using Whisper (Offline) as primary STT');
          return getIt<WhisperDatasourceImpl>();
        } else {
          debugPrint('DI: ✅ Using Google STT (Online) as primary STT');
          return getIt<SpeechDatasourceImpl>();
        }
      },
    );
    debugPrint('DI: Primary SpeechDatasource registered (dynamic based on settings)');
    
    getIt.registerLazySingleton<OverlayDatasource>(
      () => OverlayDatasourceImpl(),
    );
    debugPrint('DI: OverlayDatasource registered');
    
    getIt.registerLazySingleton<SpellCheckDatasource>(
      () => SpellCheckDatasourceImpl(),
    );
    debugPrint('DI: SpellCheckDatasource registered');
    
    // Repositories
    debugPrint('DI: Registering repositories');
    getIt.registerLazySingleton<SpeechRepository>(
      () => SpeechRepositoryImpl(datasource: getIt()),
    );
    debugPrint('DI: SpeechRepository registered');
    
    getIt.registerLazySingleton<OverlayRepository>(
      () => OverlayRepositoryImpl(datasource: getIt()),
    );
    debugPrint('DI: OverlayRepository registered');
    
    // Use Cases
    debugPrint('DI: Registering use cases');
    getIt.registerLazySingleton<StartListening>(
      () => StartListening(repository: getIt()),
    );
    debugPrint('DI: StartListening registered');
    
    getIt.registerLazySingleton<StopListening>(
      () => StopListening(repository: getIt()),
    );
    debugPrint('DI: StopListening registered');
    
    getIt.registerLazySingleton<ShowOverlay>(
      () => ShowOverlay(repository: getIt()),
    );
    debugPrint('DI: ShowOverlay registered');
    
    getIt.registerLazySingleton<HideOverlay>(
      () => HideOverlay(repository: getIt()),
    );
    debugPrint('DI: HideOverlay registered');
    
    // BLoCs
    debugPrint('DI: Registering BLoCs');
    getIt.registerFactory<DictationBloc>(
      () => DictationBloc(
        startListening: getIt(),
        stopListening: getIt(),
        spellCheckDatasource: getIt(),
      ),
    );
    debugPrint('DI: DictationBloc registered');
    
    getIt.registerFactory<OverlayBloc>(
      () => OverlayBloc(
        showOverlay: getIt(),
        hideOverlay: getIt(),
      ),
    );
    debugPrint('DI: OverlayBloc registered');
    
    debugPrint('DI: Dependency injection setup completed successfully');
    
  } catch (e) {
    debugPrint('DI: Error during dependency injection setup: $e');
    rethrow;
  }
}

