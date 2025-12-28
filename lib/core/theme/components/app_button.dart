import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';

/// Primary action button with icon
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonStyle style;
  final bool expanded;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.style = AppButtonStyle.primary,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget buttonChild = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                style == AppButtonStyle.primary 
                  ? Colors.white 
                  : theme.colorScheme.primary,
              ),
            ),
          )
        else if (icon != null)
          Icon(icon, size: 20),
        if ((icon != null || isLoading) && label.isNotEmpty)
          const SizedBox(width: AppSpacing.sm),
        if (label.isNotEmpty)
          Text(label),
      ],
    );

    switch (style) {
      case AppButtonStyle.primary:
        return SizedBox(
          width: expanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            child: buttonChild,
          ),
        );
      case AppButtonStyle.secondary:
        return SizedBox(
          width: expanded ? double.infinity : null,
          child: OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            child: buttonChild,
          ),
        );
      case AppButtonStyle.text:
        return SizedBox(
          width: expanded ? double.infinity : null,
          child: TextButton(
            onPressed: isLoading ? null : onPressed,
            child: buttonChild,
          ),
        );
      case AppButtonStyle.danger:
        return SizedBox(
          width: expanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: buttonChild,
          ),
        );
      case AppButtonStyle.success:
        return SizedBox(
          width: expanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: buttonChild,
          ),
        );
    }
  }
}

enum AppButtonStyle {
  primary,
  secondary,
  text,
  danger,
  success,
}

/// Circular icon button with modern styling
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final String? tooltip;
  final bool isActive;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.backgroundColor,
    this.size = 48,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final bgColor = backgroundColor ?? 
      (isActive 
        ? theme.colorScheme.primary.withValues(alpha: 0.15)
        : (isDark ? AppColors.surfaceContainerHighDark : AppColors.surfaceContainerHighLight));
    
    final iconColor = color ?? 
      (isActive 
        ? theme.colorScheme.primary 
        : theme.colorScheme.onSurface);

    Widget button = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// Large recording button with pulse animation
class RecordingButton extends StatefulWidget {
  final bool isRecording;
  final bool isProcessing;
  final VoidCallback? onPressed;

  const RecordingButton({
    super.key,
    required this.isRecording,
    this.isProcessing = false,
    this.onPressed,
  });

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(RecordingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color buttonColor;
    IconData buttonIcon;
    
    if (widget.isProcessing) {
      buttonColor = AppColors.processing;
      buttonIcon = Icons.hourglass_top;
    } else if (widget.isRecording) {
      buttonColor = AppColors.recording;
      buttonIcon = Icons.stop_rounded;
    } else {
      buttonColor = AppColors.idle;
      buttonIcon = Icons.mic_rounded;
    }

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isRecording ? _scaleAnimation.value : 1.0,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: 0.4),
                  blurRadius: widget.isRecording ? 24 : 12,
                  spreadRadius: widget.isRecording ? 4 : 0,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.isProcessing ? null : widget.onPressed,
                borderRadius: BorderRadius.circular(40),
                child: Center(
                  child: widget.isProcessing
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        buttonIcon,
                        size: 36,
                        color: Colors.white,
                      ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
