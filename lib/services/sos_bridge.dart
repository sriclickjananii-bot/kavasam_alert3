import 'package:flutter/services.dart';

/// Bridge to the native BleWatchService (Kotlin). The service keeps
/// scanning for the SOS device in the background, sends the SMS to the
/// victim's emergency numbers carried in the packet, plays the alarm and
/// brings the full-screen alert to the front. This class lets Flutter
/// start it and receive the alert details.
class SosBridge {
  static const MethodChannel _ch =
      MethodChannel('com.example.kavasam_alert/watch');

  /// True while SosAlertScreen is on screen (prevents stacking duplicates).
  static bool alertOpen = false;

  static Future<void> init({
    required void Function(Map<String, dynamic>) onSos,
  }) async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onSos' && call.arguments is Map) {
        onSos(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    try {
      final pending = await _ch.invokeMethod<Map>('getPendingSos');
      if (pending != null) onSos(Map<String, dynamic>.from(pending));
    } catch (_) {}
  }

  static Future<void> startWatch() async {
    try {
      await _ch.invokeMethod('startWatch');
    } catch (_) {}
  }

  static Future<void> stopAlarm() async {
    try {
      await _ch.invokeMethod('stopAlarm');
    } catch (_) {}
  }
}
