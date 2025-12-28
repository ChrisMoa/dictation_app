import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Modern overlay widget with glassmorphism styling
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }

    FlutterOverlayWindow.shareData({
      'action': _isRecording ? 'start_recording' : 'stop_recording',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _closeApp() {
    FlutterOverlayWindow.shareData({
      'action': 'close_app',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A2E).withValues(alpha: 0.95),
              const Color(0xFF16213E).withValues(alpha: 0.95),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Recording indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isRecording ? _pulseAnimation.value : 1.0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRecording
                                    ? const Color(0xFFEF4444)
                                    : Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecording ? 'REC' : 'IDLE',
                        style: TextStyle(
                          color: _isRecording
                              ? const Color(0xFFEF4444)
                              : Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Record button
                _OverlayButton(
                  icon: _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: _isRecording
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                  onTap: _toggleRecording,
                  size: 44,
                ),

                const SizedBox(width: 8),

                // Close button
                _OverlayButton(
                  icon: Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  onTap: _closeApp,
                  size: 36,
                  filled: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final bool filled;

  const _OverlayButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 40,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.transparent,
          border: filled ? null : Border.all(color: color, width: 1.5),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: filled ? Colors.white : color,
          size: size * 0.5,
        ),
      ),
    );
  }
}
