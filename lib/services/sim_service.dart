import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SimInfo {
  final int subId;
  final int slot; // 1 or 2
  final String name;
  SimInfo(this.subId, this.slot, this.name);
}

/// Lists the phone's active SIM cards (for the "Send SMS from SIM" setting).
class SimService {
  static const MethodChannel _ch =
      MethodChannel('com.example.kavasam_alert/files');

  static Future<List<SimInfo>> list() async {
    try {
      if (!await Permission.phone.isGranted) {
        await Permission.phone.request();
      }
      final raw = await _ch.invokeMethod<List<dynamic>>('getSims');
      if (raw == null) return [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return SimInfo(
          (m['subId'] as num).toInt(),
          (m['slot'] as num).toInt(),
          (m['name'] ?? '').toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
