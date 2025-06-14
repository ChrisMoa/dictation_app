import 'package:flutter/material.dart';
import 'package:dictation_app/features/overlay/presentation/widgets/overlay_widget.dart';

// Entry point for overlay window
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const OverlayWidget(),
    );
  }
}