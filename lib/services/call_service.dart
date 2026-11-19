import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Places a phone call. If CALL_PHONE permission is granted, the call
/// is placed directly with no dialer screen shown at all (this is
/// what "auto-initiate call to Police" needs). If the permission is
/// denied, falls back to opening the normal dialer pre-filled with
/// the number, which still requires the user to tap the call button.
class CallService {
  Future<bool> callNumberDirectly(String number) async {
    final status = await Permission.phone.request();
    if (status.isGranted) {
      try {
        final ok = await FlutterPhoneDirectCaller.callNumber(number);
        if (ok == true) return true;
      } catch (_) {
        // fall through to dialer fallback
      }
    }
    final uri = Uri(scheme: 'tel', path: number);
    return launchUrl(uri);
  }
}
