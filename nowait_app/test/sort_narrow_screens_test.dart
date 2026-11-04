import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/screens/customer/category_screen.dart';

Map<String, dynamic> _shop(String id, String name, {double? min, double? max}) => {
      'id': id, 'name': name, 'category': 'Salon', 'address': 'Main road', 'city': 'Pune',
      'is_open': true, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': 0,
      'images': <String>[], 'avg_review_rating': 4.0, 'review_count': 3,
      'min_service_price': min, 'max_service_price': max,
    };

void main() {
  setUpAll(() { GoogleFonts.config.allowRuntimeFetching = false; SharedPreferences.setMockInitialValues({}); });
  for (final w in [320.0, 360.0, 393.0]) {
  testWidgets('sort works with no layout errors at ${w.toInt()} px wide', (tester) async {
    tester.view.physicalSize = Size(w, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: CategoryScreen(category: 'Salon', initialCity: 'Pune')));
      await tester.pumpAndSettle();
      for (final label in ['Price: Low to High', 'Price: High to Low', 'Best Rating']) {
        await tester.tap(find.byTooltip('Sort by'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
    }, () => MockClient((req) async => req.url.path == '/shops'
        ? http.Response(jsonEncode({'shops': [_shop('a', 'A', min: 10, max: 20), _shop('b', 'B')], 'total': 2}), 200)
        : http.Response('[]', 200)));
  });
  }
}
