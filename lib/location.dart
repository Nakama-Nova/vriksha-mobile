import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// The phone's position as the server wants it for a check-in or check-out
/// (POST /attendance/me/check-in and /check-out). The server picks the plant unit from it.
class GeoFix {
  const GeoFix(this.latitude, this.longitude, this.accuracyM);
  final double latitude;
  final double longitude;
  final double accuracyM;

  Map<String, double> toJson() => {'latitude': latitude, 'longitude': longitude, 'accuracy_m': accuracyM};
}

/// Why a position could not be had, in words for the person. [fix] says what would help.
class LocationProblem implements Exception {
  const LocationProblem(this.message, {this.fix = LocationFix.none});
  final String message;
  final LocationFix fix;
  @override
  String toString() => message;
}

enum LocationFix { none, locationSettings, appSettings }

/// Where the position comes from; replaced in tests.
typedef PositionSource = Future<GeoFix> Function();

/// Ask for permission if needed, then read one good position. Throws [LocationProblem].
Future<GeoFix> currentFix() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationProblem('Location is switched off on this phone. Turn it on, then try again.',
        fix: LocationFix.locationSettings);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied) {
    throw const LocationProblem('Allow location for this app, so your position can be sent with your check-in.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationProblem('Location is blocked for this app. Allow it in the app settings, then try again.',
        fix: LocationFix.appSettings);
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 25)),
    );
    if (p.isMocked) {
      throw const LocationProblem('A fake location is switched on. Turn it off to check in.');
    }
    return GeoFix(p.latitude, p.longitude, p.accuracy);
  } on TimeoutException {
    throw const LocationProblem('The phone could not find its position. Go outside or near a window and try again.');
  }
}

/// Open the screen that fixes a [LocationProblem].
Future<void> openFix(LocationFix fix) async {
  if (fix == LocationFix.locationSettings) await Geolocator.openLocationSettings();
  if (fix == LocationFix.appSettings) await Geolocator.openAppSettings();
}
