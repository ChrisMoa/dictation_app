import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/core/dependency_injection.dart';
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
      theme: ThemeData.dark(),
      home: const OverlayWidget(),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await setupDependencyInjection();
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
        title: 'Dictation App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const DictationHomePage(),
      ),
    );
  }
}

