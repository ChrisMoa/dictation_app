import 'package:equatable/equatable.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayConfig extends Equatable {
  final double width;
  final double height;
  final OverlayFlag flag;

  const OverlayConfig({
    required this.width,
    required this.height,
    required this.flag,
  });

  @override
  List<Object> get props => [width, height, flag];
}

