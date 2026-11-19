import 'dart:typed_data';

/// Mirrors the manufacturer-data layout produced by the ESP32 firmware
/// (kavasam_trigger.ino):
///
///   byte 0-1   company id (little endian) -> 0xFFFE
///   byte 2     packet type: 0x00 heartbeat, 0x01 SOS
///   byte 3     status flags: bit0 = location present, bit1 = button held,
///                          bit2 = location is the last known one (not live)
///   byte 4     SOS sequence number (changes on every new button press)
///   byte 5-8   latitude  int32 little-endian, scaled *1,000,000
///   byte 9-12  longitude int32 little-endian, scaled *1,000,000
///   byte 13-17 emergency contact 1 (10 digits, packed BCD, 0xF = unused)
///   byte 18-22 emergency contact 2 (10 digits, packed BCD, 0xF = unused)
///   byte 23    age of the location in units of 10 s (0 = live, 0xFF = unknown)
class SosPacket {
  final int packetType;
  final bool gpsFixValid;
  final bool buttonHeld;
  final double latitude;
  final double longitude;
  final int sequence;

  /// True when the location is the device's last known fix, not a live one.
  final bool lastKnown;

  /// Age of the location in seconds (0 when live).
  final int locationAgeSeconds;

  /// Victim's emergency contact numbers, read from the packet itself.
  final List<String> emergencyNumbers;

  static const int expectedCompanyId = 0xFFFE;

  SosPacket({
    required this.packetType,
    required this.gpsFixValid,
    required this.buttonHeld,
    required this.latitude,
    required this.longitude,
    this.sequence = 0,
    this.lastKnown = false,
    this.locationAgeSeconds = 0,
    this.emergencyNumbers = const [],
  });

  bool get isSos => packetType == 0x01;

  /// Returns null if [bytes] doesn't match our expected layout/company id.
  static SosPacket? tryParse(Uint8List bytes) {
    if (bytes.length < 13) return null;

    final companyId = bytes[0] | (bytes[1] << 8);
    if (companyId != expectedCompanyId) return null;

    final bd = ByteData.sublistView(bytes);
    final flags = bytes[3];

    final numbers = <String>[];
    for (var off = 13; off + 5 <= bytes.length && numbers.length < 3; off += 5) {
      final n = _decodePhone(bytes, off);
      if (n != null) numbers.add(n);
    }

    return SosPacket(
      packetType: bytes[2],
      gpsFixValid: (flags & 0x01) != 0,
      buttonHeld: (flags & 0x02) != 0,
      sequence: bytes[4],
      lastKnown: (flags & 0x04) != 0,
      locationAgeSeconds: bytes.length > 23 ? bytes[23] * 10 : 0,
      latitude: bd.getInt32(5, Endian.little) / 1000000.0,
      longitude: bd.getInt32(9, Endian.little) / 1000000.0,
      emergencyNumbers: numbers,
    );
  }

  static String? _decodePhone(Uint8List b, int off) {
    final sb = StringBuffer();
    for (var i = 0; i < 5; i++) {
      final hi = b[off + i] >> 4;
      final lo = b[off + i] & 0x0F;
      if (hi > 9) break;
      sb.write(hi);
      if (lo > 9) break;
      sb.write(lo);
    }
    final s = sb.toString();
    return s.length >= 6 ? s : null;
  }

  String get googleMapsUrl =>
      'https://maps.google.com/?q=$latitude,$longitude';
}