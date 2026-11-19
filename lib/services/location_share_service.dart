import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';

/// Result of accepting an invite (so the app can save a name for that person).
class AcceptedInvite {
  final String ownerUid;
  final String ownerName; // name the owner set in their own Settings
  final String forName; // name the owner typed when creating the invite (may be empty)
  AcceptedInvite(this.ownerUid, this.ownerName, this.forName);
}

/// Always-on live location for parents / invited contacts.
///
/// Firestore layout (rules in backend/firestore.rules):
///   sharing_sessions/{ownerUid}            lastLat, lastLng, lastUpdated, ownerName, sharing
///   sharing_sessions/{ownerUid}/watchers/{uid}   people who can see me
///   users/{uid}/watching/{ownerUid}        people I can see
///
/// Identity = Firebase anonymous auth uid (stable until the app data is cleared).
class LocationShareService {
  LocationShareService._();
  static final LocationShareService instance = LocationShareService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = StorageService();

  StreamSubscription<Position>? _sub;
  bool get isSharing => _sub != null;

  Future<String> ensureSignedIn() async {
    final u = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    return u!.uid;
  }

  String? get uid => _auth.currentUser?.uid;

  // ------------------------------------------------------------- invites
  // (Free plan: no Cloud Functions. The Firestore rules enforce the same checks.)

  Future<String> createInvite(String ownerName, {String forName = ''}) async {
    final me = await ensureSignedIn();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final code = List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    await _db.collection('invites').doc(code).set({
      'ownerUid': me,
      'ownerName': ownerName,
      if (forName.trim().isNotEmpty) 'forName': forName.trim(),
      'used': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 48))),
    });
    return code;
  }

  /// Returns who the owner is, or throws a readable message.
  Future<AcceptedInvite> acceptInvite(String code, String contactName) async {
    final me = await ensureSignedIn();
    try {
      final ref = _db.collection('invites').doc(code);
      final snap = await ref.get();
      if (!snap.exists) throw 'Invite code not found';
      final inv = snap.data()!;
      if (inv['used'] == true) throw 'This code was already used';
      if ((inv['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
        throw 'This code has expired';
      }
      final owner = inv['ownerUid'] as String;
      if (owner == me) throw 'That is your own code';

      await ref.update({'used': true, 'usedBy': me});
      await _db
          .collection('sharing_sessions')
          .doc(owner)
          .collection('watchers')
          .doc(me)
          .set({
        'name': contactName,
        'inviteFor': (inv['forName'] as String?) ?? '',
        'since': FieldValue.serverTimestamp(),
        'inviteCode': code,
      });
      await _db.collection('users').doc(me).collection('watching').doc(owner).set({
        'ownerName': inv['ownerName'] ?? 'Family',
        'since': FieldValue.serverTimestamp(),
      });
      return AcceptedInvite(
        owner,
        inv['ownerName'] as String? ?? '',
        inv['forName'] as String? ?? '',
      );
    } on FirebaseException catch (e) {
      throw e.message ?? 'Could not accept the invite';
    }
  }

  /// Owner removes a watcher, or a watcher stops watching.
  Future<void> revokeAccess({required String ownerUid, required String watcherUid}) async {
    await ensureSignedIn();
    final batch = _db.batch();
    batch.delete(_db
        .collection('sharing_sessions')
        .doc(ownerUid)
        .collection('watchers')
        .doc(watcherUid));
    batch.delete(_db.collection('users').doc(watcherUid).collection('watching').doc(ownerUid));
    await batch.commit();
  }

  // ------------------------------------------------------------- streams

  /// People who can currently see MY location.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchers() => _db
      .collection('sharing_sessions')
      .doc(uid)
      .collection('watchers')
      .snapshots();

  /// People whose location I can see (I am the parent).
  Stream<QuerySnapshot<Map<String, dynamic>>> watching() =>
      _db.collection('users').doc(uid).collection('watching').snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> ownerLocation(String ownerUid) =>
      _db.collection('sharing_sessions').doc(ownerUid).snapshots();

  // ------------------------------------------------------------- sharing

  /// Publishes this phone's location until [stopSharing]. Uses a foreground
  /// notification so Android keeps it running with the app in the background.
  Future<bool> startSharing() async {
    final myUid = await ensureSignedIn();
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return false;
    }
    await Permission.locationAlways.request(); // "Allow all the time" for background sharing

    await _sub?.cancel();
    final name = await _storage.getVictimName();
    final ref = _db.collection('sharing_sessions').doc(myUid);

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Kavasam Alert',
        notificationText: 'Sharing your live location with your family',
        enableWakeLock: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      ref.set({
        'ownerName': name.isEmpty ? 'Kavasam user' : name,
        'lastLat': p.latitude,
        'lastLng': p.longitude,
        'accuracy': p.accuracy,
        'speed': p.speed, // m/s
        'heading': p.heading, // degrees
        'altitude': p.altitude, // metres
        'lastUpdated': FieldValue.serverTimestamp(),
        'sharing': true,
      }, SetOptions(merge: true)).catchError((_) {});
    });
    return true;
  }

  Future<void> stopSharing() async {
    await _sub?.cancel();
    _sub = null;
    final id = uid;
    if (id != null) {
      await _db
          .collection('sharing_sessions')
          .doc(id)
          .set({'sharing': false}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// Called at app start: continue sharing if the user left it switched on.
  Future<void> resumeIfEnabled() async {
    if (await _storage.getAlwaysShareLocation()) await startSharing();
  }
}
