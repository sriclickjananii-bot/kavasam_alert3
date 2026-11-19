import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_lang.dart';
import '../services/sim_service.dart';
import '../services/sos_bridge.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/kaaval_widgets.dart';
import 'contacts_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _storage = StorageService();
  final _nameCtrl = TextEditingController();
  bool? _autoCallPolice;
  bool _responder = false;
  bool _overlayOn = false;
  List<SimInfo> _sims = [];
  int _simSubId = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _storage.getVictimName();
    final overlay = await Permission.systemAlertWindow.isGranted;
    final autoCall = await _storage.getAutoCallPolice();
    final responder = await _storage.getResponderEnabled();
    final simId = await _storage.getSmsSimSubId();
    final sims = await SimService.list();
    setState(() {
      _nameCtrl.text = name;
      _overlayOn = overlay;
      _sims = sims;
      // forget a saved SIM that is no longer inserted
      _simSubId = sims.any((x) => x.subId == simId) ? simId : -1;
      _autoCallPolice = autoCall;
      _responder = responder;
    });
  }

  Future<void> _save() async {
    await _storage.setVictimName(_nameCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Saved'))),
      );
    }
  }

  Future<void> _toggleAutoCall(bool value) async {
    await _storage.setAutoCallPolice(value);
    setState(() => _autoCallPolice = value);
  }

  /// "Display over other apps": opens the system page; no repeated pop-ups.
  Future<void> _toggleOverlay(bool v) async {
    if (v) {
      await Permission.systemAlertWindow.request();
    } else {
      await openAppSettings();
    }
    final now = await Permission.systemAlertWindow.isGranted;
    if (mounted) setState(() => _overlayOn = now);
  }

  Future<void> _toggleResponder(bool v) async {
    if (v) {
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
      await Permission.notification.request();
    }
    await _storage.setResponderEnabled(v);
    await _storage.ensureResponderCredentials();
    setState(() => _responder = v);
    await SosBridge.startWatch(); // service re-reads the setting
  }

  Widget _caption(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: Text(tr(t),
            style: const TextStyle(
                fontSize: 15, color: Color(0xFF777777), height: 1.25)),
      );

  Widget _row(String label, Widget trailing) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBDBDBD)),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(tr(label), style: const TextStyle(fontSize: 16))),
            trailing,
          ],
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: Text(tr(t),
            style: const TextStyle(fontSize: 16, color: Color(0xFF777777))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.settingsBg,
      appBar: kaavalAppBar(
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 24),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(tr('Settings'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          _label('Your name (shown in alert messages)'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBDBDBD)),
            ),
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: tr('Name'),
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _caption('Call Police (100) automatically during an SOS. Asked once '
              'on your first SOS; change your answer here any time.'),
          _row('Auto-call Police',
              KaavalOnOffButton(on: _autoCallPolice ?? false, onChanged: _toggleAutoCall)),
          if (_autoCallPolice == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Text(tr('Not set yet — will be asked on next SOS'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
          const SizedBox(height: 28),
          _caption('Help people near me: when someone close to you presses their '
              'SOS button, this phone gets an alarm even without Bluetooth range. '
              'Only your approximate position (updated every few minutes) is '
              'shared with the alert server, never your name.'),
          _row('Nearby Alerts',
              KaavalOnOffButton(on: _responder, onChanged: _toggleResponder)),
          const SizedBox(height: 28),
          _caption('Choose which SIM sends the emergency SMS automatically.'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBDBDBD)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _simSubId,
                isExpanded: true,
                style: const TextStyle(fontSize: 16, color: Colors.black),
                items: [
                  DropdownMenuItem(value: -1, child: Text(tr('Phone default'))),
                  for (final sim in _sims)
                    DropdownMenuItem(
                      value: sim.subId,
                      child: Text('${tr('SIM')} ${sim.slot}'
                          '${sim.name.isEmpty ? '' : ' - ${sim.name}'}'),
                    ),
                ],
                onChanged: (v) async {
                  await _storage.setSmsSimSubId(v ?? -1);
                  if (mounted) setState(() => _simSubId = v ?? -1);
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          _caption('Lets the SOS alert appear on top of any app or the lock screen. Turn it on once.'),
          _row('Display over other apps',
              KaavalOnOffButton(on: _overlayOn, onChanged: _toggleOverlay)),
          const SizedBox(height: 28),
          _label('Preferred Language'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBDBDBD)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: AppLang.code,
                isExpanded: true,
                style: const TextStyle(fontSize: 18, color: Colors.black),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'ta', child: Text('தமிழ்')),
                ],
                // one switch for the whole app: changes everywhere at once
                onChanged: (v) => AppLang.set(v ?? 'en'),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _label('Emergency Contacts'),
          InkWell(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ContactsScreen())),
            child: _row('Emergency Contacts',
                const Icon(Icons.chevron_right, size: 26)),
          ),
          const SizedBox(height: 30),
          Center(
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tabMaroon,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                minimumSize: const Size(160, 50),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              child: Text(tr('Save')),
            ),
          ),
        ],
      ),
    );
  }
}
