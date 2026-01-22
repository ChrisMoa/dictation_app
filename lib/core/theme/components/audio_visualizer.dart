import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';

/// Audio visualizer with frequency bars that animate based on sound level
class AudioVisualizer extends StatefulWidget {
  final double soundLevel;
  final bool isActive;
  final int barCount;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;

  const AudioVisualizer({
    super.key,
    required this.soundLevel,
    required this.isActive,
    this.barCount = 32,
    this.height = 80,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _barHeights = [];
  final List<double> _targetHeights = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Initialize bar heights
    for (int i = 0; i < widget.barCount; i++) {
      _barHeights.add(0.1);
      _targetHeights.add(0.1);
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(() {
        setState(() {
          // Smoothly interpolate bar heights toward targets
          for (int i = 0; i < _barHeights.length; i++) {
            _barHeights[i] += (_targetHeights[i] - _barHeights[i]) * 0.3;
          }
        });
      });

    _animationController.repeat();
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.soundLevel != oldWidget.soundLevel ||
        widget.isActive != oldWidget.isActive) {
      _updateBarHeights();
    }
  }

  void _updateBarHeights() {
    if (!widget.isActive) {
      // Fade to minimum when inactive
      for (int i = 0; i < _targetHeights.length; i++) {
        _targetHeights[i] = 0.05;
      }
      return;
    }

    // Normalize sound level (typically -160 to 0 dB)
    // Clamp between -60 and 0 for better visualization
    final normalizedLevel = ((widget.soundLevel + 60) / 60).clamp(0.0, 1.0);

    // Create frequency-like distribution
    // Higher frequencies (right side) tend to have less energy
    for (int i = 0; i < _targetHeights.length; i++) {
      final frequencyIndex = i / _targetHeights.length;

      // Simulate frequency response curve (bass has more energy)
      final frequencyWeight = 1.0 - (frequencyIndex * 0.6);

      // Add some randomness to simulate frequency variation
      final randomVariation = 0.7 + (_random.nextDouble() * 0.6);

      // Combine sound level, frequency weighting, and randomness
      final targetHeight = (normalizedLevel * frequencyWeight * randomVariation).clamp(0.05, 1.0);

      _targetHeights[i] = targetHeight;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveColor = widget.inactiveColor ??
      (isDark ? AppColors.surfaceContainerHighDark : AppColors.surfaceContainerHighLight);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark
          ? AppColors.surfaceContainerDark
          : AppColors.surfaceContainerLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (index) {
              final barHeight = _barHeights[index];
              final isEvenBar = index % 2 == 0;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.barCount > 24 ? 0.5 : 1.0,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    height: widget.height * barHeight * 0.85,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: widget.isActive
                          ? [
                              activeColor,
                              activeColor.withValues(alpha: 0.6),
                            ]
                          : [
                              inactiveColor,
                              inactiveColor.withValues(alpha: 0.3),
                            ],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(isEvenBar ? 2 : 3),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Compact circular audio visualizer for smaller spaces
class CompactAudioVisualizer extends StatefulWidget {
  final double soundLevel;
  final bool isActive;
  final double size;
  final Color? activeColor;

  const CompactAudioVisualizer({
    super.key,
    required this.soundLevel,
    required this.isActive,
    this.size = 120,
    this.activeColor,
  });

  @override
  State<CompactAudioVisualizer> createState() => _CompactAudioVisualizerState();
}

class _CompactAudioVisualizerState extends State<CompactAudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _waveHeights = [];
  static const int _waveCount = 12;

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < _waveCount; i++) {
      _waveHeights.add(0.3);
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;

    final normalizedLevel = ((widget.soundLevel + 60) / 60).clamp(0.0, 1.0);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return CustomPaint(
            painter: _CircularWavePainter(
              soundLevel: normalizedLevel,
              isActive: widget.isActive,
              color: activeColor,
              animationValue: _animationController.value,
            ),
          );
        },
      ),
    );
  }
}

class _CircularWavePainter extends CustomPainter {
  final double soundLevel;
  final bool isActive;
  final Color color;
  final double animationValue;

  _CircularWavePainter({
    required this.soundLevel,
    required this.isActive,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.3;

    if (!isActive) {
      // Draw static circle when inactive
      final paint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, baseRadius, paint);
      return;
    }

    final amplitude = soundLevel * 15;
    final waveCount = 3;

    for (int i = 0; i < waveCount; i++) {
      final offset = (animationValue + (i / waveCount)) % 1.0;
      final radius = baseRadius + (offset * size.width * 0.2);
      final opacity = (1.0 - offset) * soundLevel;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (amplitude * 0.2);

      canvas.drawCircle(center, radius, paint);
    }

    // Draw center circle
    final centerPaint = Paint()
      ..color = color.withValues(alpha: 0.3 + (soundLevel * 0.4))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, baseRadius * (0.6 + soundLevel * 0.2), centerPaint);
  }

  @override
  bool shouldRepaint(_CircularWavePainter oldDelegate) {
    return oldDelegate.soundLevel != soundLevel ||
        oldDelegate.isActive != isActive ||
        oldDelegate.animationValue != animationValue;
  }
}
