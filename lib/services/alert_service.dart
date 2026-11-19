import 'native_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/emergency_contact.dart';
import '../models/sos_packet.dart';

class AlertDispatchResult {
  final List<String> succeededNumbers;
  final List<String> failedNumbers;
  AlertDispatchResult({
    required this.succeededNumbers,
    required this.failedNumbers,
  });

  int get succeeded => succeededNumbers.length;
  int get failed => failedNumbers.length;
}

/// Sends a silent SMS -- no composer opened, nothing for the user to tap --
/// to the saved emergency contacts when the in-app EMERGENCY button is
/// used. (SOS packets received over BLE are handled by the native
/// BleWatchService, which sends the SMS to the numbers carried inside the
/// packet. SMS to 100 is not possible, so Police is reached by call only.)
class AlertService {

  String _buildMessage({
    required String victimName,
    required SosPacket packet,
    String? alertRef,
  }) {
    final locationLine = packet.gpsFixValid
        ? 'Location: ${packet.latitude.toStringAsFixed(6)}, '
            '${packet.longitude.toStringAsFixed(6)}\n'
            'Map: ${packet.googleMapsUrl}'
        : 'Location: not available yet (GPS fix pending).';

    return 'KAVASAM-SOS|$victimName\nSOS ALERT\n'
        '$victimName is in danger and needs help. '
        'You are listed as their emergency contact.\n'
        '$locationLine\n'
        'Please call them / contact Police (100) immediately.\n'
        '${alertRef != null ? 'Ref:$alertRef\n' : ''}'
        '(Sent automatically by Kavasam Alert)';
  }

  /// Sends a silent SMS to every saved emergency contact. Returns which numbers succeeded/failed so the caller
  /// (the SOS alert screen) can show a status line.
  Future<AlertDispatchResult> dispatchSos({
    required String victimName,
    required SosPacket packet,
    required List<EmergencyContact> contacts,
    String? alertRef,
  }) async {
    final message =
        _buildMessage(victimName: victimName, packet: packet, alertRef: alertRef);
    final numbers = contacts.map((c) => c.phoneNumber).toList();

    final succeeded = <String>[];
    final failed = <String>[];

    final smsStatus = await Permission.sms.request();

    for (final number in numbers) {
      if (!smsStatus.isGranted) {
        failed.add(number);
        continue;
      }
      final ok = await NativeSms.send(to: number, message: message);
      ok ? succeeded.add(number) : failed.add(number);
    }

    return AlertDispatchResult(succeededNumbers: succeeded, failedNumbers: failed);
  }
}