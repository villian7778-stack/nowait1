import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/owner/owner_dashboard_screen.dart';
import 'package:nowait_app/screens/owner/promotion_screen.dart';
import 'package:nowait_app/screens/owner/subscription_screen.dart';

Map<String, dynamic> _shopJson({required bool subscribed}) => {
      'id': 's1', 'name': 'My Salon', 'category': 'Salon', 'address': 'Main road', 'city': 'Pune',
      'is_open': false, 'has_active_subscription': subscribed, 'avg_wait_minutes': 10, 'queue_count': 0,
      'images': <String>[], 'services': [], 'owner_id': 'o1',
    };

/// Fake server: subscription active until [subEndsInDays] from now (null = none).
MockClient _server({required int? subEndsInDays}) => MockClient((req) async {
      final path = req.url.path;
      if (path == '/shops/my') return http.Response(jsonEncode(_shopJson(subscribed: subEndsInDays != null)), 200);
      if (path == '/subscriptions/shop/s1') {
        final active = subEndsInDays != null;
        return http.Response(jsonEncode({
          'has_active_subscription': active,
          'trial_available': false,
          'subscription': active
              ? {
                  'id': 'sub', 'shop_id': 's1', 'plan': 'basic', 'status': 'active',
                  'started_at': DateTime.now().toUtc().toIso8601String(),
                  'expires_at': DateTime.now().toUtc().add(Duration(days: subEndsInDays)).toIso8601String(),
                  'days_remaining': subEndsInDays,
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                }
              : null,
        }), 200);
      }
      if (path.startsWith('/payments/reconcile')) return http.Response(jsonEncode({'activated': []}), 200);
      if (path.startsWith('/promotions/shop/')) return http.Response(jsonEncode({'promotions': [], 'total': 0}), 200);
      if (path.contains('/summary')) {
        return http.Response(jsonEncode({'average_rating': 0, 'total_reviews': 0, 'distribution': {}}), 200);
      }
      return http.Response('[]', 200);
    });

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPromotion(WidgetTester tester, {required int? subEndsInDays}) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final shop = ShopModel.fromJson(_shopJson(subscribed: subEndsInDays != null));
    await tester.pumpWidget(MaterialApp(home: PromotionScreen(shop: shop)));
    await _settle(tester);
  }

  testWidgets('promotion screen: no subscription -> no Pay button, offers the Subscription screen', (tester) async {
    await http.runWithClient(() async {
      await pumpPromotion(tester, subEndsInDays: null);
      expect(find.textContaining('Pay & Activate'), findsNothing);
      expect(find.text('Open Subscription'), findsOneWidget);
      expect(find.textContaining('active subscription or free trial'), findsOneWidget);
    }, () => _server(subEndsInDays: null));
  });

  testWidgets('promotion screen: lengths past the subscription end are greyed out', (tester) async {
    await http.runWithClient(() async {
      await pumpPromotion(tester, subEndsInDays: 10);
      // 15 days doesn't fit before the subscription ends; 7 is pre-selected
      expect(find.textContaining('Pay & Activate  ₹70'), findsOneWidget);
      final fifteen = tester.widget<Opacity>(find.ancestor(of: find.text('15'), matching: find.byType(Opacity)).first);
      expect(fifteen.opacity, lessThan(1));
      expect(find.textContaining('A promotion must end before it'), findsOneWidget);

      // Tapping 15 says why it can't be chosen, and keeps 7 selected
      await tester.tap(find.text('15'));
      await _settle(tester);
      expect(find.text('Subscription ends sooner'), findsOneWidget);
      expect(find.textContaining('You are trying to get a 15-day promotion, but your subscription ends in 10 days'),
          findsOneWidget);
      await tester.tap(find.text('Choose shorter'));
      await _settle(tester);
      expect(find.text('Subscription ends sooner'), findsNothing);
      expect(find.textContaining('Pay & Activate  ₹70'), findsOneWidget);

      // ...or goes to the Subscription screen to extend it
      await tester.tap(find.text('15'));
      await _settle(tester);
      await tester.tap(find.text('Extend subscription'));
      await _settle(tester);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => _server(subEndsInDays: 10));
  });

  testWidgets('promotion screen: a long subscription allows every length', (tester) async {
    await http.runWithClient(() async {
      await pumpPromotion(tester, subEndsInDays: 60);
      await tester.tap(find.text('15'));
      await tester.pump();
      expect(find.textContaining('Pay & Activate  ₹150'), findsOneWidget);
      expect(find.textContaining('A promotion must end before it'), findsNothing);
    }, () => _server(subEndsInDays: 60));
  });

  testWidgets('dashboard: Promote Shop and Schemes are locked without a subscription', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: OwnerDashboardScreen()));
      await _settle(tester);
      expect(find.text('Needs subscription'), findsNWidgets(2));

      await tester.ensureVisible(find.text('Needs subscription').first);
      await tester.tap(find.text('Needs subscription').first);
      await _settle(tester);
      expect(find.text('Subscription needed'), findsOneWidget);
      expect(find.byType(PromotionScreen), findsNothing);

      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(find.text('Subscription needed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => _server(subEndsInDays: null));
  });

  testWidgets('dashboard: with a subscription, Promote Shop opens', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: OwnerDashboardScreen()));
      await _settle(tester);
      expect(find.text('Needs subscription'), findsNothing);
      await tester.ensureVisible(find.text('₹10/day'));
      await tester.tap(find.text('₹10/day'));
      await _settle(tester);
      expect(find.byType(PromotionScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => _server(subEndsInDays: 60));
  });
}
