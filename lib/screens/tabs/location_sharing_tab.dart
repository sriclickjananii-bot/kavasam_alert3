import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kaaval_widgets.dart';
import '../../services/app_lang.dart';
import '../../services/location_share_service.dart';
import '../../services/storage_service.dart';
import '../live_map_screen.dart';

class LocationSharingTab extends StatefulWidget {
  const LocationSharingTab({super.key});

  @override
  State<LocationSharingTab> createState() => _LocationSharingTabState();
}

class _LocationSharingTabState extends State<LocationSharingTab> {
  LocationShareService get _svc => LocationShareService.instance;
  final _storage = StorageService();

  bool _alwaysShare = false;
  bool _ready = false;
  String? _error;
  bool _fbOk = true;
  String? _lastInviteCode;
  bool _busy = false;
  Map<String, String> _labels = {}; // names THIS user saved for people (by uid)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final always = await _storage.getAlwaysShareLocation();
    final labels = await _storage.getWatchLabels();
    var ok = true;
    try {
      await _svc.ensureSignedIn();
    } catch (e) {
      ok = false;
      _error = 'Firebase is not set up yet (or no internet).\n'
          'Live location sharing will work after adding google-services.json (see FIREBASE_SETUP.md).';
    }
    if (!mounted) return;
    setState(() {
      _labels = labels;
      _alwaysShare = ok ? always : false;
      _fbOk = ok;
      _ready = true;
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggleAlwaysShare(bool value) async {
    if (!_fbOk) {
      _snack('Firebase is not set up yet.');
      return;
    }
    if (value) {
      final ok = await _svc.startSharing();
      if (!ok) {
        _snack(tr('Location permission / GPS is required to share.'));
        return;
      }
    } else {
      await _svc.stopSharing();
    }
    await _storage.setAlwaysShareLocation(value);
    setState(() => _alwaysShare = value);
  }

  Future<void> _createInvite() async {
    if (!_fbOk) {
      _snack('Firebase is not set up yet.');
      return;
    }
    // Ask who the code is for, so that person shows up under THAT name.
    final forCtrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Invite Code')),
        content: TextField(
          controller: forCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
              labelText: tr('Who is this invite for? (e.g. Mom)'),
              hintText: tr('Contact name (optional)')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('Create code'))),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      final name = await _storage.getVictimName();
      final code = await _svc.createInvite(name.isEmpty ? 'Kavasam user' : name,
          forName: forCtrl.text);
      setState(() => _lastInviteCode = code);
    } catch (e) {
      _snack('${tr('Could not create invite:')} $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rename a person on THIS phone only (each user sees the names they chose).
  Future<void> _renameDialog(String uid, String current) async {
    final c = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rename contact')),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.setWatchLabel(uid, c.text);
    final labels = await _storage.getWatchLabels();
    if (mounted) setState(() => _labels = labels);
  }

  Future<void> _shareOnWhatsApp(String code) async {
    final text = 'Join me on Kavasam Alert to see my live location. '
        'Open the app > Location Sharing > "Accept an Invite" and enter this code: $code '
        '(valid for 48 hours).';
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _acceptDialog() async {
    final code = TextEditingController();
    final saveAs = TextEditingController();
    final myName = TextEditingController(text: await _storage.getVictimName());
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Enter Invite Code')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: tr('e.g. 4F9A2C1B')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: saveAs,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: tr('Save this person as (name on your phone)')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: myName,
              textCapitalization: TextCapitalization.words,
              decoration:
                  InputDecoration(labelText: tr('Your name (shown to them)')),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('Cancel'))),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final r = await _svc.acceptInvite(
                    code.text.trim().toUpperCase(),
                    myName.text.trim().isEmpty ? 'Contact' : myName.text.trim());
                // The name this user typed wins; else the name from the invite.
                final label = saveAs.text.trim().isNotEmpty
                    ? saveAs.text.trim()
                    : (r.forName.isNotEmpty ? r.forName : r.ownerName);
                await _storage.setWatchLabel(r.ownerUid, label);
                final labels = await _storage.getWatchLabels();
                if (mounted) setState(() => _labels = labels);
                _snack('${tr('Done — you can now see')} $label${tr('\'s live location.')}');
              } catch (e) {
                _snack('$e');
              }
            },
            child: Text(tr('Accept')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const KaavalBackground(
          child: Center(child: CircularProgressIndicator()));
    }

    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 15);
    final small = TextStyle(color: Colors.grey.shade700, fontSize: 12);
    return KaavalBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        children: [
          if (!_fbOk && _error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                border: Border.all(color: const Color(0xFFE0B040)),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  tr('Select one of the following services to enable your family / friends to track your live location & movement'),
                  style: const TextStyle(
                      fontSize: 15, height: 1.2, color: Color(0xFF555555)),
                ),
              ),
              const SizedBox(width: 6),
              const KaavalMapIllustration(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _createInvite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF66BB6A),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.person_add_alt, size: 22),
                    label: Text(tr('Invite Code'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _acceptDialog,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF444444),
                      side: const BorderSide(
                          color: AppColors.cardGreen, width: 2.2),
                      shape: const RoundedRectangleBorder(),
                    ),
                    icon: const Icon(Icons.qr_code, size: 20),
                    label: Text(tr('Accept Invite'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ],
          ),
          if (_lastInviteCode != null) ...[
            const SizedBox(height: 14),
            KaavalGreenCard(
              child: Column(children: [
                SelectableText(_lastInviteCode!,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        color: AppColors.tabMaroon)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(tr('Copy')),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _lastInviteCode!));
                      _snack(tr('Copied'));
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.send),
                    label: Text(tr('WhatsApp')),
                    onPressed: () => _shareOnWhatsApp(_lastInviteCode!),
                  ),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          const KaavalInstructionCard(
            title: 'Invite Instructions', // translated inside the card
            steps: [
              'Tap the Invite Code button above.',
              'Send the code to your parent / contact (WhatsApp or Copy).',
              'They open this app and tap Accept Invite.',
              'Each code works once, for 48 hours.',
              'They can see you until you remove them.',
            ],
          ),
          const SizedBox(height: 16),
          KaavalGreenCard(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                  child: Text(tr('Always-On Location Sharing'), style: h),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                  child: Text(
                      tr('When on, your live location is continuously visible to every family member / contact who accepted your invite — not only during an SOS.'),
                      style: small),
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  title: Text(tr('Always share my location')),
                  subtitle: Text(_alwaysShare ? tr('Sharing is ON') : tr('Sharing is OFF')),
                  value: _alwaysShare,
                  activeColor: AppColors.tabMaroon,
                  onChanged: _toggleAlwaysShare,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('Who can see me'), style: h),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fbOk ? _svc.watchers() : null,
            builder: (c, s) {
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) return Text(tr('Nobody yet.'), style: small);
              return KaavalGreenCard(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  children: docs.map((d) {
                    // name shown: the one I saved > the one I typed on the invite
                    // > the name the person gave when accepting
                    final inviteFor = (d.data()['inviteFor'] as String?) ?? '';
                    final shown = _labels[d.id] ??
                        (inviteFor.isNotEmpty
                            ? inviteFor
                            : (d.data()['name'] as String? ?? tr('Contact')));
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.visibility),
                      title: Text(shown),
                      onTap: () => _renameDialog(d.id, shown),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            tooltip: tr('Rename'),
                            onPressed: () => _renameDialog(d.id, shown),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: tr('Remove'),
                            onPressed: () => _svc.revokeAccess(
                                ownerUid: _svc.uid!, watcherUid: d.id),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(tr('People I am watching'), style: h),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fbOk ? _svc.watching() : null,
            builder: (c, s) {
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) return Text(tr('Nobody yet.'), style: small);
              return Column(
                children: docs.map((d) {
                  // the name I saved for this person (else the name they set)
                  final name = _labels[d.id] ??
                      (d.data()['ownerName'] as String? ?? 'Family');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: KaavalGreenCard(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: AppColors.tabMaroon,
                            child: Icon(Icons.map, color: Colors.white)),
                        title: Text(name),
                        subtitle: Text(tr('Tap to see live location')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: tr('Rename'),
                              onPressed: () => _renameDialog(d.id, name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: tr('Stop watching'),
                              onPressed: () => _svc.revokeAccess(
                                  ownerUid: d.id, watcherUid: _svc.uid!),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  LiveMapScreen(ownerUid: d.id, ownerName: name)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
