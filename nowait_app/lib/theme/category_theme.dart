import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Single source of truth for category icons, colors and gradients.
/// Use these helpers everywhere a shop category drives visual styling.
class CategoryTheme {
  CategoryTheme._();

  static IconData icon(String category) {
    switch (category.toLowerCase()) {
      case 'salon':
        return Icons.content_cut;
      case 'beauty parlour':
        return Icons.face_retouching_natural;
      case 'hospital':
      case 'clinic':
      case 'hospital/clinic':
        return Icons.local_hospital;
      case 'garage':
        return Icons.car_repair;
      default:
        return Icons.storefront_outlined;
    }
  }

  static Color color(String category) {
    switch (category.toLowerCase()) {
      case 'salon':
        return const Color(0xFF2563EB);
      case 'beauty parlour':
        return const Color(0xFFDB2777);
      case 'hospital':
      case 'clinic':
      case 'hospital/clinic':
        return const Color(0xFF059669);
      case 'garage':
        return const Color(0xFFD97706);
      default:
        return AppColors.primary;
    }
  }

  static List<Color> gradient(String category) {
    switch (category.toLowerCase()) {
      case 'salon':
        return [const Color(0xFF1F4CDD), const Color(0xFF5B3CDD)];
      case 'beauty parlour':
        return [const Color(0xFFDB2777), const Color(0xFFE64080)];
      case 'hospital':
      case 'clinic':
      case 'hospital/clinic':
        return [const Color(0xFF006B2D), const Color(0xFF059669)];
      case 'garage':
        return [const Color(0xFFB45309), const Color(0xFFD97706)];
      default:
        return [AppColors.primary, AppColors.secondary];
    }
  }
}
