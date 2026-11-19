import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_lang.dart';
import '../services/ble_scan_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  final _ble = BleScanService();
  final _storage = StorageService();
  StreamSubscription<SosPacketEvent>? _sub;

  final Set<String> _foundDeviceIds = {};
  String? _pairedId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    _pairedId = await _storage.getPairedDeviceId();

    // Scan without a device filter so *any* Kavasam-firmware device
    // broadcasting nearby shows up as a pairing candidate.
    await _ble.startScanning();
    _sub = _ble.packets.listen((event) {
      if (event.deviceId.isEmpty) return;
      setState(() => _foundDeviceIds.add(event.deviceId));
    });
  }

  Future<void> _pair(String deviceId) async {
    await _storage.setPairedDeviceId(deviceId);
    setState(() => _pairedId = deviceId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr('Paired with')} $deviceId')),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Pair SOS Device'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_pairedId != null)
              Card(
                color: AppColors.surfaceGrey,
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: AppColors.safeGreen),
                  title: Text('${tr('Currently paired:')} $_pairedId'),
                ),
              ),
            const SizedBox(height: 12),
            Text(tr('Nearby devices:'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _foundDeviceIds.isEmpty
                  ? Center(child: Text(tr('Scanning… bring your device close and power it on.')))
                  : ListView(
                      children: _foundDeviceIds.map((id) {
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(id),
                            trailing: ElevatedButton(
                              onPressed: () => _pair(id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.maroon,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(tr('Pair')),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
