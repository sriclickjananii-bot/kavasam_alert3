import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_lang.dart';
import '../services/phone_location.dart';
import '../services/responder_cloud.dart';
import '../services/video_saver.dart';
import '../models/sos_packet.dart';
import '../services/alert_service.dart';
import '../services/call_service.dart';
import '../services/notification_service.dart';
import '../services/sos_bridge.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// The highest-priority, full-screen, red SOS popup. This is what the
/// EMERGENCY tab pushes the instant a trigger fires (manual button or
/// a real SOS packet from the paired device) — it is also what the
/// full-screen-intent notification brings to the front if the app was
/// backgrounded when the SOS happened.
///
/// It dispatches the silent SMS itself (Police 100 + saved emergency
/// contacts) as soon as it opens, plays a looping siren, and — once
/// the user has answered the "auto-call Police?" question the first
/// time — either counts down to an automatic direct call or offers a
/// one-tap manual call button, per their remembered choice.
class SosAlertScreen extends StatefulWidget {
  final SosPacket packet;
  final String source; // 'device' or 'manual'

  /// For 'device' alerts the native BleWatchService has already sent the
  /// SMS (to the victim's numbers from the packet); this is its result.
  final AlertDispatchResult? preDispatched;

  /// Victim's name (from the device packet or the SMS), if known.
  final String? victimName;

  /// For 'nearby' alerts: metres between this phone and the victim (-1/null = unknown).
  final int? distanceM;

  /// For 'sms' alerts: id of the cloud alert (from the SMS "Ref:" line), used to
  /// tell the responder network that an emergency contact is acting.
  final String? alertRef;

  const SosAlertScreen({
    super.key,
    required this.packet,
    required this.source,
    this.preDispatched,
    this.victimName,
    this.distanceM,
    this.alertRef,
  });

  @override
  State<SosAlertScreen> createState() => _SosAlertScreenState();
}

enum _SmsState { sending, sent, failed }

class _SosAlertScreenState extends State<SosAlertScreen> {
  final _storage = StorageService();
  final _alerts = AlertService();
  final _calls = CallService();
  final _player = AudioPlayer();

  _SmsState _smsState = _SmsState.sending;
  AlertDispatchResult? _result;

  // location actually used (device location if it was heard, else this phone)
  late SosPacket _packet = widget.packet;
  String _locSource = ''; // 'phone' | 'device' | ''

  // evidence video (phone-triggered SOS only)
  static const int _recordSeconds = 12;
  CameraController? _cam;
  bool _rec = false;
  bool _finishing = false;
  int _recLeft = 0;
  String _recStatus = '';
  Timer? _recTimer;

  bool _responded = false;

  bool _loadedAutoCallPref = false;
  bool? _storedAutoCallChoice; // null = never asked before
  bool _calling = false;
  int _countdown = 3;

  @override
  void initState() {
    super.initState();
    SosBridge.alertOpen = true;
    // Device alerts: the native service already plays the alarm and has
    // already sent the SMS. Manual alerts: do both here.
    if (widget.source == 'manual') _startSiren();
    if (widget.source == 'sms' || widget.source == 'nearby') {
      _smsState = _SmsState.sent; // nothing to send: this phone received the alert
    } else if (widget.preDispatched != null) {
      _result = widget.preDispatched;
      _smsState = _result!.failed == 0 && _result!.succeeded > 0
          ? _SmsState.sent
          : _SmsState.failed;
    } else {
      _sendSms();
    }
    _loadAutoCallChoice();
    if (widget.source == 'manual') _startEvidence();
  }

  // ------------------------------------------------------ evidence video

