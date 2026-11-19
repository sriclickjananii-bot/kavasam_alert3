import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_lang.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// App bar: dark gradient panel with white title, like the reference app.
// ---------------------------------------------------------------------------
PreferredSizeWidget kaavalAppBar({
  required Widget title,
  Widget? leading,
  List<Widget>? actions,
  double toolbarHeight = kToolbarHeight,
  bool automaticallyImplyLeading = true,
}) {
  return AppBar(
    toolbarHeight: toolbarHeight,
    centerTitle: true,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    title: title,
    actions: actions,
    elevation: 4,
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    flexibleSpace: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111111), Color(0xFF2B2B2B), Color(0xFF454545)],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Light grey page background with soft diagonal white streaks.
// ---------------------------------------------------------------------------
class KaavalBackground extends StatelessWidget {
  final Widget child;
  const KaavalBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _StreakPainter())),
        child,
      ],
    );
  }
}

class _StreakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAFAFA), Color(0xFFE9E9E9)],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    void streak(double x1, double x2, double alpha, {bool dark = false}) {
      final path = Path()
        ..moveTo(x1, 0)
        ..lineTo(x2, 0)
        ..lineTo(x2 - w * 0.9, h)
        ..lineTo(x1 - w * 0.9, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = (dark ? Colors.black : Colors.white).withOpacity(alpha),
      );
    }

    streak(w * 1.00, w * 1.25, 0.55);
    streak(w * 1.35, w * 1.50, 0.35);
    streak(w * 0.75, w * 0.88, 0.30);
    streak(w * 1.62, w * 1.80, 0.20, dark: true);
    streak(w * 0.55, w * 0.62, 0.12, dark: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// ENG | தமிழ் pill toggle (persists to the same stored language setting
// that Settings uses).
// ---------------------------------------------------------------------------
class KaavalLangToggle extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  const KaavalLangToggle({super.key, this.onChanged});

  Future<void> _set(String l) async {
    await AppLang.set(l); // changes the language everywhere
    onChanged?.call(l);
  }

  @override
  Widget build(BuildContext context) {
    const selected = Color(0xFF8C4A5F);
    const idle = Color(0xFFA8A8A8);
    final current = AppLang.code;
    Widget half(String label, String code, BorderRadius r, {bool tamil = false}) {
      final on = current == code;
      return Expanded(
        child: GestureDetector(
          onTap: () => _set(code),
          child: Container(
            alignment: tamil ? Alignment.centerRight : Alignment.centerLeft,
            padding: EdgeInsets.only(left: tamil ? 0 : 14, right: tamil ? 10 : 0),
            decoration: BoxDecoration(color: on ? selected : idle, borderRadius: r),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 150,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              half('ENG', 'en',
                  const BorderRadius.horizontal(left: Radius.circular(12))),
              half('தமிழ்', 'ta',
                  const BorderRadius.horizontal(right: Radius.circular(12)),
                  tamil: true),
            ],
          ),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Text('OR',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom news ticker: red RSS square + scrolling white text on dark grey.
// ---------------------------------------------------------------------------
class KaavalTicker extends StatefulWidget {
  final String message;
  const KaavalTicker({super.key, this.message = 'Welcome to Kavasam Alert!!!'});

  @override
  State<KaavalTicker> createState() => _KaavalTickerState();
}

class _KaavalTickerState extends State<KaavalTicker> {
  final _c = ScrollController();
  bool _run = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  Future<void> _loop() async {
    while (_run && mounted) {
      if (!_c.hasClients || _c.position.maxScrollExtent <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      _c.jumpTo(0);
      final max = _c.position.maxScrollExtent;
      try {
        await _c.animateTo(
          max,
          duration: Duration(milliseconds: (max * 16).round()),
          curve: Curves.linear,
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _run = false;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = List.filled(40, '${widget.message}      ').join();
    return SafeArea(
      top: false,
      child: Container(
        height: 40,
        color: AppColors.tickerGrey,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              color: AppColors.tickerRed,
              child: const Icon(Icons.rss_feed, color: Colors.white, size: 26),
            ),
            Expanded(
              child: ListView(
                controller: _c,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        text,
                        softWrap: false,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grey 3D tile (Other Services grid).
// ---------------------------------------------------------------------------
class KaavalGreyTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const KaavalGreyTile({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 4, 8, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1B1B), Color(0xFF555555), Color(0xFF2A2A2A)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFD8D8D8), Color(0xFFB4B4B4), Color(0xFF9C9C9C)],
            ),
          ),
          child: Text(
            tr(label),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.tileText,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Green-bordered info card, optionally with a "View more" expander.
// ---------------------------------------------------------------------------
class KaavalGreenCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const KaavalGreenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        border: Border.all(color: AppColors.cardGreen, width: 2.2),
      ),
      child: child,
    );
  }
}

class KaavalInstructionCard extends StatefulWidget {
  final String title;
  final List<String> steps;
  final int visibleCount;
  const KaavalInstructionCard({
    super.key,
    required this.title,
    required this.steps,
    this.visibleCount = 3,
  });

  @override
  State<KaavalInstructionCard> createState() => _KaavalInstructionCardState();
}

class _KaavalInstructionCardState extends State<KaavalInstructionCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final shown =
        _open ? widget.steps : widget.steps.take(widget.visibleCount).toList();
    final canExpand = widget.steps.length > widget.visibleCount;
    return KaavalGreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(widget.title),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('${i + 1}. ${tr(shown[i])}',
                  style: const TextStyle(fontSize: 14, height: 1.25)),
            ),
          if (canExpand)
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Text(_open ? tr('View less') : tr('View more'),
                        style: const TextStyle(
                            color: Color(0xFFA0103F), fontSize: 15)),
                    const SizedBox(width: 14),
                    Icon(_open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: AppColors.tabMaroon, size: 30),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Big italic maroon heading ("DIAL 112 / 100 / 101" style).
// ---------------------------------------------------------------------------
class KaavalHeading extends StatelessWidget {
  final String text;
  final double size;
  const KaavalHeading(this.text, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Text(
      tr(text),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        color: AppColors.headingMaroon,
        letterSpacing: -0.5,
        shadows: const [Shadow(color: Colors.black26, offset: Offset(1, 2), blurRadius: 2)],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ON / OFF pill button used on the Settings screen.
// ---------------------------------------------------------------------------
class KaavalOnOffButton extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const KaavalOnOffButton({super.key, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: Container(
        width: 160,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFD3D3D3),
          border: Border(
            bottom: BorderSide(
              color: on ? const Color(0xFF2E9E3E) : const Color(0xFFE53935),
              width: 2.5,
            ),
          ),
        ),
        child: Text(on ? tr('ON') : tr('OFF'),
            style: const TextStyle(fontSize: 16, color: Colors.black87)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small illustrated phone + map pin (Location Sharing header).
// ---------------------------------------------------------------------------
class KaavalMapIllustration extends StatelessWidget {
  const KaavalMapIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 140,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0xFFDCEBFA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(70),
                  topRight: Radius.circular(50),
                  bottomLeft: Radius.circular(60),
                  bottomRight: Radius.circular(70),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.12,
            child: Container(
              width: 62,
              height: 118,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FB),
                border: Border.all(color: const Color(0xFF16336B), width: 3.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: CustomPaint(painter: _MiniMapPainter()),
            ),
          ),
          const Positioned(
            top: 4,
            child: Icon(Icons.location_on, color: Color(0xFFE53935), size: 56),
          ),
        ],
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF9DB7D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final path = Path()
      ..moveTo(size.width * 0.2, size.height)
      ..lineTo(size.width * 0.35, size.height * 0.6)
      ..lineTo(size.width * 0.8, size.height * 0.5)
      ..moveTo(size.width * 0.5, size.height * 0.55)
      ..lineTo(size.width * 0.55, size.height * 0.25);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Drawer header illustration (sun disc + road + shield).
// ---------------------------------------------------------------------------
class KaavalDrawerIllustration extends StatelessWidget {
  const KaavalDrawerIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(double.infinity, 240), painter: _DrawerPainter()),
          Container(
            width: 120,
            height: 120,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.shield, size: 130, color: AppColors.maroon),
                Icon(Icons.notifications_active,
                    size: 52, color: Colors.white.withOpacity(0.95)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w / 2, h * 0.48), math.min(w, h) * 0.5,
        Paint()..color = const Color(0xFFE2B26B));
    final road = Path()
      ..moveTo(w * 0.04, h)
      ..lineTo(w * 0.34, h * 0.74)
      ..lineTo(w * 0.66, h * 0.74)
      ..lineTo(w * 0.96, h)
      ..close();
    canvas.drawPath(road, Paint()..color = const Color(0xFF494B5E));
    final line = Path()
      ..moveTo(w * 0.47, h)
      ..lineTo(w * 0.495, h * 0.78)
      ..lineTo(w * 0.505, h * 0.78)
      ..lineTo(w * 0.53, h)
      ..close();
    canvas.drawPath(line, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Shared dialogs (About / How to use / share).
// The Close button uses the DIALOG's own context (dctx). It used to use the
// context of the screen that opened the dialog (e.g. the side menu, which is
// already gone), so the dialog could not be closed.
// ---------------------------------------------------------------------------
Future<void> showAboutKavasam(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(tr('About Kavasam Alert')),
      content: SingleChildScrollView(
        child: Text(
          tr('Kavasam Alert is an independent personal-safety companion '
              'app for a DIY SOS wearable. It is not affiliated with, '
              'endorsed by, or operated by any police department.\n\n'
              'When triggered \u2014 by the device button or the in-app '
              'EMERGENCY button \u2014 it automatically sends a silent SMS '
              'with your live location to your saved '
              'emergency contacts, shows a full-screen alert with a '
              'siren, records a short video from your phone camera (when triggered from the phone), and can auto-call Police for you if you\'ve turned '
              'that on. This does not guarantee a response from Police; '
              'for anything urgent, also place a direct call yourself '
              'from the Voice/Mobile tab.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: Text(tr('Close')),
        ),
      ],
    ),
  );
}

Future<void> showHowToUse(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(tr('How to Use')),
      content: SingleChildScrollView(
        child: Text(
          tr('1. Add your emergency contacts (Other Services > Emergency Contacts).\n'
              '2. Optionally pair your SOS device (Other Services > Pair SOS Device).\n'
              '3. In an emergency press the red EMERGENCY button, or the button on your device.\n'
              '4. Your contacts get an SMS with your live location and you can call Police (100).\n'
              '5. Use Location Sharing to let family follow you live.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: Text(tr('Close')),
        ),
      ],
    ),
  );
}

/// Sends the app itself (the installed APK file) through the Android share
/// sheet - WhatsApp, Bluetooth, Nearby Share, Drive, etc. If that is not
/// possible it falls back to a plain WhatsApp text message.
Future<void> shareAppWithFriends() async {
  final text = tr('I use Kavasam Alert, a personal safety app with SOS alerts and '
      'live location sharing. Install it from the attached file.');
  try {
    const ch = MethodChannel('com.example.kavasam_alert/files');
    final ok = await ch.invokeMethod<bool>('shareApk', {
      'text': text,
      'title': tr('Share Kavasam Alert'),
    });
    if (ok == true) return;
  } catch (_) {}
  await launchUrl(
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
    mode: LaunchMode.externalApplication,
  );
}
