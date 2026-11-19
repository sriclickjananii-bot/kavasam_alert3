# Kavasam Alert

Same app and UI as before (renamed). New behaviour:

1. Victim presses BOOT on the ESP32-C3 trigger (`kavasam_trigger.ino`).
2. The device broadcasts a BLE SOS packet containing its GPS location and the
   victim's emergency contact numbers (set `EMERGENCY_1` / `EMERGENCY_2` in the sketch).
3. Every nearby phone with this app (background service `BleWatchService`, works with
   the screen off / app closed) instantly:
   - plays a looping alarm at max alarm volume,
   - shows a full-screen red emergency alert over the lock screen / other apps,
   - silently sends an SMS (location + map link) to the victim's emergency numbers from the packet,
   - asks "Call Police (100) now?" - tap Yes and the call is placed directly.

SMS to 100 is not possible, so Police is reached by the call only.

## First run
```
flutter clean
flutter pub get
flutter run --release
```
Open the app once and allow: Bluetooth, Location, Notifications, SMS, Phone,
"Display over other apps", and "Ignore battery optimisation". Also allow
"Full-screen notifications" for the app in Android settings (Android 14+).

## v2: nearest-people alert, BLE relay, parent live map
See **FIREBASE_SETUP.md** (free Spark plan, no billing). Firestore rules are in `backend/`.

## UI refresh (Kaaval-style)
Only the presentation layer changed; services, native Android code, SMS / BLE /
call / Firebase logic and the SOS alert flow are untouched.

- `lib/widgets/kaaval_widgets.dart` – shared look: gradient app bar, striped
  background, ENG|தமிழ் pill, scrolling ticker, grey 3D tiles, green info cards.
- `assets/images/sos_button.png` – the red EMERGENCY button used on the
  Emergency tab (tap = same manual SOS trigger as before).
- First launch shows a "Permission required" explainer once, then Home.
- This app is NOT an official police app. Do not publish it using a
  government emblem without written permission from the owner of that emblem.
