import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/customer/queue_status_screen.dart';
import 'package:nowait_app/screens/customer/shop_details_screen.dart';
import 'package:nowait_app/screens/owner/promotion_screen.dart';
import 'package:nowait_app/screens/owner/staff_management_screen.dart';
import 'package:nowait_app/theme/accent.dart';
import 'package:nowait_app/theme/app_theme.dart';
import 'package:nowait_app/theme/category_theme.dart';
import 'package:nowait_app/widgets/gradient_button.dart';

Map<String, dynamic> _shopJson(String category) => {
      'id': 's1', 'name': 'Test Shop', 'category': category, 'address': 'Main road', 'city': 'Pune',
      'is_open': true, 'has_active_subscription': true, 'can_accept_queue': true, 'avg_wait_minutes': 10,
      'queue_count': 0, 'images': <String>[], 'services': [
        {'id': 'v1', 'shop_id': 's1', 'name': 'Service', 'description': '', 'price': 100, 'duration_minutes': 15},
      ],
    };

Future<http.Response> _api(http.Request r) async {
  final path = r.url.path;
  if (path.startsWith('/shops/')) return http.Response(jsonEncode(_shopJson(_category)), 200);
  if (path.contains('/summary')) return http.Response(jsonEncode({'average_rating': 0, 'total_reviews': 0, 'distribution': {}}), 200);
  return http.Response('[]', 200);
}

String _category = 'Salon';

/// The accent the widgets below [finder] see.
AccentColors _accentAt(WidgetTester tester, Finder finder) => Accent.of(tester.element(finder));

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('each category has its own accent; unknown / empty keeps the brand blue', () {
    for (final c in ['Salon', 'Beauty Parlour', 'Hospital/Clinic', 'Garage']) {
      final a = AccentColors.forCategory(c);
      expect(a.primary, CategoryTheme.color(c));
      expect(a.gradient, CategoryTheme.gradient(c));
    }
    expect(AccentColors.forCategory('').primary, AppColors.primary);
    expect(AccentColors.forCategory(null), AccentColors.app);
    expect(AccentColors.forCategory('Beauty Parlour').primary, isNot(AppColors.primary));
  });

  testWidgets('shop page (join queue / get token) is in the shop\'s category colours', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final c in ['Beauty Parlour', 'Garage']) {
      _category = c;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: ShopDetailsScreen(shop: ShopModel.fromJson(_shopJson(c)))));
        await tester.pump(const Duration(seconds: 1));
        final button = find.byType(GradientButton).first;
        expect(_accentAt(tester, button), AccentColors.forCategory(c), reason: c);
        // The join button itself is drawn with the category gradient
        final box = tester
            .widgetList<Container>(find.descendant(of: button, matching: find.byType(Container)))
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.gradient != null);
        expect((box.gradient! as LinearGradient).colors, CategoryTheme.gradient(c));
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(_api));
    }
  });

  testWidgets('queue status takes the colour from the queue entry (opened from My Queue)', (tester) async {
    final entry = QueueEntry.fromJson({
      'id': 'q1', 'shop_id': 's1', 'shop_name': 'Clinic', 'shop_category': 'Hospital/Clinic',
      'token_number': 4, 'display_status': 'waiting', 'position': 4, 'people_ahead': 3, 'estimated_wait_minutes': 30,
    });
    expect(entry.shopCategory, 'Hospital/Clinic');
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: QueueStatusScreen(entry: entry)));
      await tester.pump(const Duration(seconds: 1));
      expect(_accentAt(tester, find.byType(Scaffold).first), AccentColors.forCategory('Hospital/Clinic'));
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(_api));
  });

  testWidgets('owner screens follow the owner\'s shop category', (tester) async {
    final garage = ShopModel.fromJson(_shopJson('Garage'));
    await http.runWithClient(() async {
      for (final screen in <Widget>[PromotionScreen(shop: garage), StaffManagementScreen(shop: garage)]) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pump(const Duration(seconds: 1));
        expect(_accentAt(tester, find.byType(Scaffold).first), AccentColors.forCategory('Garage'),
            reason: screen.runtimeType.toString());
        await tester.pumpWidget(const SizedBox());
      }
    }, () => MockClient(_api));
  });
}
