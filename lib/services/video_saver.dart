import 'package:flutter/services.dart';

/// Copies a recorded video into the phone gallery (native MediaStore).
class VideoSaver {
  static const MethodChannel _ch =
      MethodChannel('com.example.kavasam_alert/files');

  static Future<bool> saveToGallery(String path) async {
    try {
      return (await _ch.invokeMethod<bool>('saveVideo', {'path': path})) ?? false;
    } catch (_) {
      return false;
    }
  }
}
