import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/promotion_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class SchemeScreen extends StatefulWidget {
  final ShopModel shop;

  const SchemeScreen({super.key, required this.shop});

  @override
  State<SchemeScreen> createState() => _SchemeScreenState();
}

class _SchemeScreenState extends State<SchemeScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  int _durationDays = 7;
  // ignore: unused_field
  bool _saved = false;
  bool _isLoading = false;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    final existing = widget.shop.activeScheme;
    if (existing != null) {
      _titleController.text = existing.title;
      _descController.text = existing.description;
    }
  }

  void _onLocale() => setState(() {});

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty && _descController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and description')),
      );
      return;
    }
    // Prevent collision with the "Featured Promotion" paid boost entry
    if (_titleController.text.trim() == 'Featured Promotion') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use a different title for your scheme')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final validUntil = DateTime.now()
          .add(Duration(days: _durationDays))
          .toUtc()
          .toIso8601String();
      await PromotionService.instance.createPromotion(
        widget.shop.id,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        validUntil: validUntil,
      );
      if (!mounted) return;
      setState(() { _saved = true; _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓  Scheme saved for $_durationDays days'),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save scheme: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        title: Text('Add / Edit Scheme', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info
                Text(
                  'Create a scheme or offer that customers will see on your shop card.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 20),

                // Preview card
                if (_titleController.text.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.local_offer_outlined, color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titleController.text,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                              ),
                              if (_descController.text.isNotEmpty)
                                Text(
                                  _descController.text,
                                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          'Valid $_durationDays days',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '↑ Preview of how it appears on your shop card',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                ],

                // Form
                _buildLabel('SCHEME TITLE'),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. 20% Off on Weekdays',
                    prefixIcon: const Icon(Icons.title_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 20),
                _buildLabel('DESCRIPTION'),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Describe the offer in detail...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),
                _buildLabel('VALIDITY PERIOD'),
                const SizedBox(height: 14),
                // Duration chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [3, 7, 14, 30, 60].map((d) {
                    final sel = _durationDays == d;
                    return GestureDetector(
                      onTap: () => setState(() => _durationDays = d),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: sel ? AppColors.primaryGradient135 : null,
                          color: sel ? null : AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? Colors.transparent : AppColors.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$d Days',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : AppColors.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Validity info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        'Scheme valid until: ${_formattedEndDate()}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.surface.withValues(alpha: 0), AppColors.surface, AppColors.surface],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GradientButton(
                        label: 'Save Scheme',
                        onPressed: _save,
                        icon: Icons.check_rounded,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formattedEndDate() {
    final end = DateTime.now().add(Duration(days: _durationDays));
    return '${end.day}/${end.month}/${end.year}';
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
