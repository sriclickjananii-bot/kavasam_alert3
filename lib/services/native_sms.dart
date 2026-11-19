import 'package:flutter/services.dart';

/// Thin bridge to Android's native SmsManager, used instead of the
/// discontinued `telephony` package. Sends silently -- no SMS app UI is
/// opened, nothing for the user to tap. Requires the SEND_SMS permission
/// to already be granted (the caller in AlertService checks this).
class NativeSms {
  static const MethodChannel _channel =
      MethodChannel('com.example.kavasam_alert/sms');

  /// Returns true if the native side reports the SMS was handed off to
  /// the radio successfully, false on any failure (including the
  /// permission not being granted).
  static Future<bool> send({
    required String to,
    required String message,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('sendSms', {
        'to': to,
        'message': message,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }
}
