import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'category_theme.dart';

/// The accent colours of one part of the app: the brand blue by default, or a shop category's
/// colours (pink for Beauty Parlour, green for Hospital/Clinic, amber for Garage, the brand
/// blue/purple for Salon) inside an [Accent].
@immutable
class AccentColors {
  final Color primary;
  final List<Color> gradient;

  const AccentColors(this.primary, this.gradient);

  static const app = AccentColors(AppColors.primary, [AppColors.primary, AppColors.secondary]);

  factory AccentColors.forCategory(String? category) {
    if (category == null || category.trim().isEmpty) return app;
    return AccentColors(CategoryTheme.color(category), CategoryTheme.gradient(category));
  }

  Color get secondary => gradient.last;

  /// Same direction as [AppColors.primaryGradient135].
  LinearGradient get gradient135 => LinearGradient(
        colors: gradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Tinted shadow, like [AppColors.shadowPrimary] but in this accent.
  Color get shadow => primary.withValues(alpha: 0.08);

  @override
  bool operator ==(Object other) =>
      other is AccentColors && other.primary == primary && _sameColors(other.gradient, gradient);

  @override
  int get hashCode => Object.hash(primary, Object.hashAll(gradient));

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Gives everything below it a category's accent colours. Screens that belong to one shop
/// (shop page, join-queue sheet, token, queue status, the owner's screens) wrap themselves in
/// `Accent.forCategory(shop.category, child: ...)`, and read colours with `Accent.of(context)`
/// instead of [AppColors.primary] / [AppColors.primaryGradient135]. The [GradientButton] /
/// [GhostButton] and Material widgets (text fields, switches, progress indicators...) follow it too.
///
/// Every pushed route starts outside of it, so a screen opened from a themed screen wraps itself.
class Accent extends InheritedWidget {
  final AccentColors colors;

  const Accent({super.key, required this.colors, required super.child});

  /// Accent of the nearest [Accent], or the app's brand colours.
  static AccentColors of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Accent>()?.colors ?? AccentColors.app;

  /// [child] in the colours of [category] (an empty or unknown category keeps the brand colours).
  static Widget forCategory(String? category, {Key? key, required Widget child}) =>
      AccentScope(key: key, colors: AccentColors.forCategory(category), child: child);

  @override
  bool updateShouldNotify(Accent oldWidget) => oldWidget.colors != colors;
}

/// [Accent] plus a matching Material [Theme], so stock widgets pick the colours up as well.
class AccentScope extends StatelessWidget {
  final AccentColors colors;
  final Widget child;

  const AccentScope({super.key, required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Accent(
      colors: colors,
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(primary: colors.primary, secondary: colors.secondary),
          progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(color: colors.primary),
          textSelectionTheme: theme.textSelectionTheme.copyWith(
            cursorColor: colors.primary,
            selectionHandleColor: colors.primary,
            selectionColor: colors.primary.withValues(alpha: 0.25),
          ),
          // AppTheme sets these two to the brand blue explicitly, so they need overriding too
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
              backgroundColor: WidgetStatePropertyAll(colors.primary),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
