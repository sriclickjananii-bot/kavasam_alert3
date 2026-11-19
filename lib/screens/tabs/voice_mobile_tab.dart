import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../models/emergency_contact.dart';
import '../../services/app_lang.dart';
import '../../services/storage_service.dart';
import '../../widgets/kaaval_widgets.dart';

class VoiceMobileTab extends StatefulWidget {
  const VoiceMobileTab({super.key});

  @override
  State<VoiceMobileTab> createState() => _VoiceMobileTabState();
}

class _VoiceMobileTabState extends State<VoiceMobileTab> {
  final _storage = StorageService();
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _storage.getContacts();
    setState(() => _contacts = c);
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return KaavalBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        children: [
          const KaavalHeading('DIAL 112 / 100 / 101'),
          const SizedBox(height: 10),
          Text(
            tr('PRESS BELOW DIAL BUTTON FOR POLICE / FIRE EMERGENCY'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.2),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => _call('112'),
              child: Container(
                width: 150,
                height: 150,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1A1A), Color(0xFFBDBDBD), Color(0xFF2A2A2A)],
                  ),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF4CA64F),
                  ),
                  child: Transform.rotate(
                    angle: 0.0,
                    child: const Icon(Icons.phone,
                        size: 72, color: Color(0xFFD9D9D9)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr('Tap to call the National Emergency number (112)'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 14),
          const KaavalHeading('HELPLINES', size: 24),
          const SizedBox(height: 4),
          Text(
            tr('These are direct voice lines \u2014 tap to call. (An SMS alert to '
                'short-code helpline numbers is not guaranteed to be '
                'monitored; use a call for anything urgent.)'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ...defaultPublicHelplines.map(
            (h) => _DialTile(
              title: tr(h.label),
              subtitle: h.number,
              onTap: () => _call(h.number),
            ),
          ),
          const SizedBox(height: 20),
          const KaavalHeading('YOUR EMERGENCY CONTACTS', size: 19),
          const SizedBox(height: 12),
          if (_contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr('No emergency contacts added yet. Add them from Other '
                    'Services > Emergency Contacts.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else
            ..._contacts.map(
              (c) => _DialTile(
                title: c.name,
                subtitle: c.phoneNumber,
                onTap: () => _call(c.phoneNumber),
              ),
            ),
          const SizedBox(height: 20),
          const Center(child: KaavalLangToggle()),
        ],
      ),
    );
  }
}

class _DialTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _DialTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.tabMaroon,
          child: Icon(Icons.call, color: Colors.white, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
