import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_bloc.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_event.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_state.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_bloc.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_event.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_state.dart' as overlay_state;
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';
import 'package:dictation_app/features/settings/presentation/pages/settings_page.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/whisper_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';

class DictationHomePage extends StatefulWidget {
  const DictationHomePage({super.key});

  @override
  State<DictationHomePage> createState() => _DictationHomePageState();
}

class _DictationHomePageState extends State<DictationHomePage> {
  final TextEditingController _textController = TextEditingController();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _setupFallbackListener();
    _setupWhisperContext();
  }

  void _setupWhisperContext() {
    // Set context for WhisperService to show download dialog
    try {
      final whisperService = getIt<WhisperService>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          whisperService.setDownloadContext(context);
        }
      });
    } catch (e) {
      debugPrint('Error setting up Whisper context: $e');
    }
  }

  void _setupFallbackListener() {
    // No longer needed with simplified text processing
    // Text processing now only uses Ollama or is disabled
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _startDictation() {
    context.read<DictationBloc>().add(const StartDictationEvent());
    setState(() {
      _isListening = true;
    });
  }

  void _stopDictation() {
    context.read<DictationBloc>().add(StopDictationEvent());
    setState(() {
      _isListening = false;
    });
  }

  void _clearText() {
    context.read<DictationBloc>().add(ClearTextEvent());
    _textController.clear();
  }

  void _saveToClipboard() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      context.read<DictationBloc>().add(SaveToClipboardEvent(text));
    }
  }

  void _showOverlay() {
    const config = OverlayConfig(
      width: 300,
      height: 120,
      flag: OverlayFlag.defaultFlag,
    );
    debugPrint('HomePage: Requesting overlay with config: width=${config.width}, height=${config.height}');
    
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Showing overlay...'),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );
    
    context.read<OverlayBloc>().add(const ShowOverlayEvent(config));
  }

  void _hideOverlay() {
    debugPrint('HomePage: Hiding overlay');
    context.read<OverlayBloc>().add(HideOverlayEvent());
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    ).then((_) {
      // Refresh fallback listener in case settings changed
      _setupFallbackListener();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictation App'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Grammar Correction Settings',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: BlocBuilder<DictationBloc, DictationState>(
            builder: (context, state) {
              if (state is DictationLoading || state is SpellCheckLoading) {
                return const LinearProgressIndicator(minHeight: 4.0);
              }
              return const SizedBox(height: 4.0);
            },
          ),
        ),
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<DictationBloc, DictationState>(
            listener: (context, state) {
              if (state is DictationListening) {
                _textController.text = state.currentText + state.partialText;
                setState(() {
                  _isListening = true;
                });
              } else if (state is DictationStopped) {
                _textController.text = state.finalText;
                setState(() {
                  _isListening = false;
                });
              } else if (state is SpellCheckLoading) {
                // Show loading indicator for spell check
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 16),
                        Text('Checking spelling...'),
                      ],
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else if (state is SpellCheckResultState) {
                _textController.text = state.correctedText;
                final hasCorrections = state.originalText != state.correctedText;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(hasCorrections 
                      ? 'Spell check complete! Text corrected with ${(state.confidence * 100).toStringAsFixed(1)}% confidence'
                      : 'Spell check complete! No corrections needed'),
                    backgroundColor: hasCorrections ? Colors.orange : Colors.green,
                  ),
                );
                setState(() {
                  _isListening = false;
                });
              } else if (state is DictationError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${state.message}')),
                );
                setState(() {
                  _isListening = false;
                });
              } else if (state is DictationTextSavedToClipboard) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Text saved to clipboard!')),
                );
              }
            },
          ),
          BlocListener<OverlayBloc, overlay_state.OverlayState>(
            listener: (context, state) {
              if (state is overlay_state.OverlayVisible) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Overlay shown - You can now minimize the app!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (state is overlay_state.OverlayHidden) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Overlay hidden')),
                );
              } else if (state is overlay_state.OverlayError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Overlay Error: ${state.message}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      hintText: 'Dictated text will appear here...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              BlocBuilder<DictationBloc, DictationState>(
                builder: (context, state) {
                  final isLoading = state is DictationLoading || state is SpellCheckLoading;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: isLoading ? null : (_isListening ? _stopDictation : _startDictation),
                        icon: Icon(_isListening ? Icons.stop : Icons.mic),
                        label: Text(_isListening ? 'Stop' : 'Start'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isListening ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: isLoading ? null : _clearText,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _saveToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showOverlay,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Show Overlay'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _hideOverlay,
                    icon: const Icon(Icons.close),
                    label: const Text('Hide Overlay'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

