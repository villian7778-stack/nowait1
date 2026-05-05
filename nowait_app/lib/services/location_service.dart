import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Nominatim (OpenStreetMap) is used for search and reverse-geocoding so the
// feature works without a Google Maps API key on the backend.
// Terms: max 1 req/s, must send a descriptive User-Agent.
const _kNominatim = 'https://nominatim.openstreetmap.org';
const _kUserAgent = 'NowaitApp/1.0 (contact@nowait.app)';

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
  // Populated by Nominatim search so no second API call is needed on tap.
  final double? lat;
  final double? lng;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
    this.lat,
    this.lng,
  });
}

class LocationResult {
  final double lat;
  final double lng;
  final String address;

  const LocationResult({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  // ── GPS ────────────────────────────────────────────────────────────────────

  /// Requests permission and fetches the device's current GPS location.
  /// Returns null if permission is denied or GPS unavailable.
  Future<LocationResult?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final address =
          await getAddressFromCoords(position.latitude, position.longitude);
      return LocationResult(
        lat: position.latitude,
        lng: position.longitude,
        address: address ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Nominatim: reverse geocode ──────────────────────────────────────────────

  /// Returns a human-readable address for [lat]/[lng] via Nominatim.
  Future<String?> getAddressFromCoords(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_kNominatim/reverse').replace(queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'json',
        'zoom': '16', // street-level detail
      });
      final response = await http
          .get(uri, headers: {'User-Agent': _kUserAgent}).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          return _shortenAddress(displayName);
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Nominatim: forward search ───────────────────────────────────────────────

  /// Returns up to 5 place predictions for [query] via Nominatim.
  /// Each result already carries lat/lng so no second round-trip is needed.
  Future<List<PlacePrediction>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final uri = Uri.parse('$_kNominatim/search').replace(queryParameters: {
        'q': trimmed,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'in',
        'addressdetails': '0',
        'dedupe': '1',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': _kUserAgent}).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list.map((p) {
          final displayName = (p['display_name'] as String?) ?? '';
          final parts = displayName.split(', ');
          final mainText = parts.isNotEmpty ? parts.first : displayName;
          final secondaryText =
              parts.length > 1 ? parts.skip(1).join(', ') : '';
          return PlacePrediction(
            placeId: p['place_id']?.toString() ?? '',
            description: displayName,
            mainText: mainText,
            secondaryText: secondaryText,
            lat: double.tryParse(p['lat'] as String? ?? ''),
            lng: double.tryParse(p['lon'] as String? ?? ''),
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// No-op for Nominatim predictions (lat/lng already in PlacePrediction).
  /// Kept for compatibility if Google-style placeIds are ever used.
  Future<LocationResult?> getPlaceDetails(String placeId) async {
    return null;
  }

  // ── Directions ──────────────────────────────────────────────────────────────

  /// Opens navigation to [lat],[lng] in the best available map app.
  ///
  /// Android priority:
  ///   1. google.navigation: — Google Maps turn-by-turn
  ///   2. geo: — default map app
  ///   3. https://maps.google.com — browser fallback
  ///
  /// iOS priority:
  ///   1. comgooglemaps:// — Google Maps app
  ///   2. maps:// — Apple Maps
  ///   3. https://maps.apple.com — web fallback
  Future<bool> launchDirections(double lat, double lng) async {
    if (kIsWeb) {
      return _tryLaunch(Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ));
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final googleMapsUri = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
      );
      if (await _tryLaunch(googleMapsUri)) return true;

      final appleMapsUri = Uri.parse('maps://?daddr=$lat,$lng');
      if (await _tryLaunch(appleMapsUri)) return true;

      return _tryLaunch(Uri.parse(
        'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d',
      ));
    }

    // Android
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await _tryLaunch(navUri)) return true;

    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(Shop)');
    if (await _tryLaunch(geoUri)) return true;

    return _tryLaunch(Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    ));
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  // Nominatim returns very long comma-separated strings; keep a readable slice.
  String _shortenAddress(String full) {
    final parts = full.split(', ');
    // Drop the last part if it's just "India" and keep up to 5 segments.
    final filtered = parts.where((p) => p != 'India').take(5).toList();
    return filtered.join(', ');
  }
}
