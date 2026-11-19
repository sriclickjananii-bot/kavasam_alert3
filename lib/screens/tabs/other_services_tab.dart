import 'package:flutter/material.dart';
import '../contacts_screen.dart';
import '../device_pairing_screen.dart';
import '../profile_settings_screen.dart';
import '../../widgets/kaaval_widgets.dart';

class OtherServicesTab extends StatelessWidget {
  const OtherServicesTab({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    final tiles = <(String, VoidCallback)>[
      ('MANAGE EMERGENCY\nCONTACTS', () => open(const ContactsScreen())),
      ('PAIR SOS\nDEVICE', () => open(const DevicePairingScreen())),
      ('PROFILE &\nLANGUAGE', () => open(const ProfileSettingsScreen())),
      ('ABOUT\nKAVASAM ALERT', () => showAboutKavasam(context)),
    ];

    return KaavalBackground(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
          childAspectRatio: 1.35,
        ),
        itemCount: tiles.length,
        itemBuilder: (_, i) =>
            KaavalGreyTile(label: tiles[i].$1, onTap: tiles[i].$2), // text translated inside
      ),
    );
  }
}
