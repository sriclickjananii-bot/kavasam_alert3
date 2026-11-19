import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kaaval_widgets.dart';
import '../../models/sos_packet.dart';
import '../../services/app_lang.dart';
import '../../services/ble_scan_service.dart';
import '../../services/notification_service.dart';
import '../../services/sos_bridge.dart';
import '../../services/storage_service.dart';
import '../sos_alert_screen.dart';

class EmergencyTab extends StatefulWidget {
  const EmergencyTab({super.key});

  @override
  State<EmergencyTab> createState() => _EmergencyTabState();
}

class _EmergencyTabState extends State<EmergencyTab> {
  final _ble = BleScanService();
  final _storage = StorageService();

  StreamSubscription<SosPacketEvent>? _sub;
  bool _deviceNearby = false;
  bool _sosOpen = false;
  String _statusKey = 'Connecting to your SOS device…';

  // Last packet heard from the PAIRED SOS device that had a valid GPS fix.
  SosPacket? _devicePacket;
  DateTime? _devicePacketAt;
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
      Permission.bluetoothAdvertise, // BLE relay to other phones
      Permission.locationWhenInUse,
      Permission.notification,
      Permission.sms,
      Permission.phone,
      Permission.camera, // evidence video when SOS is pressed in the app
      Permission.microphone,
    ].request();

    // Needed so the full-screen alert can appear over other apps / the
    // lock screen, and so Android doesn't kill the background watcher.
    // Asked only ONCE (this tab is rebuilt every time you come back to it,
    // which used to show the "Display over other apps" screen again and
    // again). It can still be switched on later from Settings.
    if (!await _storage.getSpecialPermsAsked()) {
      await _storage.setSpecialPermsAsked(true);
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    }
    _pairedId = await _storage.getPairedDeviceId();

    // Background watcher: keeps listening for any nearby SOS device even
    // when this app is closed or the screen is off.
    await SosBridge.startWatch();

    // In-app status only (device nearby / SOS seen). The alert itself is
    // raised by the background watcher.
    await _ble.startScanning();

    _sub = _ble.packets.listen((event) async {
      if (!mounted) return;
      // Remember the paired device's position so a button press in the app
      // can use it (only while the device was heard recently).
      final fromPaired = _pairedId != null &&
          (event.deviceId == _pairedId || event.deviceId.isEmpty);
      if (fromPaired &&
          event.packet.gpsFixValid &&
          (event.packet.latitude != 0 || event.packet.longitude != 0)) {
        _devicePacket = event.packet;
        _devicePacketAt = DateTime.now();
      }
      setState(() {
        _deviceNearby = true;
        _statusKey = event.packet.isSos
            ? 'SOS SIGNAL RECEIVED FROM DEVICE'
            : 'Device connected — standing by';
      });
    });
  }

  /// Manual EMERGENCY button: fires the highest-priority notification and
  /// pushes the full-screen red alert. The SMS dispatch itself happens
  /// inside SosAlertScreen as soon as it opens.
  Future<void> _openSosAlert(SosPacket packet, {required String source}) async {
    if (_sosOpen || SosBridge.alertOpen) return;
    _sosOpen = true;

    final name = await _storage.getVictimName();
    await NotificationService.instance.showSosAlert(
      SosNotificationPayload(
        victimName: name.isEmpty ? 'A Kavasam user' : name,
        latitude: packet.latitude,
        longitude: packet.longitude,
        gpsFixValid: packet.gpsFixValid,
        source: source,
      ),
    );

    if (!mounted) {
      _sosOpen = false;
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SosAlertScreen(packet: packet, source: source),
        fullscreenDialog: true,
      ),
    );

    _sosOpen = false;
  }

  Future<void> _manualTrigger() async {
    // Manual in-app trigger. Location rule:
    //  - paired SOS device heard recently with a GPS fix -> the DEVICE's location
    //  - otherwise (no device paired / nearby) -> THIS PHONE's own location,
    //    which the SOS screen reads as it opens.
    final dp = _devicePacket;
    final at = _devicePacketAt;
    final deviceFresh = dp != null &&
        at != null &&
        DateTime.now().difference(at).inSeconds < 120;
    final packet = deviceFresh
        ? SosPacket(
            packetType: 0x01,
            gpsFixValid: true,
            buttonHeld: true,
            latitude: dp.latitude,
            longitude: dp.longitude,
            lastKnown: dp.lastKnown,
            locationAgeSeconds: dp.locationAgeSeconds,
          )
        : SosPacket(
            packetType: 0x01,
            gpsFixValid: false,
            buttonHeld: true,
            latitude: 0,
            longitude: 0,
          );
    await _openSosAlert(packet, source: 'manual');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ta = AppLang.isTa;
    return KaavalBackground(
      child: LayoutBuilder(
        builder: (context, box) {
          // Everything must fit on one screen: the SOS button takes
          // whatever height is left after the fixed text rows.
          final reserved = 250.0; // titles + captions + toggle + status
          final size = (box.maxHeight - reserved)
              .clamp(110.0, box.maxWidth * 0.62)
              .toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'KAVASAM ALERT',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: AppColors.headingMaroon,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Text(
                      'கவசம் அலர்ட்',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.headingMaroon,
                      ),
                    ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black),
                      children: ta
                          ? const [
                              TextSpan(text: 'அவசரத்தில் '),
                              TextSpan(
                                  text: 'பொத்தானை',
                                  style: TextStyle(
                                      color: AppColors.emergencyRed)),
                              TextSpan(text: ' அழுத்தவும்'),
                            ]
                          : const [
                              TextSpan(text: 'Press the Button in '),
                              TextSpan(
                                  text: 'Emergency',
                                  style: TextStyle(
                                      color: AppColors.emergencyRed)),
                            ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Emergency SOS button',
                  child: GestureDetector(
                    onTap: _sosOpen ? null : _manualTrigger,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/sos_button.png',
                            width: size,
                            height: size,
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (_sosOpen)
                          const CircularProgressIndicator(color: Colors.white),
                      ],
                    ),
                  ),
                ),
                Text(
                  ta
                      ? 'உங்கள் நேரடி இருப்பிடம் அவசர தொடர்புகளுக்கு SMS ஆக அனுப்பப்படும்'
                      : 'Your live location will be sent by SMS to your emergency contacts',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const KaavalLangToggle(),
                _DeviceStatusCard(
                  connected: _deviceNearby,
                  statusText: tr(_statusKey),
                ),
                Text(
                  tr('Not an official police service; no call back is guaranteed.'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 10.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  final bool connected;
  final String statusText;
  const _DeviceStatusCard({required this.connected, required this.statusText});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: connected ? AppColors.safeGreen : Colors.grey.shade400,
        ),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
              color: connected ? AppColors.safeGreen : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
