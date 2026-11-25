import 'package:flutter/material.dart';
import '../screens/register_location_screen.dart';
import '../services/app_lang.dart';
import '../services/sos_bridge.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// "Safe Zone" card: shows the registered place, lets the user switch the
/// second-layer alert on/off (alerts near the place even when GPS is OFF),
/// change it, or remove it.
class SafeZoneCard extends StatefulWidget {
  const SafeZoneCard({super.key});

  @override
  State<SafeZoneCard> createState() => _SafeZoneCardState();
}

class _SafeZoneCardState extends State<SafeZoneCard> {
  final _storage = StorageService();
  RegisteredLocation? _loc;
  bool _on = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loc = await _storage.getRegisteredLocation();
    final on = await _storage.getRegisteredAlerts();
    if (!mounted) return;
    setState(() {
      _loc = loc;
      _on = on && loc != null;
      _loaded = true;
    });
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const RegisterLocationScreen()));
    await _load();
  }

  Future<void> _toggle(bool v) async {
    await _storage.setRegisteredAlerts(v);
    setState(() => _on = v);
    await SosBridge.startWatch(); // background service re-reads the setting
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove safe location?')),
        content: Text(tr('You will no longer be alerted for SOS near this place when your phone location is off.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.clearRegisteredLocation();
    await SosBridge.startWatch();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final loc = _loc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.maroonDark, AppColors.tabMaroon],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: loc == null ? _empty() : _registered(loc),
    );
  }

  Widget _empty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Safe Zone alerts'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            tr('Register your home / college location. When someone near it needs help, you will be alerted - even if your phone location is OFF.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.25)),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ElevatedButton.icon(
            onPressed: _openRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.tabMaroon,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(tr('Register my location'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ]),
      );

  Widget _registered(RegisteredLocation loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
                color: Colors.white24, shape: BoxShape.circle),
            child: Icon(_on ? Icons.shield_rounded : Icons.shield_outlined,
                color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tr('Safe Zone')}: ${tr(loc.label)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                Text(
                    '${loc.lat.toStringAsFixed(4)}, ${loc.lon.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(_on ? Icons.check_circle : Icons.pause_circle,
              _on ? tr('Protection ON') : tr('Protection OFF')),
          _chip(Icons.radar, tr('About 5 km')),
          _chip(Icons.location_off, tr('Works with GPS off')),
        ]),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _on,
          onChanged: _toggle,
          activeColor: Colors.white,
          activeTrackColor: AppColors.cardGreen,
          title: Text(tr('Alert me near this place'),
              style: const TextStyle(color: Colors.white, fontSize: 14.5)),
          subtitle: Text(tr('Even when my phone location is off'),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Row(children: [
          TextButton.icon(
            onPressed: _openRegister,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: Text(tr('Change')),
          ),
          TextButton.icon(
            onPressed: _remove,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tr('Remove')),
          ),
        ]),
      ],
    );
  }
}
