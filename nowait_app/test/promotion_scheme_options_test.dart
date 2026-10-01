import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/owner/promotion_screen.dart';
import 'package:nowait_app/screens/owner/scheme_screen.dart';

ShopModel _shop() => ShopModel.fromJson({
      'id': 's1', 'name': 'Lux hair spa', 'category': 'Salon', 'address': 'a', 'city': 'c', 'owner_id': 'o',
      'is_open': true, 'has_active_subscription': true,
    });

/// No active promotion, nothing to reconcile.
Future<http.Response> _quietBackend(http.Request r) async {
  if (r.url.path.contains('/payments/reconcile/')) {
    return http.Response(jsonEncode({'activated': []}), 200, headers: {'content-type': 'application/json'});
  }
  return http.Response('[]', 200, headers: {'content-type': 'application/json'});
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Featured Promotion offers 3, 7 and 15 days at ₹10 a day', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, PromotionScreen(shop: _shop()));

      for (final d in ['3', '7', '15']) {
        expect(find.text(d), findsOneWidget, reason: '$d days option');
      }
      for (final gone in ['1', '2', '14', '30', '60']) {
        expect(find.text(gone), findsNothing, reason: '$gone days is no longer offered');
      }
      expect(find.text('₹10/day'), findsOneWidget);
      expect(find.text('₹20/day'), findsNothing);

      // 7 days is the default: 7 x 10 = 70.
      expect(find.text('₹70'), findsWidgets);
      for (final (days, total) in [('3', 30), ('15', 150)]) {
        await tester.tap(find.text(days));
        await tester.pump();
        expect(find.text('₹$total'), findsWidgets, reason: '$days days should cost ₹$total');
      }
    }, () => MockClient(_quietBackend));
  });

  testWidgets('Schemes can run for 3, 7 or 15 days only', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, SchemeScreen(shop: _shop()));

      for (final label in ['3 Days', '7 Days', '15 Days']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final gone in ['1 Day', '2 Days', '14 Days', '30 Days', '60 Days']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    }, () => MockClient(_quietBackend));
  });
}
