import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_lang.dart';

/// Payload carried in the highest-priority "someone is in danger"
/// notification, and used to reopen the same alert screen if the
/// user taps the notification instead of already being on it.
class SosNotificationPayload {
  final String victimName;
  final double latitude;
  final double longitude;
  final bool gpsFixValid;
  final String source; // 'device' or 'manual'

  SosNotificationPayload({
    required this.victimName,
    required this.latitude,
    required this.longitude,
    required this.gpsFixValid,
    required this.source,
  });
}

/// Wraps flutter_local_notifications with the two channels this app
/// needs:
///  - `emergency_channel` — max importance, full-screen intent, plays
///    the siren sound once and shows a big red heads-up notification
///    even if the phone is locked or the user is in another app.
///  - `emergency_result_channel` — a quiet, normal-priority channel
///    used only to report "SMS sent to N number(s)" after dispatch,
///    replacing the old in-app SnackBar entirely.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called by main.dart with a callback that pushes SosAlertScreen
  /// when the user taps the full-screen notification.
  Future<void> init({
    required void Function(SosNotificationPayload) onSosNotificationTapped,
  }) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final p = _pendingPayload;
        if (p != null) onSosNotificationTapped(p);
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emergency_channel',
        'Emergency Alerts',
        description: 'Highest-priority SOS alert popup with siren',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('sos_alarm'),
        enableVibration: true,
        vibrationPattern: null,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'emergency_result_channel',
        'Alert Status',
        description: 'Quiet confirmation once SMS has been sent',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  SosNotificationPayload? _pendingPayload;

  /// Fires the big red, full-screen, siren notification. `fullScreenIntent`
  /// tells Android to launch this app's activity directly over the lock
  /// screen / whatever app is in front, on devices that allow it.
  Future<void> showSosAlert(SosNotificationPayload payload) async {
    _pendingPayload = payload;

    final locationText = payload.gpsFixValid
        ? '${payload.latitude.toStringAsFixed(6)}, '
            '${payload.longitude.toStringAsFixed(6)}'
        : 'acquiring GPS fix…';

    const androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Highest-priority SOS alert popup with siren',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      color: Color(0xFFD32F2F),
      colorized: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('sos_alarm'),
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
    );

    final mine = payload.source == 'manual';
    await _plugin.show(
      998,
      mine
          ? (AppLang.isTa ? '🚨 உங்கள் SOS தூண்டப்பட்டது' : '🚨 Your SOS is triggered')
          : '🚨 ${payload.victimName} is in danger!',
      mine
          ? (AppLang.isTa
              ? 'உங்கள் அவசர தொடர்புகளுக்கு எச்சரிக்கை அனுப்பப்படுகிறது'
              : 'Your emergency contacts are being alerted')
          : 'Location: $locationText',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Quiet follow-up once SMS dispatch finishes — replaces the old
  /// SnackBar so nothing needs to be "seen" in-app to know it worked.
  Future<void> showDispatchResult({
    required int succeeded,
    required int failed,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'emergency_result_channel',
      'Alert Status',
      channelDescription: 'Quiet confirmation once SMS has been sent',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: failed == 0 ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
    );

    await _plugin.show(
      999,
      failed == 0 ? '✅ Alert sent' : '⚠️ Alert partially sent',
      failed == 0
          ? 'SMS sent to all $succeeded number(s).'
          : 'SMS sent to $succeeded; $failed failed.',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> clearSosAlert() async {
    _pendingPayload = null;
    await _plugin.cancel(998);
  }
}
