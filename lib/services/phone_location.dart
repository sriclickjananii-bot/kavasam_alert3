import 'package:geolocator/geolocator.dart';

/// Position of THIS phone (used when no SOS device is paired / nearby).
class PhoneLocation {
  /// Best available position: a fresh fix within [wait], otherwise the
  /// last known one. Returns null if location is off or not permitted.
  static Future<Position?> best({Duration wait = const Duration(seconds: 7)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await Geolocator.getLastKnownPosition();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: wait,
        );
      } catch (_) {
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      return null;
    }
  }
}
