import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/models.dart';
import '../../services/shop_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/searchable_picker_sheet.dart';

class EditShopScreen extends StatefulWidget {
  final ShopModel shop;

  const EditShopScreen({super.key, required this.shop});

  @override
  State<EditShopScreen> createState() => _EditShopScreenState();
}

class _EditShopScreenState extends State<EditShopScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _avgWaitController;
  late final TextEditingController _openingHoursController;
  late String _selectedCategory;
  String _selectedState = '';
  String _selectedCity = '';
  Map<String, List<String>> _stateCityData = {};
  bool _isLoading = false;
  final _l = LocaleService.instance;

  // Services editing
  late List<ServiceModel> _existingServices;
  final List<String> _deletedServiceIds = [];
  final List<Map<String, TextEditingController>> _newServices = [];

  late List<String> _existingImages;
  final List<String> _removedUrls = [];
  final List<XFile> _newImages = [];
  bool _isUploadingImages = false;

  final _categories = [
    'Salon',
    'Beauty Parlour',
    'Hospital/Clinic',
    'Garage'
  ];

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    _nameController = TextEditingController(text: widget.shop.name);
    _addressController = TextEditingController(text: widget.shop.address);
    _avgWaitController = TextEditingController(text: widget.shop.avgWaitMinutes.toString());
    _openingHoursController = TextEditingController(text: widget.shop.openingHours ?? '9:00 AM - 8:00 PM');
    _selectedCategory = _categories.contains(widget.shop.category) ? widget.shop.category : _categories.first;
    _selectedState = widget.shop.state;
    _selectedCity = widget.shop.city;
    _existingImages = List<String>.from(widget.shop.images);
    _existingServices = List<ServiceModel>.from(widget.shop.services);
    _loadStateCityData();
  }

  Future<void> _loadStateCityData() async {
    final raw = await rootBundle.loadString('assets/data/india_state_city.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _stateCityData = decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    });
  }

  int get _totalImageCount => _existingImages.length + _newImages.length;

  Future<void> _pickNewImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() {
        final remaining = 10 - _totalImageCount;
        _newImages.addAll(picked.take(remaining));
      });
    }
  }

  void _removeExistingImage(String url) {
    setState(() {
      _existingImages.remove(url);
      _removedUrls.add(url);
    });
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  void _onLocale() => setState(() {});

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _nameController.dispose();
    _addressController.dispose();
    _avgWaitController.dispose();
    _openingHoursController.dispose();
    for (final s in _newServices) {
      s['name']?.dispose();
      s['price']?.dispose();
      s['duration']?.dispose();
    }
    super.dispose();
  }

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty &&
      _selectedState.isNotEmpty &&
      _selectedCity.isNotEmpty;

  bool get _hasChanges =>
      _nameController.text.trim() != widget.shop.name ||
      _selectedCategory != widget.shop.category ||
      _addressController.text.trim() != widget.shop.address ||
      _selectedState != widget.shop.state ||
      _selectedCity != widget.shop.city ||
      (int.tryParse(_avgWaitController.text) ?? widget.shop.avgWaitMinutes) !=
          widget.shop.avgWaitMinutes ||
      _openingHoursController.text.trim() !=
          (widget.shop.openingHours ?? '9:00 AM - 8:00 PM');

  bool get _hasImageChanges => _removedUrls.isNotEmpty || _newImages.isNotEmpty;

  bool get _hasServiceChanges =>
      _deletedServiceIds.isNotEmpty ||
      _newServices.any((s) => s['name']!.text.trim().isNotEmpty);

  void _addNewService() {
    setState(() {
      _newServices.add({
        'name': TextEditingController(),
        'price': TextEditingController(),
        'duration': TextEditingController(text: '20'),
      });
    });
  }

  void _removeNewService(int index) {
    setState(() {
      _newServices[index]['name']?.dispose();
      _newServices[index]['price']?.dispose();
      _newServices[index]['duration']?.dispose();
      _newServices.removeAt(index);
    });
  }

  void _markDeleteExistingService(String id) {
    setState(() {
      _existingServices.removeWhere((s) => s.id == id);
      _deletedServiceIds.add(id);
    });
  }

  Future<void> _save() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }
    if (!_hasChanges && !_hasImageChanges && !_hasServiceChanges) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Delete removed images
      if (_removedUrls.isNotEmpty) {
        setState(() => _isUploadingImages = true);
        for (final url in _removedUrls) {
          try {
            await ShopService.instance.deleteImage(widget.shop.id, url);
          } catch (_) {}
        }
      }

      // Upload new images
      if (_newImages.isNotEmpty) {
        setState(() => _isUploadingImages = true);
        for (final img in _newImages) {
          try {
            await ShopService.instance.uploadImage(widget.shop.id, img);
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _isUploadingImages = false);

      // Delete removed services
      for (final id in _deletedServiceIds) {
        try { await ShopService.instance.deleteService(id); } catch (_) {}
      }
      // Add new services
      for (final s in _newServices) {
        final name = s['name']!.text.trim();
        if (name.isEmpty) continue;
        try {
          await ShopService.instance.addService(
            widget.shop.id,
            name: name,
            price: double.tryParse(s['price']!.text) ?? 0.0,
            durationMinutes: int.tryParse(s['duration']!.text) ?? 20,
          );
        } catch (_) {}
      }

      ShopModel? updated;
      if (_hasChanges || _hasServiceChanges) {
        updated = await ShopService.instance.updateShop(
          widget.shop.id,
          name: _nameController.text.trim(),
          category: _selectedCategory,
          address: _addressController.text.trim(),
          state: _selectedState,
          city: _selectedCity,
          avgWaitMinutes:
              int.tryParse(_avgWaitController.text) ?? widget.shop.avgWaitMinutes,
          openingHours: _openingHoursController.text.trim().isNotEmpty
              ? _openingHoursController.text.trim()
              : null,
        );
      } else {
        updated = await ShopService.instance.getShop(widget.shop.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓  Shop details updated'),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message),
              backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update shop. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; _isUploadingImages = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Shop Details',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface),
                            ),
                            Text(
                              widget.shop.name,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('General Details'),
                        const SizedBox(height: 14),
                        _buildSection([
                          _field(_nameController, 'SHOP NAME',
                              'e.g. Luxe Cuts Studio'),
                          const SizedBox(height: 16),
                          _categoryDropdown(),
                          const SizedBox(height: 16),
                          _field(_addressController, 'ADDRESS',
                              'Street, locality'),
                          const SizedBox(height: 16),
                          SearchablePickerField(
                            label: 'STATE',
                            hint: 'Select state',
                            icon: Icons.map_outlined,
                            value: _selectedState.isEmpty ? null : _selectedState,
                            onTap: () => showSearchPicker(
                              context: context,
                              title: 'State',
                              items: _stateCityData.keys.toList()..sort(),
                              onSelected: (val) => setState(() {
                                _selectedState = val;
                                if (!(_stateCityData[val] ?? []).contains(_selectedCity)) {
                                  _selectedCity = '';
                                }
                              }),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SearchablePickerField(
                            label: 'CITY',
                            hint: _selectedState.isEmpty ? 'Select state first' : 'Select city',
                            icon: Icons.location_city_outlined,
                            value: _selectedCity.isEmpty ? null : _selectedCity,
                            enabled: _selectedState.isNotEmpty,
                            onTap: _selectedState.isEmpty ? null : () => showSearchPicker(
                              context: context,
                              title: 'City',
                              items: (_stateCityData[_selectedState] ?? [])..sort(),
                              onSelected: (val) => setState(() => _selectedCity = val),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        _sectionTitle('Hours & Queue Settings'),
                        const SizedBox(height: 14),
                        _buildSection([
                          _field(
                            _openingHoursController,
                            'OPENING HOURS',
                            '9:00 AM - 8:00 PM',
                          ),
                          const SizedBox(height: 16),
                          _field(
                            _avgWaitController,
                            'AVG. WAIT TIME (MINUTES)',
                            '10',
                            keyboard: TextInputType.number,
                            cap: TextCapitalization.none,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Estimated wait time shown to customers when they view your shop.',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _sectionTitle('Services'),
                            const Spacer(),
                            GestureDetector(
                              onTap: _addNewService,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text('Add', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Remove old services or add new ones. Changes save when you tap Save Changes.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        _buildSection([
                          // Existing services
                          ..._existingServices.asMap().entries.map((e) {
                            final i = e.key;
                            final svc = e.value;
                            return Column(
                              children: [
                                if (i > 0) Divider(color: AppColors.outline.withValues(alpha: 0.2), height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(svc.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                                          const SizedBox(height: 2),
                                          Text('₹${svc.price.toStringAsFixed(svc.price.truncateToDouble() == svc.price ? 0 : 2)}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _markDeleteExistingService(svc.id),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: AppColors.errorContainer, borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.onErrorContainer),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                          // New services being added
                          ..._newServices.asMap().entries.map((e) {
                            final i = e.key;
                            final s = e.value;
                            return Column(
                              children: [
                                if (_existingServices.isNotEmpty || i > 0)
                                  Divider(color: AppColors.outline.withValues(alpha: 0.2), height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _field(s['name']!, 'SERVICE NAME', 'e.g. Haircut'),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: _field(s['price']!, 'PRICE (₹)', '0', keyboard: TextInputType.number, cap: TextCapitalization.none),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: _field(s['duration']!, 'MINS', '20', keyboard: TextInputType.number, cap: TextCapitalization.none),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _removeNewService(i),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: AppColors.errorContainer, borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.onErrorContainer),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                          if (_existingServices.isEmpty && _newServices.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('No services yet. Tap + Add to add one.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                            ),
                        ]),
                        const SizedBox(height: 24),
                        _sectionTitle('Gallery'),
                        const SizedBox(height: 6),
                        Text(
                          'Up to 10 photos. Changes are saved when you tap Save Changes.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        _buildSection([
                          if (_isUploadingImages)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Saving images…', style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary)),
                                ],
                              ),
                            ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                            itemCount: _totalImageCount + (_totalImageCount < 10 ? 1 : 0),
                            itemBuilder: (_, i) {
                              // Add button
                              if (i == _totalImageCount) {
                                return GestureDetector(
                                  onTap: _pickNewImages,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 26),
                                        SizedBox(height: 4),
                                        Text('Add', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              // Existing uploaded image
                              if (i < _existingImages.length) {
                                final url = _existingImages[i];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (_, __, ___) => Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.broken_image_outlined, color: AppColors.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4, right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removeExistingImage(url),
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                          child: const Icon(Icons.close, color: Colors.white, size: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                              // Newly picked (not yet uploaded) image
                              final newIdx = i - _existingImages.length;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: kIsWeb
                                        ? Image.network(
                                            _newImages[newIdx].path,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          )
                                        : Image.file(
                                            File(_newImages[newIdx].path),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                  ),
                                  Positioned(
                                    top: 4, right: 4,
                                    child: GestureDetector(
                                      onTap: () => _removeNewImage(newIdx),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                        child: const Icon(Icons.close, color: Colors.white, size: 12),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 4, left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (_totalImageCount == 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Tap + to add up to 10 photos',
                                style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sticky save button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface.withValues(alpha: 0),
                    AppColors.surface,
                    AppColors.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _isLoading
                  ? Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient135,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : GradientButton(
                      label: 'Save Changes',
                      onPressed: _save,
                      icon: Icons.check_circle_outline_rounded,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient135,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface),
        ),
      ],
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    TextCapitalization cap = TextCapitalization.sentences,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: cap,
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
            filled: false,
            border: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: AppColors.outline, width: 0.5)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.4),
                    width: 0.8)),
            focusedBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.only(bottom: 6),
          ),
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurface),
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CATEGORY',
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          onChanged: (v) => setState(() => _selectedCategory = v!),
          decoration: InputDecoration(
            filled: false,
            border: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.4),
                    width: 0.8)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.4),
                    width: 0.8)),
            focusedBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.only(bottom: 6),
          ),
          style:
              GoogleFonts.inter(fontSize: 15, color: AppColors.onSurface),
          items: _categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
        ),
      ],
    );
  }
}
