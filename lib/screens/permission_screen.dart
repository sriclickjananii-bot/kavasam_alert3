import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_lang.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/kaaval_widgets.dart';
import 'home_screen.dart';

/// Shows the "PERMISSION REQUIRED" explainer once on first launch, then
/// the normal home screen. The real permission requests are still made by
/// the Emergency tab exactly as before; the switches here simply let the
/// user grant them up-front.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _seen = StorageService().getPermissionIntroSeen();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _seen,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: SizedBox.shrink());
        return snap.data! ? const HomeScreen() : const PermissionRequiredScreen();
      },
    );
  }
}

class _PermItem {
  final String title;
  final String desc;
  final IconData icon;
  final List<Permission> perms;
  const _PermItem(this.title, this.desc, this.icon, this.perms);
}

const _items = <_PermItem>[
  _PermItem(
    'Sms',
    'SMS permission is required to send the emergency alert with your '
        'current location to your emergency contacts, and to receive SOS '
        'alerts sent by SMS from nearby phones.',
    Icons.sms_outlined,
    [Permission.sms],
  ),
  _PermItem(
    'Phone',
    'Phone permission is necessary to place the emergency call to Police '
        '(100) directly from the SOS alert screen.',
    Icons.call_outlined,
    [Permission.phone],
  ),
  _PermItem(
    'Location',
    'Location permission is essential to share your live location with '
        'your emergency contacts during an emergency and for live '
        'location sharing with your family.',
    Icons.location_on_outlined,
    [Permission.locationWhenInUse],
  ),
  _PermItem(
    'Bluetooth',
    'Bluetooth permission is required to connect to your SOS device and '
        'to listen for SOS signals from nearby devices.',
    Icons.bluetooth,
    [Permission.bluetoothScan, Permission.bluetoothConnect],
  ),
  _PermItem(
    'Notification',
    'Notification permission is necessary to show the emergency alert '
        'and to receive notifications during an SOS.',
    Icons.notifications_outlined,
    [Permission.notification],
  ),
];

class PermissionRequiredScreen extends StatefulWidget {
  const PermissionRequiredScreen({super.key});

  @override
  State<PermissionRequiredScreen> createState() =>
      _PermissionRequiredScreenState();
}

class _PermissionRequiredScreenState extends State<PermissionRequiredScreen> {
  final Map<int, bool> _on = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (var i = 0; i < _items.length; i++) {
      var ok = true;
      for (final p in _items[i].perms) {
        if (!await p.isGranted) ok = false;
      }
      _on[i] = ok;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggle(int i, bool v) async {
    if (v) {
      await _items[i].perms.request();
    } else {
      await openAppSettings();
    }
    await _refresh();
  }

  Future<void> _proceed() async {
    await StorageService().setPermissionIntroSeen(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.settingsBg,
      appBar: kaavalAppBar(
        automaticallyImplyLeading: false,
        title: Text(tr('PERMISSION REQUIRED'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 18),
              itemBuilder: (_, i) {
                final it = _items[i];
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Icon(it.icon, size: 40, color: AppColors.tabMaroon),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(it.title),
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.tabMaroon)),
                            const SizedBox(height: 2),
                            Text(tr(it.desc),
                                style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.2,
                                    color: Color(0xFF666666))),
                          ],
                        ),
                      ),
                      Switch(
                        value: _on[i] ?? false,
                        onChanged: (v) => _toggle(i, v),
                        activeColor: AppColors.tabMaroon,
                        activeTrackColor: const Color(0xFFD9D9D9),
                        inactiveThumbColor: const Color(0xFF9E9E9E),
                        inactiveTrackColor: const Color(0xFFE0E0E0),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: ElevatedButton(
                  onPressed: _proceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tabMaroon,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(),
                    minimumSize: const Size(140, 52),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  child: Text(tr('Proceed')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