  Future<void> _startEvidence() async {
    try {
      var cam = await Permission.camera.status;
      if (!cam.isGranted) cam = await Permission.camera.request();
      if (!cam.isGranted) return;
      final mic = await Permission.microphone.request();
      await Permission.storage.request(); // only matters on Android 9 and older
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(back, ResolutionPreset.medium,
          enableAudio: mic.isGranted);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _cam = ctrl;
      await ctrl.startVideoRecording();
      if (!mounted) {
        await _finishEvidence();
        return;
      }
      setState(() {
        _rec = true;
        _recLeft = _recordSeconds;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_recLeft <= 1) {
          t.cancel();
          _finishEvidence();
        } else {
          setState(() => _recLeft -= 1);
        }
      });
    } catch (_) {
      // camera not available / denied: the SOS itself is unaffected
    }
  }

  /// Stops the recording (if still running) and copies the video to the gallery.
  Future<void> _finishEvidence() async {
    if (_finishing) return;
    _finishing = true;
    _recTimer?.cancel();
    final c = _cam;
    _cam = null;
    if (c == null) return;
    String? path;
    try {
      if (c.value.isRecordingVideo) {
        final f = await c.stopVideoRecording();
        path = f.path;
      }
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _rec = false;
        _recStatus = 'saving';
      });
    }
    final ok = path != null && await VideoSaver.saveToGallery(path);
    if (mounted) setState(() => _recStatus = ok ? 'saved' : 'failed');
  }

  /// Emergency contact: tell the responder network that someone is acting.
  Future<void> _markResponded() async {
    if (widget.source != 'sms') return;
    final ref = widget.alertRef ?? '';
    if (ref.isEmpty) return;
    if (mounted) setState(() => _responded = true);
    await ResponderCloud.markContactResponded(ref);
  }

  Future<void> _startSiren() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/sos_alarm.wav'), volume: 1.0);
    } catch (_) {
      // Non-fatal — the notification channel's own sound already
      // played once even if the in-app loop fails to start.
    }
  }

  Future<void> _sendSms() async {
    final name = await _storage.getVictimName();
    final contacts = await _storage.getContacts();
    final who = name.isEmpty ? 'A Kavasam user' : name;

    // 1) Location: the paired SOS device if it was heard, otherwise THIS phone.
    var packet = widget.packet;
    if (packet.gpsFixValid) {
      _locSource = 'device';
    } else {
      final pos = await PhoneLocation.best();
      if (pos != null) {
        packet = SosPacket(
          packetType: 0x01,
          gpsFixValid: true,
          buttonHeld: true,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        _locSource = 'phone';
      }
    }
    if (mounted) setState(() => _packet = packet);

    // 2) Also alert the nearby phones (responder network).
    String? ref;
    if (packet.gpsFixValid) {
      ref = await ResponderCloud.raiseAlert(
        name: who,
        lat: packet.latitude,
        lon: packet.longitude,
      );
    }

    // 3) SMS to the emergency contacts.
    final result = await _alerts.dispatchSos(
      victimName: who,
      packet: packet,
      contacts: contacts,
      alertRef: ref,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _smsState = result.failed == 0 ? _SmsState.sent : _SmsState.failed;
    });
    await NotificationService.instance.showDispatchResult(
      succeeded: result.succeeded,
      failed: result.failed,
    );
  }

  Future<void> _loadAutoCallChoice() async {
    final choice = await _storage.getAutoCallPolice();
    if (!mounted) return;
    setState(() {
      // Only an explicit "always auto-call" setting skips the question;
      // otherwise we ask on every alert.
      _storedAutoCallChoice = choice == true ? true : null;
      _loadedAutoCallPref = true;
    });
    if (choice == true) {
      _beginAutoCallCountdown();
    }
  }

  void _beginAutoCallCountdown() {
    setState(() => _calling = true);
    Future<void>.delayed(const Duration(seconds: 1), _tickCountdown);
  }

  void _tickCountdown() {
    if (!mounted || !_calling) return;
    if (_countdown <= 1) {
      _placeCall();
      return;
    }
    setState(() => _countdown -= 1);
    Future<void>.delayed(const Duration(seconds: 1), _tickCountdown);
  }

  Future<void> _placeCall() async {
    _markResponded();
    await _calls.callNumberDirectly('100');
  }

  void _cancelAutoCall() {
    setState(() {
      _calling = false;
      _countdown = 3;
    });
  }

  Future<void> _answerAutoCallPrompt(bool enable) async {
    // Not remembered: the question is asked again on the next alert.
    setState(() => _storedAutoCallChoice = false);
    if (enable) {
      await _placeCall();
    }
  }

  Future<void> _dismiss() async {
    await _finishEvidence();
    await _player.stop();
    await SosBridge.stopAlarm();
    await NotificationService.instance.clearSosAlert();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    SosBridge.alertOpen = false;
    _recTimer?.cancel();
    if (_cam != null) _finishEvidence();
    _player.dispose();
    super.dispose();
  }

  Widget _evidenceRow() {
    if (widget.source != 'manual') return const SizedBox.shrink();
    final c = _cam;
    final String text;
    if (_rec) {
      text = '${tr('Recording evidence video…')} ${_recLeft}s';
    } else if (_recStatus == 'saving') {
      text = tr('Saving video to gallery…');
    } else if (_recStatus == 'saved') {
      text = tr('Video saved to your gallery');
    } else if (_recStatus == 'failed') {
      text = tr('Could not save the video');
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (_rec && c != null && c.value.isInitialized)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 60,
                  height: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CameraPreview(c),
                  ),
                ),
              ),
            Icon(_rec ? Icons.fiber_manual_record : Icons.videocam,
                color: _rec ? Colors.redAccent : Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _packet;
    final manual = widget.source == 'manual';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.emergencyRed,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 72),
                      const SizedBox(height: 8),
                      Text(
                        manual
                            ? tr('YOUR SOS IS TRIGGERED')
                            : tr('EMERGENCY ALERT'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (manual) ...[
                        const SizedBox(height: 8),
                        Text(
                          tr('Your emergency contacts are being alerted with your location.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                        ),
                      ],
                      if ((widget.victimName ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${widget.victimName} ${tr('is in danger!')}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (!manual) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.source == 'device'
                              ? tr('SOS signal received from your device')
                              : widget.source == 'sms'
                                  ? tr('SOS received by SMS — someone you know needs help')
                                  : ((widget.distanceM ?? -1) >= 0
                                      ? '${tr('You are one of the nearest people — about')} ${widget.distanceM} ${tr('m away')}'
                                      : tr('You are one of the nearest people to the victim')),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 15),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _StatusCard(
                        smsState: _smsState,
                        result: _result,
                        packet: p,
                        fromSms: widget.source == 'sms',
                        nearby: widget.source == 'nearby',
                        locSource: _locSource,
                      ),
                      _evidenceRow(),
                      if ((widget.source == 'nearby' ||
                              widget.source == 'sms') &&
                          p.gpsFixValid) ...[
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(p.googleMapsUrl),
                              mode: LaunchMode.externalApplication),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.emergencyRed),
                          icon: const Icon(Icons.directions),
                          label: Text(tr('Navigate to the victim')),
                        ),
                      ],
                      if (widget.source == 'sms' &&
                          (widget.alertRef ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _responded
                            ? Text(tr('Thanks — your response was noted.'),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14))
                            : OutlinedButton.icon(
                                onPressed: _markResponded,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white),
                                ),
                                icon: const Icon(Icons.volunteer_activism),
                                label: Text(tr('I am responding')),
                              ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_loadedAutoCallPref)
                      const CircularProgressIndicator(color: Colors.white)
                    else if (_calling)
                      _CallingCountdown(
                        countdown: _countdown,
                        onCancel: _cancelAutoCall,
                      )
                    else if (_storedAutoCallChoice == null)
                      _AutoCallPrompt(onAnswer: _answerAutoCallPrompt)
                    else
                      _ManualCallButton(
                        onCallNow: () {
                          _markResponded();
                          _calls.callNumberDirectly('100');
                        },
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _dismiss,
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white70),
                      child: Text(tr('Dismiss')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final _SmsState smsState;
  final AlertDispatchResult? result;
  final SosPacket packet;
  final bool fromSms;
  final bool nearby;
  final String locSource;

  const _StatusCard({
    required this.smsState,
    required this.result,
    required this.packet,
    required this.fromSms,
    this.nearby = false,
    this.locSource = '',
  });

  @override
  Widget build(BuildContext context) {
    final ok = result?.succeeded ?? 0;
    final bad = result?.failed ?? 0;
    final text = nearby
        ? tr('Go to help only if it is safe, and call Police (100).')
        : fromSms
            ? tr('Alert received by SMS from a nearby phone.')
            : switch (smsState) {
                _SmsState.sending => tr('Sending SMS to the emergency contacts…'),
                _SmsState.sent =>
                  '${tr('SMS sent to')} $ok ${tr('emergency contact(s).')}',
                _SmsState.failed => ok + bad == 0
                    ? tr('No emergency contact number available to SMS.')
                    : '${tr('SMS sent to')} $ok; $bad ${tr('failed')}.',
              };
    final locLine = packet.gpsFixValid
        ? '${tr('Location:')} ${packet.latitude.toStringAsFixed(6)}, '
            '${packet.longitude.toStringAsFixed(6)}'
        : '${tr('Location:')} ${tr('acquiring GPS fix…')}';
    final srcLine = locSource == 'phone'
        ? tr('Location source: your phone')
        : locSource == 'device'
            ? tr('Location source: your SOS device')
            : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (smsState == _SmsState.sending)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                Icon(
                  smsState == _SmsState.failed ? Icons.error : Icons.check_circle,
                  color: Colors.white,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            locLine,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (srcLine.isNotEmpty)
            Text(
              srcLine,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _CallingCountdown extends StatelessWidget {
  final int countdown;
  final VoidCallback onCancel;
  const _CallingCountdown({required this.countdown, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${tr('Calling Police (100) in')} $countdown…',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white70),
          ),
          child: Text(tr('Cancel call')),
        ),
      ],
    );
  }
}

/// Shown the very first time an SOS fires — asks the auto-call
/// question once; the answer is then remembered forever (see
/// StorageService.getAutoCallPolice/setAutoCallPolice) and this
/// prompt never shows again unless cleared from Settings.
class _AutoCallPrompt extends StatelessWidget {
  final void Function(bool enable) onAnswer;
  const _AutoCallPrompt({required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          tr('Call Police (100) now?'),
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          tr('Tap Yes to call Police now.'),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => onAnswer(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.emergencyRed,
              ),
              icon: const Icon(Icons.call),
              label: Text(tr('Yes, call')),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => onAnswer(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: Text(tr('No')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown on every SOS once the user has already answered "No" to
/// auto-call — a one-tap manual call is still offered, it just never
/// dials on its own.
class _ManualCallButton extends StatelessWidget {
  final VoidCallback onCallNow;
  const _ManualCallButton({required this.onCallNow});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onCallNow,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.emergencyRed,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      icon: const Icon(Icons.call),
      label: Text(tr('Call Police (100) now')),
    );
  }
}