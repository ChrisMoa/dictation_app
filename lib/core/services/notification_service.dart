import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('NotificationService: Initializing notification service');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(initSettings);

    _isInitialized = true;
    debugPrint('NotificationService: Notification service initialized');
  }

  Future<void> showDictationControls() async {
    debugPrint('NotificationService: Showing dictation control notification');

    const androidDetails = AndroidNotificationDetails(
      'dictation_controls',
      'Dictation Controls',
      channelDescription: 'Persistent controls for dictation app',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      'Dictation App Active',
      'Tap to return to dictation controls. App is running in background.',
      notificationDetails,
    );

    debugPrint('NotificationService: Dictation controls notification shown');
  }

  Future<void> updateDictationStatus(String status) async {
    debugPrint('NotificationService: Updating dictation status: $status');

    const androidDetails = AndroidNotificationDetails(
      'dictation_controls',
      'Dictation Controls',
      channelDescription: 'Persistent controls for dictation app',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      'Dictation App',
      status,
      notificationDetails,
    );
  }

  Future<void> hideDictationControls() async {
    debugPrint('NotificationService: Hiding dictation controls');
    await _notifications.cancel(1);
  }
} 