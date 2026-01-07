import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/core/theme/app_theme.dart';
import 'package:dictation_app/core/theme/components/components.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_bloc.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_event.dart';
import 'package:dictation_app/features/dictation/presentation/bloc/dictation_state.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_bloc.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_event.dart';
import 'package:dictation_app/features/overlay/presentation/bloc/overlay_state.dart' as overlay_state;
import 'package:dictation_app/features/overlay/domain/entities/overlay_config.dart';
import 'package:dictation_app/features/settings/presentation/pages/settings_page.dart';
import 'package:dictation_app/core/services/whisper_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';

class DictationHomePage extends StatefulWidget {
  const DictationHomePage({super.key});

  @override
  State<DictationHomePage> createState() => _DictationHomePageState();
}

class _DictationHomePageState extends State<DictationHomePage>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  bool _isListening = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupWhisperContext();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  void _setupWhisperContext() {
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

  @override
  void dispose() {
    _textController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _startDictation() {
    context.read<DictationBloc>().add(const StartDictationEvent());
    setState(() => _isListening = true);
  }

  void _stopDictation() {
    context.read<DictationBloc>().add(StopDictationEvent());
    setState(() => _isListening = false);
  }

  void _toggleDictation() {
    if (_isListening) {
      _stopDictation();
    } else {
      _startDictation();
    }
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
    context.read<OverlayBloc>().add(const ShowOverlayEvent(config));
  }

  void _hideOverlay() {
    context.read<OverlayBloc>().add(HideOverlayEvent());
  }

  void _openSettings() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
          const SettingsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : 
              isSuccess ? Icons.check_circle_outline : 
              Icons.info_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.error : 
                        isSuccess ? AppColors.success : 
                        null,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: MultiBlocListener(
          listeners: [
            BlocListener<DictationBloc, DictationState>(
              listener: (context, state) {
                if (state is DictationListening) {
                  _textController.text = state.currentText + state.partialText;
                  if (!_isListening) setState(() => _isListening = true);
                } else if (state is DictationProcessing) {
                  _textController.text = state.currentText;
                  if (_isListening) setState(() => _isListening = false);
                } else if (state is DictationStopped) {
                  _textController.text = state.finalText;
                  if (_isListening) setState(() => _isListening = false);
                } else if (state is SpellCheckLoading) {
                  _showSnackBar('Rechtschreibung wird geprüft...');
                } else if (state is SpellCheckResultState) {
                  _textController.text = state.correctedText;
                  final hasCorrections = state.originalText != state.correctedText;
                  _showSnackBar(
                    hasCorrections 
                      ? 'Text korrigiert (${(state.confidence * 100).toStringAsFixed(0)}% Konfidenz)'
                      : 'Keine Korrekturen nötig',
                    isSuccess: true,
                  );
                  if (_isListening) setState(() => _isListening = false);
                } else if (state is DictationError) {
                  _showSnackBar('Fehler: ${state.message}', isError: true);
                  if (_isListening) setState(() => _isListening = false);
                } else if (state is DictationTextSavedToClipboard) {
                  _showSnackBar('In Zwischenablage kopiert!', isSuccess: true);
                }
              },
            ),
            BlocListener<OverlayBloc, overlay_state.OverlayState>(
              listener: (context, state) {
                if (state is overlay_state.OverlayVisible) {
                  _showSnackBar('Overlay aktiv - App kann minimiert werden', isSuccess: true);
                } else if (state is overlay_state.OverlayHidden) {
                  _showSnackBar('Overlay geschlossen');
                } else if (state is overlay_state.OverlayError) {
                  _showSnackBar('Overlay Fehler: ${state.message}', isError: true);
                }
              },
            ),
          ],
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Header
                _buildHeader(theme, isDark),
                
                // Main content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        
                        // Status indicator
                        _buildStatusIndicator(),
                        
                        const SizedBox(height: AppSpacing.md),
                        
                        // Text area
                        Expanded(
                          child: BlocBuilder<DictationBloc, DictationState>(
                            builder: (context, state) {
                              final isSpellChecking = state is SpellCheckLoading;
                              return AppTextArea(
                                controller: _textController,
                                hintText: 'Tippe auf den Mikrofon-Button um zu diktieren...',
                                isActive: _isListening,
                                suffix: TextAreaActions(
                                  characterCount: _textController.text.length,
                                  onCopy: _textController.text.isNotEmpty 
                                    ? _saveToClipboard 
                                    : null,
                                  onClear: _textController.text.isNotEmpty 
                                    ? _clearText 
                                    : null,
                                  isSpellChecking: isSpellChecking,
                                ),
                              );
                            },
                          ),
                        ),
                        
                        const SizedBox(height: AppSpacing.lg),
                        
                        // Recording button
                        _buildRecordingSection(),
                        
                        const SizedBox(height: AppSpacing.md),
                        
                        // Quick actions
                        _buildQuickActions(),
                        
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // App icon and title
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dictation',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  'Sprache zu Text',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // Settings button
          AppIconButton(
            icon: Icons.settings_outlined,
            onPressed: _openSettings,
            tooltip: 'Einstellungen',
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return BlocBuilder<DictationBloc, DictationState>(
      builder: (context, state) {
        AppStatusType statusType;
        String statusText;

        if (state is DictationListening) {
          statusType = AppStatusType.success;
          statusText = 'Aufnahme läuft...';
        } else if (state is DictationProcessing) {
          statusType = AppStatusType.warning;
          statusText = 'Finalisiere Aufnahme...';
        } else if (state is DictationLoading || state is SpellCheckLoading) {
          statusType = AppStatusType.warning;
          statusText = state is SpellCheckLoading
            ? 'Rechtschreibprüfung...'
            : 'Verarbeitung...';
        } else if (state is DictationError) {
          statusType = AppStatusType.error;
          statusText = 'Fehler aufgetreten';
        } else {
          statusType = AppStatusType.neutral;
          statusText = 'Bereit';
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: AppStatusBadge(
            key: ValueKey(statusText),
            type: statusType,
            label: statusText,
          ),
        );
      },
    );
  }

  Widget _buildRecordingSection() {
    return BlocBuilder<DictationBloc, DictationState>(
      builder: (context, state) {
        final isLoading = state is DictationLoading;
        final isSpellChecking = state is SpellCheckLoading;
        final isProcessing = state is DictationProcessing;

        return Column(
          children: [
            RecordingButton(
              isRecording: _isListening,
              isProcessing: isLoading || isSpellChecking || isProcessing,
              onPressed: _toggleDictation,
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isListening ? 1.0 : 0.6,
              child: Text(
                _isListening ? 'Tippen zum Stoppen' : 'Tippen zum Starten',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return BlocBuilder<OverlayBloc, overlay_state.OverlayState>(
      builder: (context, state) {
        final isOverlayVisible = state is overlay_state.OverlayVisible;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _QuickActionButton(
              icon: isOverlayVisible 
                ? Icons.picture_in_picture_alt 
                : Icons.picture_in_picture_outlined,
              label: isOverlayVisible ? 'Overlay aus' : 'Overlay an',
              onTap: isOverlayVisible ? _hideOverlay : _showOverlay,
              isActive: isOverlayVisible,
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isActive 
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : (isDark ? AppColors.surfaceContainerHighDark : AppColors.surfaceContainerHighLight),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive 
                  ? theme.colorScheme.primary 
                  : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isActive 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
