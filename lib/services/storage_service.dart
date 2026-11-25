import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emergency_contact.dart';

/// The place the user registered as their safe location (home / college / work).
class RegisteredLocation {
  final double lat;
  final double lon;
  final String label;
  const RegisteredLocation(this.lat, this.lon, this.label);
}

/// Simple local persistence layer. Swap this out for a cloud-backed
/// store later if you want contacts to sync across the user's devices.
class StorageService {
  static const _kContacts = 'emergency_contacts';
  static const _kDeviceName = 'device_name';
  static const _kPairedDeviceId = 'paired_device_id';
  static const _kVictimName = 'victim_name';
  static const _kLanguage = 'app_language'; // 'en' or 'ta'
  static const _kAlwaysShareLocation = 'always_share_location';
  static const _kAutoCallPolice = 'auto_call_police';
  static const _kPermIntroSeen = 'permission_intro_seen';
  static const _kSpecialPermsAsked = 'special_perms_asked';
  static const _kWatchLabels = 'watch_labels';
  // Read by the native SMS code (SimSms.kt as "flutter.sms_sim_sub_id"): do not rename.
  static const _kSmsSimSubId = 'sms_sim_sub_id';
  // These three keys are ALSO read by the native Android service
  // (ResponderNet.kt reads "flutter.responder_*"), so do not rename them.
  // Registered safe location. Saved as TEXT and read natively by ResponderNet.kt as
  // "flutter.reg_lat" / "flutter.reg_lon" / "flutter.reg_alerts_enabled": do not rename.
  static const _kRegLat = 'reg_lat';
  static const _kRegLon = 'reg_lon';
  static const _kRegLabel = 'reg_label';
  static const _kRegAlerts = 'reg_alerts_enabled';
  static const _kRegPromptDone = 'reg_prompt_done';
  static const _kResponderEnabled = 'responder_enabled';
  static const _kResponderId = 'responder_id';
  static const _kResponderSecret = 'responder_secret';

  Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kContacts) ?? [];
    return raw
        .map((s) => EmergencyContact.fromJson(jsonDecode(s)))
        .toList();
  }

  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_kContacts, raw);
  }

  Future<void> addContact(EmergencyContact contact) async {
    final contacts = await getContacts();
    contacts.add(contact);
    await saveContacts(contacts);
  }

  Future<void> removeContact(String id) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.id == id);
    await saveContacts(contacts);
  }

  Future<void> updateContact(EmergencyContact updated) async {
    final contacts = await getContacts();
    final idx = contacts.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      contacts[idx] = updated;
      await saveContacts(contacts);
    }
  }

  Future<String?> getPairedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPairedDeviceId);
  }

  Future<void> setPairedDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPairedDeviceId, deviceId);
  }

  Future<String> getVictimName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVictimName) ?? '';
  }

  Future<void> setVictimName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVictimName, name);
  }

  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLanguage) ?? 'en';
  }

  Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, lang);
  }

  Future<bool> getAlwaysShareLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAlwaysShareLocation) ?? false;
  }

  Future<void> setAlwaysShareLocation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlwaysShareLocation, value);
  }

  /// null = user has never been asked "auto-initiate call to Police?"
  /// yet. true/false = their remembered answer, applied on every
  /// future SOS without asking again (changeable from Settings).
  Future<bool?> getAutoCallPolice() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kAutoCallPolice)) return null;
    return prefs.getBool(_kAutoCallPolice);
  }

  Future<void> setAutoCallPolice(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoCallPolice, value);
  }

  /// Opt-in: "alert me when someone near me needs help" (also shares this
  /// phone's approximate position with the backend, nothing else).
  Future<bool> getResponderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kResponderEnabled) ?? false;
  }

  Future<void> setResponderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kResponderEnabled, value);
  }

  /// Random id + secret that identify this phone to the backend. Created once.
  Future<void> ensureResponderCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kResponderId) == null) {
      const u = Uuid();
      await prefs.setString(_kResponderId, u.v4().replaceAll('-', ''));
      await prefs.setString(
          _kResponderSecret, u.v4().replaceAll('-', '') + u.v4().replaceAll('-', ''));
    }
  }

  /// Subscription id of the SIM that should send the automatic SMS (-1 = phone default).
  Future<int> getSmsSimSubId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSmsSimSubId) ?? -1;
  }

  Future<void> setSmsSimSubId(int subId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSmsSimSubId, subId);
  }

  /// True once the one-time "Display over other apps" / battery prompts
  /// were shown, so they are never pushed again on every screen visit.
  Future<bool> getSpecialPermsAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSpecialPermsAsked) ?? false;
  }

  Future<void> setSpecialPermsAsked(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpecialPermsAsked, value);
  }

  /// Names this user saved for people in location sharing (key = that
  /// person's uid). Stored only on this phone, so every user sees the
  /// names *they* chose.
  Future<Map<String, String>> getWatchLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWatchLabels);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setWatchLabel(String uid, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final m = await getWatchLabels();
    if (label.trim().isEmpty) {
      m.remove(uid);
    } else {
      m[uid] = label.trim();
    }
    await prefs.setString(_kWatchLabels, jsonEncode(m));
  }

  /// UI only: whether the first-run "Permission required" explainer screen
  /// has already been shown. Does not affect any permission logic.
  Future<bool> getPermissionIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPermIntroSeen) ?? false;
  }

  Future<void> setPermissionIntroSeen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermIntroSeen, value);
  }

  // ------------------------------------------------ registered safe location

  Future<RegisteredLocation?> getRegisteredLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final la = double.tryParse(prefs.getString(_kRegLat) ?? '');
    final lo = double.tryParse(prefs.getString(_kRegLon) ?? '');
    if (la == null || lo == null) return null;
    return RegisteredLocation(la, lo, prefs.getString(_kRegLabel) ?? 'Home');
  }

  Future<void> setRegisteredLocation(double lat, double lon, String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRegLat, lat.toString());
    await prefs.setString(_kRegLon, lon.toString());
    await prefs.setString(_kRegLabel, label);
  }

  Future<void> clearRegisteredLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRegLat);
    await prefs.remove(_kRegLon);
    await prefs.remove(_kRegLabel);
    await prefs.setBool(_kRegAlerts, false);
  }

  /// Second layer: alert this phone for SOS near the registered location,
  /// even when the phone's own location (GPS) is switched off.
  Future<bool> getRegisteredAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRegAlerts) ?? false;
  }

  Future<void> setRegisteredAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRegAlerts, value);
  }

  /// True once the first-run "register your location" screen was completed or skipped.
  Future<bool> getRegPromptDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRegPromptDone) ?? false;
  }

  Future<void> setRegPromptDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRegPromptDone, value);
  }
}
