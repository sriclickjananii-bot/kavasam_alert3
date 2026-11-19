# Kavasam Alert 3 - what changed

1. About / How to Use: Close button works (dialogs use their own context).
2. Share with Friends: sends the app's APK file (Kavasam_Alert.apk) via the share sheet.
3. One language for the whole app (English / Tamil): toggle on Emergency tab and Settings change everything.
4. Your own SOS: screen + notification say "YOUR SOS IS TRIGGERED"; contacts get "<name> is in danger".
5. Live map: street/satellite, accuracy circle, recent path, speed, altitude, coordinates, distance, zoom buttons.
6. Location sharing names: each user sees the name THEY saved (invite "for" name, "Save this person as", rename).
7. SOS location: paired device location if it was heard, otherwise this phone's own location.
8. "Display over other apps" / battery prompt asked once only (switch kept in Settings).
9. SOS from the phone: camera records 12 s of video and saves it to the gallery (Movies/KavasamAlert).
10. Nearby alert escalation: 0-5 km at once; 5-10 km only if (<3 phones answered in 60 s) or (5 min and no
    emergency contact responded) and NO emergency contact has responded.
    Emergency contact answers with "I am responding" or by calling Police on the alert screen.
11. Settings > choose which SIM sends the automatic SMS.
12. App label: "Kavasam Alert 3".

## IMPORTANT: publish the new Firestore rules (needed for item 10)
    cd backend
    firebase deploy --only firestore:rules
(Without this, escalation still works but treats every alert as "nobody answered".)

## Build
    flutter clean
    flutter pub get        # downloads the new `camera` package
    flutter run --release
Copy google-services.json into android\app\ first.
For a universal APK to share with friends: flutter build apk --release
