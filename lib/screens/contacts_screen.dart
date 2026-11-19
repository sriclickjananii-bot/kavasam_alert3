import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/emergency_contact.dart';
import '../services/app_lang.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/kaaval_widgets.dart';

const _relations = [
  'Father',
  'Mother',
  'Brother',
  'Sister',
  'Husband',
  'Wife',
  'Guardian',
  'Friend',
  'Other',
];

class _Slot {
  String? id; // existing contact id (kept so saved data stays stable)
  bool invited = false;
  bool accepted = false;
  final phone = TextEditingController();
  final name = TextEditingController();
  String? relation;

  void dispose() {
    phone.dispose();
    name.dispose();
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const _minSlots = 5;
  final _storage = StorageService();
  final List<_Slot> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await _storage.getContacts();
    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();
    for (final c in contacts) {
      final slot = _Slot()
        ..id = c.id
        ..invited = c.isInvitedToLocationSharing
        ..accepted = c.invitationAccepted
        ..relation = _relations.contains(c.relation) ? c.relation : null;
      slot.phone.text = c.phoneNumber;
      slot.name.text = c.name;
      _slots.add(slot);
    }
    while (_slots.length < _minSlots) {
      _slots.add(_Slot());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  /// Same address-book picker as before, now filling a slot.
  Future<void> _pickFromAddressBook(_Slot slot) async {
    final granted = await Permission.contacts.request();
    if (!granted.isGranted) return;

    final contact = await FlutterContacts.openExternalPick();
    if (contact == null) return;

    final full = await FlutterContacts.getContact(contact.id);
    final phone =
        full?.phones.isNotEmpty == true ? full!.phones.first.number : null;
    if (phone == null) return;

    setState(() {
      slot.phone.text = phone;
      slot.name.text = full?.displayName ?? 'Unnamed';
    });
  }

  Future<void> _save() async {
    final out = <EmergencyContact>[];
    for (final s in _slots) {
      final phone = s.phone.text.trim();
      if (phone.isEmpty) continue; // an empty slot = no contact
      final name = s.name.text.trim();
      out.add(EmergencyContact(
        id: s.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.isEmpty ? 'Unnamed' : name,
        phoneNumber: phone,
        isInvitedToLocationSharing: s.invited,
        invitationAccepted: s.accepted,
        relation: s.relation,
      ));
    }
    await _storage.saveContacts(out);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Emergency contacts saved'))));
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 16),
        suffixIcon: suffix,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFBDBDBD)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.tabMaroon, width: 1.5),
        ),
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
        title: Text(tr('EMERGENCY CONTACTS'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
      ),
      body: _slots.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    children: [
                      Text(tr('Manage your emergency contacts'),
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(
                        tr('Emergency contacts will receive a real time alert with '
                            'your location details.'),
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xFF777777), height: 1.25),
                      ),
                      const SizedBox(height: 18),
                      for (var i = 0; i < _slots.length; i++) _slotCard(i),
                    ],
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
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.tabMaroon,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(),
                          minimumSize: const Size(140, 50),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        child: Text(tr('Save')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _slotCard(int i) {
    final slot = _slots[i];
    final title = i < 2
        ? '${tr('Emergency Contact')} - ${i + 1} ${tr('(Recommended)')}'
        : '${tr('Emergency Contact')} - ${i + 1}';
    return Container(
      margin: const EdgeInsets.only(bottom: 26),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          if (i == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Text(
                tr('We suggest only blood relation or guardian to be added as primary contact'),
                style: const TextStyle(fontSize: 15, color: Color(0xFF777777), height: 1.25),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: slot.phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 17),
            decoration: _dec(
              tr('Mobile Number'),
              suffix: IconButton(
                tooltip: tr('Pick from contacts'),
                icon: const Icon(Icons.person_add_alt_1,
                    color: Color(0xFF1FA32B), size: 36),
                onPressed: () => _pickFromAddressBook(slot),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: slot.name,
            style: const TextStyle(fontSize: 17),
            decoration: _dec(tr('Name')),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: slot.relation,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Color(0xFF9E9E9E), size: 30),
            hint: Text(tr('Select Relation'),
                style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 16)),
            style: const TextStyle(fontSize: 17, color: Colors.black),
            decoration: _dec(''),
            items: _relations
                .map((r) => DropdownMenuItem(value: r, child: Text(tr(r))))
                .toList(),
            onChanged: (v) => setState(() => slot.relation = v),
          ),
        ],
      ),
    );
  }
}
