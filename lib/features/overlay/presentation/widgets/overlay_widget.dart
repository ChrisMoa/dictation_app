import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  bool _isRecording = false;

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
    
    // Send message to main app
    FlutterOverlayWindow.shareData({
      'action': _isRecording ? 'start_recording' : 'stop_recording',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _closeApp() {
    // Send close message to main app
    FlutterOverlayWindow.shareData({
      'action': 'close_app',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    // Close overlay
    FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: _isRecording ? Colors.red : Colors.green,
                  size: 24,
                ),
              ),
            ),
            const VerticalDivider(
              color: Colors.white,
              thickness: 1,
              indent: 8,
              endIndent: 8,
            ),
            GestureDetector(
              onTap: _closeApp,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.close,
                  color: Colors.red,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

