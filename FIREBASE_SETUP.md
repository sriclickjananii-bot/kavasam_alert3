# Kavasam Alert — FREE Firebase setup (Spark plan, no card, no billing)

No Cloud Functions and no paid plan. Everything runs on Firestore + Anonymous Auth, which are free on the Spark plan
(limits: 50,000 reads/day, 20,000 writes/day, 1 GiB) — far more than a prototype needs.

## How it works
1. **Nearest people:** the phone that hears the device over BLE writes ONE document to Firestore `alerts`.
   Every opted-in phone has a background listener on recent alerts and checks its own distance locally.
   The allowed radius grows with the alert's age: 0-1 min = 1 km, then 2 km, 5 km, 10 km (one step per minute),
   so the closest people are alarmed first. Phone positions never leave the phone.
2. **BLE relay:** every phone that gets the SOS re-broadcasts it over BLE (3 hops) — works with NO internet.
3. **Parents:** always-share toggle + one-time invite code -> live map.

## Part A — Firebase console (5 minutes, no payment)
1. https://console.firebase.google.com -> **Add project**. Stay on the free **Spark** plan; do NOT click Upgrade.
2. **Build -> Firestore Database -> Create database** -> **Production mode** -> location **asia-south1 (Mumbai)**.
3. **Build -> Authentication -> Get started -> Sign-in method -> Anonymous -> Enable.**
4. **Firestore -> Rules tab:** delete everything, paste the full contents of `backend/firestore.rules`, click **Publish**.
   (No CLI needed. Optional CLI route: `npm i -g firebase-tools`, `firebase login`, set the project id in
   `backend/.firebaserc`, then `cd backend && firebase deploy --only firestore:rules`.)
5. **Project settings (gear) -> Your apps -> Android icon.** Package name: `com.example.kavasam_alert`.
   Download **google-services.json** and put it in `android/app/google-services.json`.

## Part B — Build the app
```
flutter clean
flutter pub get
flutter run --release
```
(Nothing to edit in the code — the backend URL step from the earlier version is gone.)

## Part C — Test with 2-3 phones
1. Every phone: open the app, allow Bluetooth, Location (**"Allow all the time"**), Notifications, SMS, Phone,
   "Display over other apps", battery **Unrestricted**. Then Other Services -> Profile & Language ->
   turn **"Help people near me" ON**.
2. Phone A near the ESP32 device, Phone B a few hundred metres away with internet. Press the device button.
   Phone A alarms and Firestore -> `alerts` gets a document. Phone B alarms within seconds (if within 1 km),
   or up to a minute later if it is 1-2 km away, and so on.
3. Mesh test: turn off A's internet. Phone C within ~30 m of A but out of the device's range still alarms via BLE relay.
4. Parents: victim -> Location Sharing -> "Always share" ON -> Generate Invite Code. Parent -> Accept an Invite -> enter it.

To test distance rings quickly on one desk, temporarily change `RADII_M` in `Respondernet.kt`.

## Honest limits of the free design
- **Reliability with the screen off:** without FCM push, delivery depends on the phone keeping its internet connection
  while idle. Set battery to Unrestricted. Expect occasional delays on Doze-heavy phones (Xiaomi/Oppo/Vivo/Realme).
  The BLE relay is not affected.
- **Security:** rules stop edits/deletes and fake identities, but any app user can create an alert. Fine for a prototype.
- **Scale:** every opted-in phone reads every new alert. OK for hundreds of users. For thousands, add geohash buckets,
  or move to FCM push later (needs Blaze, or a free Cloudflare Worker sending FCM).
- Anonymous accounts vanish if app data is cleared (parents must be re-invited). Use phone login for production.
- Location sharing stops if Android force-kills the app; it resumes next time the app opens.
- Play Store needs a privacy policy and clear disclosure for background location. Prototype aid only — still call 100/112.
