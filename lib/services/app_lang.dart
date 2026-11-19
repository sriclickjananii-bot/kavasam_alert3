import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'storage_service.dart';

/// App-wide language (English / Tamil). One switch for the whole app:
/// changing it anywhere (language toggle, Settings) rebuilds every screen.
///
/// Use [tr] around any English UI text:  Text(tr('Settings'))
/// Unknown strings fall back to the English text, so nothing ever breaks.
class AppLang {
  AppLang._();

  static final ValueNotifier<String> notifier = ValueNotifier<String>('en');

  static String get code => notifier.value;
  static bool get isTa => notifier.value == 'ta';

  /// Call once at start-up (before runApp).
  static Future<void> load() async {
    notifier.value = await StorageService().getLanguage();
  }

  /// Change the language everywhere, remember it, and redraw all screens
  /// that are currently open (state of the screens is kept).
  static Future<void> set(String lang) async {
    if (lang != 'en' && lang != 'ta') lang = 'en';
    await StorageService().setLanguage(lang);
    if (notifier.value == lang) return;
    notifier.value = lang;
    _rebuildAll();
  }

  static void _rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

/// Translate an English UI string to the current app language.
String tr(String en) {
  if (!AppLang.isTa) return en;
  return _ta[en] ?? en;
}

const Map<String, String> _ta = {
  // ---- common
  'Close': 'மூடு',
  'View less': 'குறைவாகக் காட்டு',
  'View more': 'மேலும் காட்டு',
  'Cancel': 'ரத்து',
  'Save': 'சேமி',
  'Saved': 'சேமிக்கப்பட்டது',
  'Accept': 'ஏற்கவும்',
  'Copy': 'நகலெடு',
  'Copied': 'நகலெடுக்கப்பட்டது',
  'Remove': 'நீக்கு',
  'Name': 'பெயர்',
  'Yes, call': 'ஆம், அழை',
  'No': 'இல்லை',
  'OK': 'சரி',
  'Navigate': 'வழிகாட்டு',
  'Pair': 'இணை',
  'Proceed': 'தொடரவும்',
  'ON': 'ஆன்',
  'OFF': 'ஆஃப்',
  'Rename': 'பெயர் மாற்று',

  // ---- home / tabs / drawer
  'Kavasam Alert -\nCITIZEN SAFETY APP':
      'கவசம் அலர்ட் -\nகுடிமக்கள் பாதுகாப்பு செயலி',
  'EMERGENCY': 'அவசரம்',
  'VOICE/\nMOBILE': 'குரல்/\nமொபைல்',
  'LOCATION\nSHARING': 'இருப்பிடம்\nபகிர்வு',
  'OTHER\nSERVICES': 'பிற\nசேவைகள்',
  'Settings': 'அமைப்புகள்',
  'Emergency Contacts': 'அவசர தொடர்புகள்',
  'Edit Profile': 'சுயவிவரத்தை திருத்து',
  'Pair SOS Device': 'SOS சாதனத்தை இணை',
  'Share with Friends': 'நண்பர்களுடன் பகிர்',
  'How to Use': 'பயன்படுத்தும் முறை',
  'About App': 'செயலியைப் பற்றி',
  'Set your name': 'உங்கள் பெயரை அமைக்கவும்',
  'Share Kavasam Alert': 'கவசம் அலர்ட்டை பகிர்',
  'I use Kavasam Alert, a personal safety app with SOS alerts and live location sharing. Install it from the attached file.':
      'நான் கவசம் அலர்ட் செயலியைப் பயன்படுத்துகிறேன் - SOS எச்சரிக்கை மற்றும் நேரடி இருப்பிடப் பகிர்வு கொண்ட தனிநபர் பாதுகாப்பு செயலி. இணைக்கப்பட்ட கோப்பிலிருந்து நிறுவவும்.',

  // ---- emergency tab
  'Connecting to your SOS device…': 'உங்கள் SOS சாதனத்துடன் இணைகிறது…',
  'SOS SIGNAL RECEIVED FROM DEVICE': 'சாதனத்திலிருந்து SOS சமிக்ஞை பெறப்பட்டது',
  'Device connected — standing by': 'சாதனம் இணைக்கப்பட்டது — தயார் நிலையில்',
  'Not an official police service; no call back is guaranteed.':
      'இது அதிகாரப்பூர்வ காவல்துறை சேவை அல்ல; திரும்ப அழைப்பு உறுதியில்லை.',

  // ---- voice / mobile tab
  'DIAL 112 / 100 / 101': 'அழைக்க 112 / 100 / 101',
  'PRESS BELOW DIAL BUTTON FOR POLICE / FIRE EMERGENCY':
      'காவல் / தீயணைப்பு அவசரத்திற்கு கீழே உள்ள அழைப்பு பொத்தானை அழுத்தவும்',
  'Tap to call the National Emergency number (112)':
      'தேசிய அவசர எண்ணை (112) அழைக்கத் தட்டவும்',
  'HELPLINES': 'உதவி எண்கள்',
  'These are direct voice lines \u2014 tap to call. (An SMS alert to short-code helpline numbers is not guaranteed to be monitored; use a call for anything urgent.)':
      'இவை நேரடி குரல் எண்கள் \u2014 அழைக்கத் தட்டவும். (சுருக்க உதவி எண்களுக்கு SMS அனுப்பினால் கண்காணிக்கப்படும் என்று உறுதியில்லை; அவசரத்திற்கு அழைப்பையே பயன்படுத்தவும்.)',
  'YOUR EMERGENCY CONTACTS': 'உங்கள் அவசர தொடர்புகள்',
  'No emergency contacts added yet. Add them from Other Services > Emergency Contacts.':
      'அவசர தொடர்புகள் இன்னும் சேர்க்கப்படவில்லை. பிற சேவைகள் > அவசர தொடர்புகள் பகுதியில் சேர்க்கவும்.',
  'Police': 'காவல்துறை',
  'Women Helpline': 'பெண்கள் உதவி எண்',
  'Child Helpline': 'குழந்தைகள் உதவி எண்',
  'National Emergency (All-in-one)': 'தேசிய அவசர எண் (அனைத்தும் ஒன்றில்)',

  // ---- other services
  'MANAGE EMERGENCY\nCONTACTS': 'அவசர தொடர்புகளை\nநிர்வகி',
  'PAIR SOS\nDEVICE': 'SOS சாதனத்தை\nஇணை',
  'PROFILE &\nLANGUAGE': 'சுயவிவரம் &\nமொழி',
  'ABOUT\nKAVASAM ALERT': 'கவசம் அலர்ட்\nபற்றி',

  // ---- about / how to use
  'About Kavasam Alert': 'கவசம் அலர்ட் பற்றி',
  'Kavasam Alert is an independent personal-safety companion app for a DIY SOS wearable. It is not affiliated with, endorsed by, or operated by any police department.\n\nWhen triggered \u2014 by the device button or the in-app EMERGENCY button \u2014 it automatically sends a silent SMS with your live location to your saved emergency contacts, shows a full-screen alert with a siren, records a short video from your phone camera (when triggered from the phone), and can auto-call Police for you if you\'ve turned that on. This does not guarantee a response from Police; for anything urgent, also place a direct call yourself from the Voice/Mobile tab.':
      'கவசம் அலர்ட் என்பது DIY SOS அணிகலனுக்கான சுயாதீன தனிநபர் பாதுகாப்பு துணைச் செயலி. இது எந்த காவல்துறையுடனும் இணைந்ததோ, அங்கீகரிக்கப்பட்டதோ, இயக்கப்படுவதோ அல்ல.\n\nசாதனப் பொத்தான் அல்லது செயலியின் அவசர பொத்தான் மூலம் தூண்டப்பட்டால், உங்கள் நேரடி இருப்பிடத்துடன் சேமிக்கப்பட்ட அவசர தொடர்புகளுக்கு தானாகவே அமைதியான SMS அனுப்பும், சைரனுடன் முழுத்திரை எச்சரிக்கையைக் காட்டும், (போனிலிருந்து தூண்டினால்) கேமராவில் சிறிய வீடியோவைப் பதிவு செய்யும், நீங்கள் இயக்கியிருந்தால் காவல்துறையை தானாக அழைக்கும். இது காவல்துறையின் பதிலுக்கு உத்தரவாதம் அல்ல; அவசரத்திற்கு குரல்/மொபைல் தாவலிலிருந்து நீங்களே நேரடியாக அழைக்கவும்.',
  '1. Add your emergency contacts (Other Services > Emergency Contacts).\n2. Optionally pair your SOS device (Other Services > Pair SOS Device).\n3. In an emergency press the red EMERGENCY button, or the button on your device.\n4. Your contacts get an SMS with your live location and you can call Police (100).\n5. Use Location Sharing to let family follow you live.':
      '1. உங்கள் அவசர தொடர்புகளைச் சேர்க்கவும் (பிற சேவைகள் > அவசர தொடர்புகள்).\n2. விரும்பினால் SOS சாதனத்தை இணைக்கவும் (பிற சேவைகள் > SOS சாதனத்தை இணை).\n3. அவசரத்தில் சிவப்பு அவசர பொத்தானை அல்லது சாதனத்தில் உள்ள பொத்தானை அழுத்தவும்.\n4. உங்கள் தொடர்புகளுக்கு நேரடி இருப்பிடத்துடன் SMS செல்லும்; காவல்துறையை (100) அழைக்கலாம்.\n5. குடும்பத்தினர் உங்களை நேரடியாகப் பின்தொடர இருப்பிடப் பகிர்வைப் பயன்படுத்தவும்.',

  // ---- settings
  'Your name (shown in alert messages)': 'உங்கள் பெயர் (எச்சரிக்கை செய்திகளில் காட்டப்படும்)',
  'Call Police (100) automatically during an SOS. Asked once on your first SOS; change your answer here any time.':
      'SOS போது காவல்துறையை (100) தானாக அழைக்கவும். முதல் SOS-இல் ஒருமுறை கேட்கப்படும்; உங்கள் பதிலை இங்கே எப்போது வேண்டுமானாலும் மாற்றலாம்.',
  'Auto-call Police': 'காவல்துறையை தானாக அழை',
  'Not set yet — will be asked on next SOS': 'இன்னும் அமைக்கப்படவில்லை — அடுத்த SOS-இல் கேட்கப்படும்',
  'Help people near me: when someone close to you presses their SOS button, this phone gets an alarm even without Bluetooth range. Only your approximate position (updated every few minutes) is shared with the alert server, never your name.':
      'அருகிலுள்ளவர்களுக்கு உதவுங்கள்: உங்களுக்கு அருகில் யாரேனும் SOS பொத்தானை அழுத்தினால், புளூடூத் எல்லைக்கு வெளியிலும் இந்த போனில் அலாரம் ஒலிக்கும். உங்கள் தோராயமான இருப்பிடம் மட்டுமே (சில நிமிடங்களுக்கு ஒருமுறை) எச்சரிக்கை சேவையகத்துடன் பகிரப்படும்; பெயர் ஒருபோதும் இல்லை.',
  'Nearby Alerts': 'அருகிலுள்ள எச்சரிக்கைகள்',
  'Display over other apps': 'பிற செயலிகளின் மேல் காட்டு',
  'Lets the SOS alert appear on top of any app or the lock screen. Turn it on once.':
      'SOS எச்சரிக்கை எந்த செயலி அல்லது பூட்டுத் திரையின் மேலும் தோன்ற அனுமதிக்கும். ஒருமுறை இயக்கவும்.',
  'Preferred Language': 'விருப்ப மொழி',
  'Choose which SIM sends the emergency SMS automatically.':
      'அவசர SMS தானாக அனுப்பப்பட வேண்டிய சிம்மைத் தேர்ந்தெடுக்கவும்.',
  'Phone default': 'போனின் இயல்புநிலை',
  'SIM': 'சிம்',

  // ---- contacts screen
  'EMERGENCY CONTACTS': 'அவசர தொடர்புகள்',
  'Manage your emergency contacts': 'உங்கள் அவசர தொடர்புகளை நிர்வகிக்கவும்',
  'Emergency contacts will receive a real time alert with your location details.':
      'அவசர தொடர்புகளுக்கு உங்கள் இருப்பிட விவரங்களுடன் உடனடி எச்சரிக்கை கிடைக்கும்.',
  'Emergency Contacts saved': 'அவசர தொடர்புகள் சேமிக்கப்பட்டன',
  'Emergency contacts saved': 'அவசர தொடர்புகள் சேமிக்கப்பட்டன',
  'Emergency Contact': 'அவசர தொடர்பு',
  '(Recommended)': '(பரிந்துரைக்கப்படுகிறது)',
  'We suggest only blood relation or guardian to be added as primary contact':
      'இரத்த உறவினர் அல்லது பாதுகாவலரை மட்டுமே முதன்மை தொடர்பாகச் சேர்க்க பரிந்துரைக்கிறோம்',
  'Mobile Number': 'மொபைல் எண்',
  'Pick from contacts': 'தொடர்புகளிலிருந்து தேர்வு செய்',
  'Select Relation': 'உறவைத் தேர்ந்தெடுக்கவும்',
  'Father': 'தந்தை',
  'Mother': 'தாய்',
  'Brother': 'சகோதரன்',
  'Sister': 'சகோதரி',
  'Husband': 'கணவர்',
  'Wife': 'மனைவி',
  'Guardian': 'பாதுகாவலர்',
  'Friend': 'நண்பர்',
  'Other': 'மற்றவை',

  // ---- permission screen
  'PERMISSION REQUIRED': 'அனுமதி தேவை',
  'Sms': 'SMS',
  'SMS permission is required to send the emergency alert with your current location to your emergency contacts, and to receive SOS alerts sent by SMS from nearby phones.':
      'உங்கள் தற்போதைய இருப்பிடத்துடன் அவசர எச்சரிக்கையை அவசர தொடர்புகளுக்கு அனுப்பவும், அருகிலுள்ள போன்களிலிருந்து SMS மூலம் வரும் SOS எச்சரிக்கைகளைப் பெறவும் SMS அனுமதி தேவை.',
  'Phone': 'தொலைபேசி',
  'Phone permission is necessary to place the emergency call to Police (100) directly from the SOS alert screen.':
      'SOS எச்சரிக்கைத் திரையிலிருந்தே காவல்துறைக்கு (100) நேரடியாக அழைக்க தொலைபேசி அனுமதி அவசியம்.',
  'Location': 'இருப்பிடம்',
  'Location permission is essential to share your live location with your emergency contacts during an emergency and for live location sharing with your family.':
      'அவசரத்தில் உங்கள் நேரடி இருப்பிடத்தை அவசர தொடர்புகளுடனும், குடும்பத்துடனும் பகிர இருப்பிட அனுமதி மிகவும் அவசியம்.',
  'Bluetooth': 'புளூடூத்',
  'Bluetooth permission is required to connect to your SOS device and to listen for SOS signals from nearby devices.':
      'உங்கள் SOS சாதனத்துடன் இணைக்கவும், அருகிலுள்ள சாதனங்களின் SOS சமிக்ஞைகளைக் கேட்கவும் புளூடூத் அனுமதி தேவை.',
  'Notification': 'அறிவிப்பு',
  'Notification permission is necessary to show the emergency alert and to receive notifications during an SOS.':
      'அவசர எச்சரிக்கையைக் காட்டவும், SOS நேரத்தில் அறிவிப்புகளைப் பெறவும் அறிவிப்பு அனுமதி அவசியம்.',

  // ---- device pairing
  'Currently paired:': 'தற்போது இணைக்கப்பட்டது:',
  'Nearby devices:': 'அருகிலுள்ள சாதனங்கள்:',
  'Scanning… bring your device close and power it on.':
      'தேடுகிறது… உங்கள் சாதனத்தை அருகில் கொண்டு வந்து இயக்கவும்.',
  'Paired with': 'இணைக்கப்பட்டது:',

  // ---- location sharing tab
  'Select one of the following services to enable your family / friends to track your live location & movement':
      'உங்கள் குடும்பம் / நண்பர்கள் உங்கள் நேரடி இருப்பிடத்தையும் நகர்வையும் கண்காணிக்க கீழே உள்ள சேவைகளில் ஒன்றைத் தேர்ந்தெடுக்கவும்',
  'Invite Code': 'அழைப்புக் குறியீடு',
  'Accept Invite': 'அழைப்பை ஏற்கவும்',
  'WhatsApp': 'வாட்ஸ்அப்',
  'Invite Instructions': 'அழைப்பு வழிமுறைகள்',
  'Tap the Invite Code button above.': 'மேலே உள்ள அழைப்புக் குறியீடு பொத்தானைத் தட்டவும்.',
  'Send the code to your parent / contact (WhatsApp or Copy).':
      'குறியீட்டை உங்கள் பெற்றோர் / தொடர்புக்கு அனுப்பவும் (வாட்ஸ்அப் அல்லது நகலெடு).',
  'They open this app and tap Accept Invite.':
      'அவர்கள் இந்த செயலியைத் திறந்து அழைப்பை ஏற்கவும் என்பதைத் தட்டுவார்கள்.',
  'Each code works once, for 48 hours.': 'ஒவ்வொரு குறியீடும் 48 மணி நேரம், ஒருமுறை மட்டுமே செயல்படும்.',
  'They can see you until you remove them.': 'நீங்கள் நீக்கும் வரை அவர்கள் உங்களைப் பார்க்கலாம்.',
  'Always-On Location Sharing': 'எப்போதும் இருப்பிடப் பகிர்வு',
  'When on, your live location is continuously visible to every family member / contact who accepted your invite — not only during an SOS.':
      'இயக்கினால், உங்கள் அழைப்பை ஏற்ற ஒவ்வொரு குடும்ப உறுப்பினர் / தொடர்புக்கும் உங்கள் நேரடி இருப்பிடம் தொடர்ந்து தெரியும் — SOS நேரத்தில் மட்டுமல்ல.',
  'Always share my location': 'எப்போதும் என் இருப்பிடத்தைப் பகிர்',
  'Sharing is ON': 'பகிர்வு இயக்கத்தில் உள்ளது',
  'Sharing is OFF': 'பகிர்வு நிறுத்தப்பட்டுள்ளது',
  'Who can see me': 'என்னை யார் பார்க்கலாம்',
  'People I am watching': 'நான் கண்காணிப்பவர்கள்',
  'Nobody yet.': 'இன்னும் யாரும் இல்லை.',
  'Tap to see live location': 'நேரடி இருப்பிடத்தைக் காண தட்டவும்',
  'Stop watching': 'கண்காணிப்பதை நிறுத்து',
  'Enter Invite Code': 'அழைப்புக் குறியீட்டை உள்ளிடவும்',
  'e.g. 4F9A2C1B': 'எ.கா. 4F9A2C1B',
  'Save this person as (name on your phone)': 'இவரை இந்தப் பெயரில் சேமி (உங்கள் போனில் தெரியும் பெயர்)',
  'Your name (shown to them)': 'உங்கள் பெயர் (அவர்களுக்குக் காட்டப்படும்)',
  'Who is this invite for? (e.g. Mom)': 'இந்த அழைப்பு யாருக்கு? (எ.கா. அம்மா)',
  'Contact name (optional)': 'தொடர்பின் பெயர் (விருப்பம்)',
  'Create code': 'குறியீட்டை உருவாக்கு',
  'Location permission / GPS is required to share.':
      'பகிர இருப்பிட அனுமதி / GPS அவசியம்.',
  'Could not create invite:': 'அழைப்பை உருவாக்க முடியவில்லை:',
  'Done — you can now see': 'முடிந்தது — இப்போது நீங்கள் காணலாம்:',
  '\'s live location.': ' இன் நேரடி இருப்பிடத்தை.',
  'Rename contact': 'தொடர்பின் பெயரை மாற்று',
  'Contact': 'தொடர்பு',

  // ---- live map
  'Access removed or not available.': 'அணுகல் நீக்கப்பட்டது அல்லது கிடைக்கவில்லை.',
  'Waiting for the first location…': 'முதல் இருப்பிடத்திற்காகக் காத்திருக்கிறது…',
  'Sharing': 'பகிர்கிறது',
  'Sharing paused': 'பகிர்வு இடைநிறுத்தம்',
  'updated': 'புதுப்பிக்கப்பட்டது',
  'just now': 'இப்போது',
  'min ago': 'நிமிடம் முன்',
  'h ago': 'மணி முன்',
  'days ago': 'நாட்கள் முன்',
  'unknown': 'தெரியவில்லை',
  'Map type': 'வரைபட வகை',
  'Standard': 'சாதாரண',
  'Satellite': 'செயற்கைக்கோள்',
  'Accuracy': 'துல்லியம்',
  'Speed': 'வேகம்',
  'Distance from you': 'உங்களிடமிருந்து தூரம்',
  'Coordinates': 'ஆயத்தொலைவுகள்',
  'Last update': 'கடைசி புதுப்பிப்பு',
  'Altitude': 'உயரம்',
  'Copy coordinates': 'ஆயத்தொலைவுகளை நகலெடு',
  'Center on person': 'நபரை மையப்படுத்து',
  'Show both': 'இருவரையும் காட்டு',
  'You': 'நீங்கள்',
  'Recent path': 'சமீபத்திய பாதை',

  // ---- SOS alert screen
  'YOUR SOS IS TRIGGERED': 'உங்கள் SOS தூண்டப்பட்டது',
  'EMERGENCY ALERT': 'அவசர எச்சரிக்கை',
  'is in danger!': 'ஆபத்தில் உள்ளார்!',
  'Your emergency contacts are being alerted with your location.':
      'உங்கள் அவசர தொடர்புகளுக்கு உங்கள் இருப்பிடத்துடன் எச்சரிக்கை அனுப்பப்படுகிறது.',
  'SOS signal received from your device': 'உங்கள் சாதனத்திலிருந்து SOS சமிக்ஞை பெறப்பட்டது',
  'SOS received by SMS — someone you know needs help':
      'SMS மூலம் SOS பெறப்பட்டது — உங்களுக்குத் தெரிந்த ஒருவருக்கு உதவி தேவை',
  'You are one of the nearest people — about': 'நீங்கள் அருகிலுள்ளவர்களில் ஒருவர் — சுமார்',
  'm away': 'மீ தொலைவில்',
  'You are one of the nearest people to the victim': 'பாதிக்கப்பட்டவருக்கு மிக அருகில் உள்ளவர்களில் நீங்களும் ஒருவர்',
  'Navigate to the victim': 'பாதிக்கப்பட்டவரிடம் செல்ல வழிகாட்டு',
  'Dismiss': 'மூடு',
  'Go to help only if it is safe, and call Police (100).':
      'பாதுகாப்பாக இருந்தால் மட்டுமே உதவிக்குச் செல்லுங்கள்; காவல்துறையை (100) அழையுங்கள்.',
  'Alert received by SMS from a nearby phone.': 'அருகிலுள்ள போனிலிருந்து SMS மூலம் எச்சரிக்கை பெறப்பட்டது.',
  'Sending SMS to the emergency contacts…': 'அவசர தொடர்புகளுக்கு SMS அனுப்புகிறது…',
  'SMS sent to': 'SMS அனுப்பப்பட்டது:',
  'emergency contact(s).': 'அவசர தொடர்பு(கள்).',
  'failed': 'தோல்வி',
  'No emergency contact number available to SMS.': 'SMS அனுப்ப அவசர தொடர்பு எண் எதுவும் இல்லை.',
  'Location:': 'இருப்பிடம்:',
  'acquiring GPS fix…': 'GPS கிடைக்கப் பெறுகிறது…',
  'Location source: your phone': 'இருப்பிட மூலம்: உங்கள் போன்',
  'Location source: your SOS device': 'இருப்பிட மூலம்: உங்கள் SOS சாதனம்',
  'Calling Police (100) in': 'காவல்துறையை (100) அழைக்கிறது:',
  'Cancel call': 'அழைப்பை ரத்து செய்',
  'Call Police (100) now?': 'காவல்துறையை (100) இப்போது அழைக்கவா?',
  'Tap Yes to call Police now.': 'இப்போது அழைக்க ஆம் என்பதைத் தட்டவும்.',
  'Call Police (100) now': 'காவல்துறையை (100) இப்போது அழை',
  'I am responding': 'நான் உதவிக்கு செல்கிறேன்',
  'Thanks — your response was noted.': 'நன்றி — உங்கள் பதில் பதிவு செய்யப்பட்டது.',
  'Recording evidence video…': 'ஆதார வீடியோ பதிவாகிறது…',
  'Saving video to gallery…': 'வீடியோ கேலரியில் சேமிக்கப்படுகிறது…',
  'Video saved to your gallery': 'வீடியோ உங்கள் கேலரியில் சேமிக்கப்பட்டது',
  'Could not save the video': 'வீடியோவை சேமிக்க முடியவில்லை',
};
