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

  static String get _apiKey => AppConfig.googleMapsApiKey;
  static const _geocodeBase = 'maps.googleapis.com';
  static const _placesBase = 'maps.googleapis.com';

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

  /// Reverse geocodes lat/lng to a human-readable address via Geocoding API.
  Future<String?> getAddressFromCoords(double lat, double lng) async {
    try {
      final uri = Uri.https(_geocodeBase, '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'key': _apiKey,
      });
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

  /// Returns Places Autocomplete suggestions for [query].
  /// Debouncing is the caller's responsibility.
  Future<List<PlacePrediction>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final uri = Uri.https(_placesBase, '/maps/api/place/autocomplete/json', {
        'input': trimmed,
        'key': _apiKey,
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

  /// Fetches lat/lng and formatted address for a Place ID.
  Future<LocationResult?> getPlaceDetails(String placeId) async {
    try {
      final uri = Uri.https(_placesBase, '/maps/api/place/details/json', {
        'place_id': placeId,
        'fields': 'geometry,formatted_address',
        'key': _apiKey,
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

  /// Opens Google Maps navigation to [lat],[lng] in the device's map app.
  Future<bool> launchDirections(double lat, double lng) async {
    // Android: uses Google Maps intent; iOS: same URL works or falls back to Apple Maps
    final gMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    try {
      if (await canLaunchUrl(gMapsUri)) {
        await launchUrl(gMapsUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}

    // Fallback: geo URI (works on most Android devices)
    if (!kIsWeb) {
      final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      try {
        if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
