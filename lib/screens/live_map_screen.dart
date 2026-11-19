import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_lang.dart';
import '../services/location_share_service.dart';
import '../theme/app_theme.dart';

/// Parent view: live position of one person who invited me.
/// Shows: street / satellite map, accuracy circle, recent path, speed,
/// altitude, exact coordinates, last-update time, distance from me,
/// zoom buttons, "center" / "show both" and Navigate / Copy actions.
class LiveMapScreen extends StatefulWidget {
  final String ownerUid;
  final String ownerName;
  const LiveMapScreen({super.key, required this.ownerUid, required this.ownerName});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _map = MapController();
  LatLng? _last;
  final List<LatLng> _trail = []; // recent positions seen while this screen is open
  LatLng? _me; // my own position (blue dot)
  bool _satellite = false;

  static const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _sat =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          );
      if (mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
    } catch (_) {}
  }

  String _ago(Timestamp? t) {
    if (t == null) return tr('unknown');
    final d = DateTime.now().difference(t.toDate());
    if (d.inSeconds < 60) return tr('just now');
    if (d.inMinutes < 60) return '${d.inMinutes} ${tr('min ago')}';
    if (d.inHours < 48) return '${d.inHours} ${tr('h ago')}';
    return '${d.inDays} ${tr('days ago')}';
  }

  String _clock(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _dist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(2)} km';

  void _zoom(double delta) {
    try {
      final z = (_map.camera.zoom + delta).clamp(3.0, 19.0);
      _map.move(_map.camera.center, z);
    } catch (_) {}
  }

  void _center(LatLng pos) {
    try {
      _map.move(pos, 17);
    } catch (_) {}
  }

  void _showBoth(LatLng pos) {
    final me = _me;
    if (me == null) {
      _center(pos);
      return;
    }
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([pos, me]),
        padding: const EdgeInsets.all(70),
        maxZoom: 18,
      ));
    } catch (_) {}
  }

  Widget _fab(IconData icon, VoidCallback onTap, {String? tip}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          elevation: 3,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tip ?? '',
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 22, color: AppColors.tabMaroon),
              ),
            ),
          ),
        ),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(tr(label),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ownerName),
        actions: [
          IconButton(
            tooltip: tr('Map type'),
            icon: Icon(_satellite ? Icons.map : Icons.satellite_alt),
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: LocationShareService.instance.ownerLocation(widget.ownerUid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(tr('Access removed or not available.')));
          }
          final d = snap.data?.data();
          if (d == null || d['lastLat'] == null) {
            return Center(child: Text(tr('Waiting for the first location…')));
          }
          final pos = LatLng(
              (d['lastLat'] as num).toDouble(), (d['lastLng'] as num).toDouble());
          if (_last != pos) {
            _last = pos;
            if (_trail.isEmpty || _trail.last != pos) {
              _trail.add(pos);
              if (_trail.length > 200) _trail.removeAt(0);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                _map.move(pos, _map.camera.zoom);
              } catch (_) {}
            });
          }
          final sharing = d['sharing'] == true;
          final updated = d['lastUpdated'] as Timestamp?;
          final acc = (d['accuracy'] as num?)?.toDouble();
          final speed = (d['speed'] as num?)?.toDouble(); // m/s
          final alt = (d['altitude'] as num?)?.toDouble();
          final meters = _me == null
              ? null
              : const Distance().as(LengthUnit.Meter, _me!, pos);

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: pos,
                        initialZoom: 17,
                        minZoom: 3,
                        maxZoom: 19,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _satellite ? _sat : _osm,
                          maxNativeZoom: 19,
                          userAgentPackageName: 'com.example.kavasam_alert',
                        ),
                        if (acc != null && acc > 0)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: pos,
                              radius: acc,
                              useRadiusInMeter: true,
                              color: Colors.blue.withOpacity(0.15),
                              borderColor: Colors.blue.withOpacity(0.6),
                              borderStrokeWidth: 1.5,
                            ),
                          ]),
                        if (_trail.length > 1)
                          PolylineLayer(polylines: [
                            Polyline(
                              points: List<LatLng>.from(_trail),
                              strokeWidth: 4,
                              color: AppColors.tabMaroon.withOpacity(0.8),
                            ),
                          ]),
                        MarkerLayer(markers: [
                          if (_me != null)
                            Marker(
                              point: _me!,
                              width: 26,
                              height: 26,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black38, blurRadius: 4)
                                  ],
                                ),
                              ),
                            ),
                          Marker(
                            point: pos,
                            width: 48,
                            height: 48,
                            child: const Icon(Icons.location_pin,
                                color: AppColors.emergencyRed, size: 48),
                          ),
                        ]),
                        const RichAttributionWidget(attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ]),
                      ],
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Column(
                        children: [
                          _fab(Icons.add, () => _zoom(1)),
                          _fab(Icons.remove, () => _zoom(-1)),
                          _fab(Icons.my_location, () => _center(pos),
                              tip: tr('Center on person')),
                          _fab(Icons.zoom_out_map, () => _showBoth(pos),
                              tip: tr('Show both')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 12,
                              color: sharing ? AppColors.safeGreen : Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${sharing ? tr('Sharing') : tr('Sharing paused')} · ${tr('updated')} ${_ago(updated)}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _info('Last update', '${_clock(updated)}  (${_ago(updated)})'),
                      _info('Coordinates',
                          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}'),
                      if (acc != null) _info('Accuracy', '± ${acc.round()} m'),
                      if (speed != null && speed >= 0)
                        _info('Speed', '${(speed * 3.6).toStringAsFixed(1)} km/h'),
                      if (alt != null) _info('Altitude', '${alt.round()} m'),
                      if (meters != null)
                        _info('Distance from you', _dist(meters)),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.directions),
                            label: Text(tr('Navigate')),
                            onPressed: () => launchUrl(
                              Uri.parse(
                                  'https://maps.google.com/?q=${pos.latitude},${pos.longitude}'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.copy, size: 18),
                            label: Text(tr('Copy coordinates')),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text:
                                      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(tr('Copied'))));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
