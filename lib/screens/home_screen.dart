import 'package:flutter/material.dart';
import '../services/app_lang.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/kaaval_widgets.dart';
import 'contacts_screen.dart';
import 'device_pairing_screen.dart';
import 'profile_settings_screen.dart';
import 'register_location_screen.dart';
import 'tabs/emergency_tab.dart';
import 'tabs/location_sharing_tab.dart';
import 'tabs/other_services_tab.dart';
import 'tabs/voice_mobile_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: kaavalAppBar(
          toolbarHeight: 56,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, size: 26),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Text(
            tr('Kavasam Alert -\nCITIZEN SAFETY APP'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 1.15),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications, size: 24),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 24),
              tooltip: tr('Settings'),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
              },
            ),
          ],
        ),
        // `context` (this screen) is passed so About / How to Use dialogs have
        // a live context after the side menu closes.
        drawer: _AppDrawer(homeContext: context),
        body: Column(
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                isScrollable: false,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: const BoxDecoration(color: AppColors.tabMaroon),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, height: 1.1),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, height: 1.1),
                tabs: [
                  Tab(height: 46, text: tr('EMERGENCY')),
                  Tab(height: 46, text: tr('VOICE/\nMOBILE')),
                  Tab(height: 46, text: tr('LOCATION\nSHARING')),
                  Tab(height: 46, text: tr('OTHER\nSERVICES')),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  EmergencyTab(),
                  VoiceMobileTab(),
                  LocationSharingTab(),
                  OtherServicesTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const KaavalTicker(),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  final BuildContext homeContext;
  const _AppDrawer({required this.homeContext});

  void _go(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 26, color: Colors.black87),
                const SizedBox(width: 22),
                Text(tr(label), style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        );

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: const Color(0xFFFAFAFA),
      shape: const RoundedRectangleBorder(),
      child: Column(
        children: [
          const KaavalDrawerIllustration(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FutureBuilder<String>(
                future: StorageService().getVictimName(),
                builder: (_, s) {
                  final name = (s.data ?? '').trim();
                  return Text(
                    name.isEmpty ? tr('Set your name') : name,
                    style: const TextStyle(
                        fontSize: 18, color: AppColors.linkBlue, height: 1.3),
                  );
                },
              ),
            ),
          ),
          item(Icons.manage_accounts_outlined, 'Edit Profile',
              () => _go(context, const ProfileSettingsScreen())),
          item(Icons.add_location_alt_outlined, 'My Safe Location',
              () => _go(context, const RegisterLocationScreen())),
          item(Icons.bluetooth, 'Pair SOS Device',
              () => _go(context, const DevicePairingScreen())),
          item(Icons.contacts_outlined, 'Emergency Contacts',
              () => _go(context, const ContactsScreen())),
          item(Icons.share_outlined, 'Share with Friends', () {
            Navigator.pop(context);
            shareAppWithFriends();
          }),
          item(Icons.help_outline, 'How to Use', () {
            Navigator.pop(context);
            showHowToUse(homeContext);
          }),
          item(Icons.info_outline, 'About App', () {
            Navigator.pop(context);
            showAboutKavasam(homeContext);
          }),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: const Color(0xFFEDEDED),
            child: const Text(
              'Kavasam Alert  •  Version 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
