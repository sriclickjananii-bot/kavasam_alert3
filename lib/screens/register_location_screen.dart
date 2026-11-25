import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_lang.dart';
import '../services/sos_bridge.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/kaaval_widgets.dart';
import 'home_screen.dart';

/// "Register your safe location": shown once when the app is first opened
/// (and any time from the Safe Zone card / side menu).
///
/// The saved place is the SECOND LAYER of protection: when someone near it
/// raises an SOS, this phone is alerted even if its own location (GPS) is OFF.
class RegisterLocationScreen extends StatefulWidget {
  /// true = first launch: after saving / skipping, go to the home screen.
  final bool firstRun;
  const RegisterLocationScreen({super.key, this.firstRun = false});

  @override
  State<RegisterLocationScreen> createState() => _RegisterLocationScreenState();
}

class _RegisterLocationScreenState extends State<RegisterLocationScreen> {
  static const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _fallback = LatLng(11.0168, 76.9558); // Coimbatore
  static const _labels = ['Home', 'College', 'Work', 'Other'];
  static const _labelIcons = <String, IconData>{
    'Home': Icons.home_rounded,
    'College': Icons.school_rounded,
    'Work': Icons.work_rounded,
    'Other': Icons.place_rounded,
  };

  final _storage = StorageService();
  final _map = MapController();

  bool _loaded = false;
  bool _locating = false;
  bool _saving = false;
  LatLng? _pin;
  String _label = 'Home';

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final r = await _storage.getRegisteredLocation();
    if (!mounted) return;
    setState(() {
      if (r != null) {
        _pin = LatLng(r.lat, r.lon);
        _label = _labels.contains(r.label) ? r.label : 'Other';
      }
      _loaded = true;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Turn on location')),
            content: Text(tr(
                'Please switch on your phone location once, so we can save your place. You can switch it off afterwards - alerts will still reach this saved place.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(tr('Cancel'))),
              ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(tr('Open settings'))),
            ],
          ),
        );
        if (open == true) await Geolocator.openLocationSettings();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack(tr('Location permission is needed once to find your place. You can also tap the map to place the pin.'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      _setPin(LatLng(pos.latitude, pos.longitude), zoom: 16);
    } catch (_) {
      _snack(tr('Could not get your location. Tap the map to place the pin instead.'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _setPin(LatLng p, {double? zoom}) {
    setState(() => _pin = p);
    try {
      _map.move(p, zoom ?? _map.camera.zoom);
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = _pin;
    if (p == null || _saving) return;
    setState(() => _saving = true);
    await _storage.setRegisteredLocation(p.latitude, p.longitude, _label);
    await _storage.setRegisteredAlerts(true);
    await _storage.setRegPromptDone(true);
    // Needed so the alert can appear while the app is closed.
    try {
      await Permission.notification.request();
    } catch (_) {}
    await SosBridge.startWatch(); // background service re-reads the saved place
    if (!mounted) return;
    _snack(tr('Safe location saved. You will be alerted for SOS near this place.'));
    _finish(true);
  }

  Future<void> _skip() async {
    await _storage.setRegPromptDone(true);
    if (!mounted) return;
    _finish(false);
  }

  void _finish(bool saved) {
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.of(context).pop(saved);
    }
  }

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.tabMaroon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr(text),
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.25, color: Color(0xFF444444))),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.settingsBg,
      appBar: kaavalAppBar(
        automaticallyImplyLeading: !widget.firstRun,
        title: Text(tr('REGISTER YOUR LOCATION'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w400)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    children: [
                      // ---- header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.maroonDark, AppColors.tabMaroon],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                  color: Colors.white24, shape: BoxShape.circle),
                              child: const Icon(Icons.shield_rounded,
                                  color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr('Set your Safe Zone'),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                      tr('Register the place you want protected. We will alert you when someone nearby needs help.'),
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.25)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ---- map
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 250,
                          child: Stack(
                            children: [
                              FlutterMap(
                                mapController: _map,
                                options: MapOptions(
                                  initialCenter: _pin ?? _fallback,
                                  initialZoom: _pin != null ? 15 : 11,
                                  maxZoom: 19,
                                  onTap: (_, point) => _setPin(point),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: _osm,
                                    maxNativeZoom: 19,
                                    userAgentPackageName:
                                        'com.example.kavasam_alert',
                                  ),
                                  if (_pin != null)
                                    CircleLayer(circles: [
                                      CircleMarker(
                                        point: _pin!,
                                        radius: 5000, // 5 km: first alert ring
                                        useRadiusInMeter: true,
                                        color: AppColors.tabMaroon
                                            .withOpacity(0.12),
                                        borderColor: AppColors.tabMaroon
                                            .withOpacity(0.6),
                                        borderStrokeWidth: 1.5,
                                      ),
                                    ]),
                                  if (_pin != null)
                                    MarkerLayer(markers: [
                                      Marker(
                                        point: _pin!,
                                        width: 46,
                                        height: 46,
                                        alignment: Alignment.topCenter,
                                        child: const Icon(Icons.location_on,
                                            size: 46,
                                            color: AppColors.emergencyRed),
                                      ),
                                    ]),
                                ],
                              ),
                              if (_pin == null)
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  top: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.92),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                        tr('Tap the map to drop the pin, or use your current location.'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12.5)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _locating ? null : _useCurrentLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.tabMaroon,
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.tabMaroon),
                            ),
                          ),
                          icon: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location),
                          label: Text(tr('Use my current location'),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ---- label chips
                      Text(tr('What is this place?'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: _labels
                            .map((l) => ChoiceChip(
                                  avatar: Icon(_labelIcons[l],
                                      size: 18,
                                      color: _label == l
                                          ? Colors.white
                                          : AppColors.tabMaroon),
                                  label: Text(tr(l)),
                                  selected: _label == l,
                                  selectedColor: AppColors.tabMaroon,
                                  labelStyle: TextStyle(
                                      color: _label == l
                                          ? Colors.white
                                          : Colors.black87),
                                  showCheckmark: false,
                                  onSelected: (_) => setState(() => _label = l),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      // ---- how it works
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('How your Safe Zone works'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 8),
                            _point(Icons.notifications_active_outlined,
                                'When an SOS is raised within about 5 km of this place, your phone rings the alert.'),
                            _point(Icons.location_off_outlined,
                                'It works even when your phone location (GPS) is switched OFF.'),
                            _point(Icons.lock_outline,
                                'The place is saved only on this phone. Change or remove it any time.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        if (widget.firstRun) ...[
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: _saving ? null : _skip,
                                child: Text(tr('Skip for now')),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: (_pin == null || _saving) ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.tabMaroon,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                  tr(widget.firstRun
                                      ? 'Save & Continue'
                                      : 'Save location'),
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
