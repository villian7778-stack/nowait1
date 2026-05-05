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

  static String get _base => AppConfig.baseUrl;

  // ── GPS ────────────────────────────────────────────────────────────────────

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

  // ── Reverse geocode ─────────────────────────────────────────────────────────

  /// Returns a human-readable address via the backend → Google Geocoding proxy.
  Future<String?> getAddressFromCoords(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_base/maps/geocode')
          .replace(queryParameters: {'latlng': '$lat,$lng'});
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Google Geocoding returns status + results[].formatted_address
        if (data['status'] == 'OK') {
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            return results.first['formatted_address'] as String?;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Places Autocomplete ─────────────────────────────────────────────────────

  /// Returns up to 5 place predictions via the backend → Google Places proxy.
  /// Caller is responsible for debouncing.
  Future<List<PlacePrediction>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final uri = Uri.parse('$_base/maps/places/autocomplete')
          .replace(queryParameters: {
        'input': trimmed,
        // 'geocode' returns cities, regions and addresses; no pipe needed.
        'types': 'geocode',
        'components': 'country:in',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Surface a useful exception when the key is wrong / quota exceeded.
        final status = data['status'] as String? ?? '';
        if (status != 'OK' && status != 'ZERO_RESULTS') {
          throw Exception('Places API: $status');
        }
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

  // ── Place Details ───────────────────────────────────────────────────────────

  /// Resolves a Google place_id to lat/lng + address via the backend proxy.
  Future<LocationResult?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;
    try {
      final uri =
          Uri.parse('$_base/maps/place/details').replace(queryParameters: {
        'place_id': placeId,
        'fields': 'geometry,formatted_address',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status != 'OK') return null;
        final result = data['result'] as Map?;
        if (result != null) {
          final loc =
              (result['geometry'] as Map)['location'] as Map;
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

  // ── Directions ──────────────────────────────────────────────────────────────

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
}
