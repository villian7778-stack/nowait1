import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// Full-screen location picker page. Push with Navigator.push; the page pops
/// with [LocationResult] when the user taps "Confirm Location", or null on back.
class LocationPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  const LocationPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  // Default center: geographic center of India
  static const _indiaCenter = LatLng(20.5937, 78.9629);
  static const _defaultZoom = 4.5;
  static const _selectedZoom = 15.0;

  GoogleMapController? _mapController;
  LatLng _center = _indiaCenter;
  String _address = '';
  bool _isGeocoding = false;
  bool _isLoadingGPS = false;
  bool _hasConfirmed = false;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<PlacePrediction> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _center = LatLng(widget.initialLat!, widget.initialLng!);
      _address = widget.initialAddress ?? '';
    }
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && mounted) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      if (mounted) setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await LocationService.instance.searchPlaces(value);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
        });
      }
    });
  }

  Future<void> _onSuggestionTap(PlacePrediction prediction) async {
    _searchFocusNode.unfocus();
    setState(() {
      _showSuggestions = false;
      _searchController.text = prediction.mainText;
      _isGeocoding = true;
      _hasConfirmed = false;
    });

    final result = await LocationService.instance.getPlaceDetails(prediction.placeId);
    if (!mounted) return;

    if (result != null) {
      final latlng = LatLng(result.lat, result.lng);
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latlng, zoom: _selectedZoom),
        ),
      );
      setState(() {
        _center = latlng;
        _address = result.address;
        _isGeocoding = false;
      });
    } else {
      setState(() => _isGeocoding = false);
      _showError('Could not load location details. Try again.');
    }
  }

  // ── GPS ─────────────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() { _isLoadingGPS = true; _hasConfirmed = false; });

    final result = await LocationService.instance.getCurrentLocation();
    if (!mounted) return;

    if (result != null) {
      final latlng = LatLng(result.lat, result.lng);
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latlng, zoom: _selectedZoom),
        ),
      );
      setState(() {
        _center = latlng;
        _address = result.address;
        _isLoadingGPS = false;
      });
    } else {
      setState(() => _isLoadingGPS = false);
      _showError('Could not get location. Check that GPS is enabled and permission is granted.');
    }
  }

  // ── Camera idle → reverse geocode ───────────────────────────────────────────

  Future<void> _onCameraIdle() async {
    if (_hasConfirmed) return;
    setState(() { _isGeocoding = true; _address = ''; });

    final addr = await LocationService.instance.getAddressFromCoords(
      _center.latitude,
      _center.longitude,
    );
    if (mounted) {
      setState(() {
        _address = addr ?? '';
        _isGeocoding = false;
      });
    }
  }

  // ── Confirm ──────────────────────────────────────────────────────────────────

  void _confirmLocation() {
    if (_address.isEmpty) {
      _showError('No address detected. Move the pin to a valid location.');
      return;
    }
    setState(() => _hasConfirmed = true);
    Navigator.of(context).pop(
      LocationResult(lat: _center.latitude, lng: _center.longitude, address: _address),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // ── Full-screen map ────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: widget.initialLat != null ? _selectedZoom : _defaultZoom,
              ),
              onMapCreated: (c) => _mapController = c,
              onCameraMove: (pos) {
                if (mounted) setState(() => _center = pos.target);
              },
              onCameraIdle: _onCameraIdle,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              // Allow the map to capture gestures inside any scroll view
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
          ),

          // ── Center pin (fixed, map moves beneath it) ───────────────────────
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Offset slightly above center to match the pin tip
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isGeocoding
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Detecting...',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  _address.isEmpty ? 'Move map to select' : _address,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        const SizedBox(height: 2),
                        // Arrow connecting bubble to pin
                        Container(
                          width: 2,
                          height: 8,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.location_pin, size: 44, color: AppColors.primary),
                ],
              ),
            ),
          ),

          // ── Top bar: back button + search ──────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      // Back button
                      _MapButton(
                        onTap: () => Navigator.pop(context, null),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Search field
                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onChanged: _onSearchChanged,
                                  decoration: InputDecoration(
                                    hintText: 'Search for a location...',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.onSurface,
                                  ),
                                  textInputAction: TextInputAction.search,
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _suggestions = [];
                                      _showSuggestions = false;
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Autocomplete suggestions dropdown
                if (_showSuggestions)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _suggestions.length.clamp(0, 5),
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: AppColors.outline.withValues(alpha: 0.2),
                          indent: 44,
                        ),
                        itemBuilder: (_, i) {
                          final s = _suggestions[i];
                          return InkWell(
                            onTap: () => _onSuggestionTap(s),
                            borderRadius: i == 0
                                ? const BorderRadius.vertical(top: Radius.circular(12))
                                : i == (_suggestions.length.clamp(0, 5) - 1)
                                    ? const BorderRadius.vertical(
                                        bottom: Radius.circular(12))
                                    : BorderRadius.zero,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.mainText.isNotEmpty
                                              ? s.mainText
                                              : s.description,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (s.secondaryText.isNotEmpty) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            s.secondaryText,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── GPS button (right side, middle) ───────────────────────────────
          Positioned(
            right: 12,
            bottom: 200,
            child: _MapButton(
              onTap: _isLoadingGPS ? null : _useCurrentLocation,
              child: _isLoadingGPS
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
            ),
          ),

          // ── Bottom panel: address + confirm button ─────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected Location',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            _isGeocoding
                                ? Row(
                                    children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Detecting address...',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    _address.isEmpty
                                        ? 'Move the map to select a location'
                                        : _address,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _address.isEmpty
                                          ? AppColors.onSurfaceVariant
                                          : AppColors.onSurface,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            if (_address.isNotEmpty && !_isGeocoding)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  '${_center.latitude.toStringAsFixed(6)}, '
                                  '${_center.longitude.toStringAsFixed(6)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isGeocoding
                        ? Container(
                            decoration: BoxDecoration(
                              color: AppColors.outline.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          )
                        : GestureDetector(
                            onTap: _address.isNotEmpty ? _confirmLocation : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                gradient: _address.isNotEmpty
                                    ? AppColors.primaryGradient135
                                    : null,
                                color: _address.isEmpty
                                    ? AppColors.outline.withValues(alpha: 0.2)
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 18,
                                    color: _address.isNotEmpty
                                        ? Colors.white
                                        : AppColors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Confirm Location',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _address.isNotEmpty
                                          ? Colors.white
                                          : AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small floating action button used on the map surface.
class _MapButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _MapButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Compact card shown inside the shop-creation form to display the currently
/// selected location or to prompt the user to pick one.
class LocationPreviewCard extends StatelessWidget {
  final double? lat;
  final double? lng;
  final String address;
  final VoidCallback onTap;

  const LocationPreviewCard({
    super.key,
    required this.lat,
    required this.lng,
    required this.address,
    required this.onTap,
  });

  bool get _hasLocation => lat != null && lng != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hasLocation
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hasLocation
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _hasLocation
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _hasLocation ? Icons.location_on_rounded : Icons.add_location_alt_outlined,
                size: 20,
                color: _hasLocation ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hasLocation ? 'Location Selected' : 'Set Shop Location',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _hasLocation ? AppColors.primary : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _hasLocation && address.isNotEmpty
                        ? address
                        : 'Tap to select on map — enables "Get Directions" for customers',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _hasLocation ? Icons.edit_location_alt_outlined : Icons.chevron_right_rounded,
              size: 18,
              color: _hasLocation ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
