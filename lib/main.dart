import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/core/dependency_injection.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/theme/app_theme.dart';
import 'package:dictation_app/features/dictation/presentation/pages/dictation_home_page.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_bloc.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_event.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_state.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_bloc.dart';
import 'package:dictation_app/features/overlay/presentation/widgets/overlay_widget.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const OverlayWidget(),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await setupDependencyInjection();
    
    // Initialize settings service
    final settingsService = getIt<SettingsService>();
    await settingsService.initialize();
    debugPrint('Main: Settings service initialized');
    
  } catch (e) {
    debugPrint('Error setting up dependencies: $e');
  }
  
  runApp(const DictationApp());
}

class DictationApp extends StatefulWidget {
  const DictationApp({super.key});

  @override
  State<DictationApp> createState() => _DictationAppState();
}

class _DictationAppState extends State<DictationApp> {
  @override
  void initState() {
    super.initState();
    _setupOverlayListener();
  }

  void _setupOverlayListener() {
    // Overlay is only supported on Android
    if (!Platform.isAndroid) {
      return;
    }

    FlutterOverlayWindow.overlayListener.listen((data) {
        final action = data['action'] as String?;

        switch (action) {
          case 'start_recording':
            _startDictationFromOverlay();
            break;
          case 'stop_recording':
            _stopDictationFromOverlay();
            break;
          case 'close_app':
            _closeAppFromOverlay();
            break;
        }
      });
  }

  void _startDictationFromOverlay() {
    final dictationBloc = context.read<DictationBloc>();
    dictationBloc.add(const StartDictationEvent());
  }

  void _stopDictationFromOverlay() {
    final dictationBloc = context.read<DictationBloc>();
    dictationBloc.add(StopDictationEvent());
  }

  void _closeAppFromOverlay() {
    // Speichere aktuellen Text in Zwischenablage vor dem Schließen
    final dictationBloc = context.read<DictationBloc>();
    final currentState = dictationBloc.state;
    
    if (currentState is DictationListening) {
      final finalText = currentState.currentText + currentState.partialText;
      if (finalText.isNotEmpty) {
        dictationBloc.add(SaveToClipboardEvent(finalText));
      }
    } else if (currentState is DictationStopped && currentState.finalText.isNotEmpty) {
      dictationBloc.add(SaveToClipboardEvent(currentState.finalText));
    }
    
    // App schließen nach kurzer Verzögerung
    Future.delayed(const Duration(milliseconds: 500), () {
      // Overlay schließen
      FlutterOverlayWindow.closeOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.surfaceLight,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<DictationBloc>(
          create: (context) => getIt<DictationBloc>(),
        ),
        BlocProvider<OverlayBloc>(
          create: (context) => getIt<OverlayBloc>(),
        ),
      ],
      child: MaterialApp(
        title: 'Dictation',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const DictationHomePage(),
      ),
    );
  }
}

