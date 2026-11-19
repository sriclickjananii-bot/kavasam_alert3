import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Dart side of the nearby-responder network (the native service does the
/// listening). Two jobs:
///  1. [raiseAlert]: an SOS pressed on this phone also alerts nearby phones.
///  2. [markContactResponded]: an emergency contact tells the network that
///     someone is acting, which stops the alert from widening to 10 km.
/// Both fail silently if Firebase is not configured / the phone is offline.
class ResponderCloud {
  static Future<String?> _uid() async {
    try {
      final a = FirebaseAuth.instance;
      final u = a.currentUser ??
          (await a.signInAnonymously().timeout(const Duration(seconds: 2))).user;
      return u?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Writes the alert and returns its id (put it in the SMS as "Ref:<id>").
  static Future<String?> raiseAlert({
    required String name,
    required double lat,
    required double lon,
  }) async {
    final uid = await _uid();
    if (uid == null) return null;
    final key = 'p${uid.substring(0, 6)}'; // "p" = raised from a phone button
    final seq = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000;
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 600000;
    final id = '${key}_${seq}_$bucket';
    try {
      // not awaited: Firestore queues the write if the phone is offline
      FirebaseFirestore.instance.collection('alerts').doc(id).set({
        'key': key,
        'seq': seq,
        'name': name.length > 40 ? name.substring(0, 40) : name,
        'lat': lat,
        'lon': lon,
        'raisedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
      return id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> markContactResponded(String alertRef) async {
    if (alertRef.isEmpty) return;
    final uid = await _uid();
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(alertRef)
          .collection('responses')
          .doc('${uid}_contact')
          .set({'type': 'contact', 'at': FieldValue.serverTimestamp()});
    } catch (_) {}
  }
}
