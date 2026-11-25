# Kavasam Alert - v4 changes

1. First launch: after the permission screen the app asks you to REGISTER YOUR LOCATION
   (current location or tap on the map, label Home / College / Work / Other). It is saved on the phone.
   Existing users see this screen once on the next launch. "Skip for now" is allowed.
2. Safe Zone card (top of the Location Sharing tab) and side menu > "My Safe Location":
   change / remove the place, switch protection on or off.
3. SECOND LAYER: the background service now also checks every nearby SOS against the REGISTERED
   location. If an SOS is raised within 5 km (10 km after the normal escalation rules) of that place,
   this phone rings the alert even when its own location (GPS) is OFF. The alert screen says
   "SOS near your registered safe location".
4. Settings icon (top right) opens Settings directly. Location Sharing tab opens even without Firebase.

Needs Firebase (google-services.json) because alerts are delivered through the cloud.
Phone needs internet (mobile data / Wi-Fi) but NOT location.
