import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sos_packet.dart';

/// Continuously scans for BLE advertisements from the paired Kavasam
/// SOS device and emits decoded [SosPacket]s (both heartbeat and SOS
/// types) as they arrive. The caller decides what to do with an SOS
/// packet (trigger alerts) vs a heartbeat (update "device nearby" UI).
class BleScanService {
  StreamSubscription<List<ScanResult>>? _subscription;
  final _packetController = StreamController<SosPacketEvent>.broadcast();

  Stream<SosPacketEvent> get packets => _packetController.stream;

  bool _scanning = false;
  bool get isScanning => _scanning;

  /// [pairedDeviceId] should match the deviceId string configured in
  /// the ESP32 firmware's scan-response name (e.g. "KAVASAM-01").
  /// Pass null to accept any device broadcasting our packet layout —
  /// useful during first-time pairing.
  Future<void> startScanning({String? pairedDeviceId}) async {
    if (_scanning) return;
    _scanning = true;

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(days: 1), // effectively continuous; stop() ends it
        androidUsesFineLocation: true,
        continuousUpdates: true, // needed so heartbeat -> SOS changes from the same device are delivered
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (_) {
      // e.g. Bluetooth is switched off: don't crash; allow a later retry.
      _scanning = false;
      return;
    }

    _subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mfrData = r.advertisementData.manufacturerData;
        for (final entry in mfrData.entries) {
          // flutter_blue_plus strips the 2-byte company id key out into
          // the map key already, but our packet also embeds it in the
          // payload bytes for a cheap sanity check — rebuild the full
          // byte sequence to reuse SosPacket.tryParse's company-id check.
          final companyIdBytes = [
            entry.key & 0xFF,
            (entry.key >> 8) & 0xFF,
          ];
          final fullBytes = [...companyIdBytes, ...entry.value];
          final packet = SosPacket.tryParse(
            Uint8List.fromList(fullBytes),
          );
          if (packet == null) continue;

          final advertisedName = r.advertisementData.advName;
          if (pairedDeviceId != null &&
              advertisedName.isNotEmpty &&
              advertisedName != pairedDeviceId) {
            continue; // not our paired device
          }

          _packetController.add(SosPacketEvent(
            deviceId: advertisedName,
            rssi: r.rssi,
            packet: packet,
          ));
        }
      }
    });
  }


  Future<void> stopScanning() async {
    _scanning = false;
    await _subscription?.cancel();
    _subscription = null;
    await FlutterBluePlus.stopScan();
  }

  void dispose() {
    stopScanning();
    _packetController.close();
  }
}

class SosPacketEvent {
  final String deviceId;
  final int rssi;
  final SosPacket packet;
  SosPacketEvent({
    required this.deviceId,
    required this.rssi,
    required this.packet,
  });
}
