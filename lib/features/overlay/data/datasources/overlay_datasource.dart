import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:dictation_app/features/overlay/data/models/overlay_config_model.dart';
import 'package:dictation_app/core/services/notification_service.dart';

abstract class OverlayDatasource {
  Future<bool> checkPermissions();
  Future<bool> requestPermissions();
  Future<void> showOverlay(OverlayConfigModel config);
  Future<void> hideOverlay();
  Future<bool> isOverlayVisible();
}

class OverlayDatasourceImpl implements OverlayDatasource {
  bool _isNotificationOverlayActive = false;
  final NotificationService _notificationService = NotificationService();

  @override
  Future<bool> checkPermissions() async {
    debugPrint('OverlayDatasource: Checking overlay permissions');
    try {
      final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
      debugPrint('OverlayDatasource: Has overlay permission: $hasPermission');
      return hasPermission;
    } catch (e) {
      debugPrint('OverlayDatasource: Error checking permissions: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('OverlayDatasource: Requesting overlay permissions');
    try {
      final result = await FlutterOverlayWindow.requestPermission();
      debugPrint('OverlayDatasource: Permission request result: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('OverlayDatasource: Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Future<void> showOverlay(OverlayConfigModel config) async {
    debugPrint('OverlayDatasource: Attempting to show overlay');
    debugPrint('OverlayDatasource: Config - Width: ${config.width}, Height: ${config.height}, Flag: ${config.flag}');
    
    try {
      // First check if we have permission
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        debugPrint('OverlayDatasource: No permission to show overlay, requesting...');
        final granted = await requestPermissions();
        if (!granted) {
          debugPrint('OverlayDatasource: Permission denied, falling back to notification overlay');
          await _showNotificationOverlay();
          return;
        }
        // Wait a bit after permission grant
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      // Check if overlay is already active and close it
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        debugPrint('OverlayDatasource: Overlay already active, closing first');
        await FlutterOverlayWindow.closeOverlay();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      debugPrint('OverlayDatasource: Trying simplified overlay approach');
      
      // Try a single, simple overlay configuration
      try {
        await FlutterOverlayWindow.showOverlay(
          width: 250,
          height: 100,
          flag: OverlayFlag.defaultFlag,
          alignment: OverlayAlignment.topRight,
          positionGravity: PositionGravity.none,
        );
        
        // Check if overlay is now active
        await Future.delayed(const Duration(milliseconds: 2000));
        final isNowActive = await FlutterOverlayWindow.isActive();
        
        if (isNowActive) {
          debugPrint('OverlayDatasource: Window overlay shown successfully');
          return;
        } else {
          debugPrint('OverlayDatasource: Window overlay failed, falling back to notification overlay');
          await _showNotificationOverlay();
        }
      } catch (e) {
        debugPrint('OverlayDatasource: Window overlay error: $e, falling back to notification overlay');
        await _showNotificationOverlay();
      }
      
    } catch (e) {
      debugPrint('OverlayDatasource: Error showing overlay: $e');
      debugPrint('OverlayDatasource: Falling back to notification overlay');
      await _showNotificationOverlay();
    }
  }

  Future<void> _showNotificationOverlay() async {
    debugPrint('OverlayDatasource: Showing notification-based overlay');
    
    try {
      // Initialize notification service if needed
      await _notificationService.initialize();
      
      // Show persistent notification with controls
      await _notificationService.showDictationControls();
      
      _isNotificationOverlayActive = true;
      
      debugPrint('OverlayDatasource: Notification overlay activated');
      debugPrint('OverlayDatasource: Users can now control the app from the notification panel');
      
    } catch (e) {
      debugPrint('OverlayDatasource: Error showing notification overlay: $e');
      rethrow;
    }
  }

  @override
  Future<void> hideOverlay() async {
    debugPrint('OverlayDatasource: Hiding overlay');
    try {
      // Hide window overlay if active
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
        debugPrint('OverlayDatasource: Window overlay hidden successfully');
      }
      
      // Hide notification overlay if active
      if (_isNotificationOverlayActive) {
        await _notificationService.hideDictationControls();
        _isNotificationOverlayActive = false;
        debugPrint('OverlayDatasource: Notification overlay hidden successfully');
      }
      
      if (!isActive && !_isNotificationOverlayActive) {
        debugPrint('OverlayDatasource: No overlay was active');
      }
    } catch (e) {
      debugPrint('OverlayDatasource: Error hiding overlay: $e');
      rethrow;
    }
  }

  @override
  Future<bool> isOverlayVisible() async {
    try {
      final isWindowActive = await FlutterOverlayWindow.isActive();
      final isOverlayVisible = isWindowActive || _isNotificationOverlayActive;
      
      debugPrint('OverlayDatasource: Overlay visibility check - Window: $isWindowActive, Notification: $_isNotificationOverlayActive, Total: $isOverlayVisible');
      return isOverlayVisible;
    } catch (e) {
      debugPrint('OverlayDatasource: Error checking overlay visibility: $e');
      return _isNotificationOverlayActive;
    }
  }
}

