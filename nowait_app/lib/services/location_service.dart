import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
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

  // All Google API calls are proxied through the backend so the API key
  // never needs to be enabled for direct mobile client access.
  static String get _backendBase => AppConfig.baseUrl;

  /// Requests permission and fetches the device's current GPS location.
  /// Returns null if permission is denied or GPS unavailable.
  Future<LocationResult?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
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
      final address = await getAddressFromCoords(position.latitude, position.longitude);
      return LocationResult(
        lat: position.latitude,
        lng: position.longitude,
        address: address ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocodes lat/lng to a human-readable address via the backend proxy.
  Future<String?> getAddressFromCoords(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_backendBase/maps/geocode')
          .replace(queryParameters: {'latlng': '$lat,$lng'});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          return results.first['formatted_address'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns Places Autocomplete suggestions for [query] via the backend proxy.
  /// Debouncing is the caller's responsibility.
  Future<List<PlacePrediction>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final uri = Uri.parse('$_backendBase/maps/places/autocomplete')
          .replace(queryParameters: {
        'input': trimmed,
        'types': 'establishment|geocode',
        'components': 'country:in',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final predictions = data['predictions'] as List? ?? [];
        return predictions.map((p) {
          final fmt = (p['structured_formatting'] as Map?) ?? {};
          return PlacePrediction(
            placeId: p['place_id'] as String? ?? '',
            description: p['description'] as String? ?? '',
            mainText: fmt['main_text'] as String? ?? '',
            secondaryText: fmt['secondary_text'] as String? ?? '',
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Fetches lat/lng and formatted address for a Place ID via the backend proxy.
  Future<LocationResult?> getPlaceDetails(String placeId) async {
    try {
      final uri = Uri.parse('$_backendBase/maps/place/details')
          .replace(queryParameters: {
        'place_id': placeId,
        'fields': 'geometry,formatted_address',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final result = data['result'] as Map?;
        if (result != null) {
          final loc = (result['geometry'] as Map)['location'] as Map;
          return LocationResult(
            lat: (loc['lat'] as num).toDouble(),
            lng: (loc['lng'] as num).toDouble(),
            address: result['formatted_address'] as String? ?? '',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Opens navigation to [lat],[lng] in the best available map app.
  ///
  /// Android priority:
  ///   1. google.navigation: — Google Maps turn-by-turn (declared in AndroidManifest queries)
  ///   2. geo: — default map app intent
  ///   3. https://maps.google.com — browser fallback
  ///
  /// iOS priority:
  ///   1. comgooglemaps:// — Google Maps app (declared in LSApplicationQueriesSchemes)
  ///   2. maps:// — Apple Maps
  ///   3. https://maps.apple.com — Apple Maps web fallback
  Future<bool> launchDirections(double lat, double lng) async {
    if (kIsWeb) {
      return _tryLaunch(Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ));
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // 1. Google Maps app on iOS
      final googleMapsUri = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
      );
      if (await _tryLaunch(googleMapsUri)) return true;

      // 2. Apple Maps
      final appleMapsUri = Uri.parse('maps://?daddr=$lat,$lng');
      if (await _tryLaunch(appleMapsUri)) return true;

      // 3. Apple Maps web (always works on iOS Safari)
      return _tryLaunch(Uri.parse(
        'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d',
      ));
    }

    // Android
    // 1. Google Maps turn-by-turn navigation
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await _tryLaunch(navUri)) return true;

    // 2. geo: URI — any installed map app
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(Shop)');
    if (await _tryLaunch(geoUri)) return true;

    // 3. Google Maps web
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
}
