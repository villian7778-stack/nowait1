import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/customer/category_screen.dart';
import 'package:nowait_app/screens/customer/home_screen.dart';
import 'package:nowait_app/screens/owner/promotion_screen.dart';

Map<String, dynamic> _shop(String id, String name, {double? min, double? max, double rating = 0, int reviews = 0}) => {
      'id': id, 'name': name, 'category': 'Salon', 'address': 'Main road', 'city': 'Pune',
      'is_open': true, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': 0,
      'images': <String>[], 'avg_review_rating': rating, 'review_count': reviews,
      'min_service_price': min, 'max_service_price': max,
    };

// Cheapest services: B 10, C 20, A 50 (D has none). Dearest: C 100, A 60, B 30.
final _shops = [
  _shop('a', 'Shop A', min: 50, max: 60, rating: 3, reviews: 2),
  _shop('b', 'Shop B', min: 10, max: 30, rating: 4.5, reviews: 8),
  _shop('c', 'Shop C', min: 20, max: 100, rating: 4.5, reviews: 20),
  _shop('d', 'Shop D'),
];

Future<http.Response> _api(http.Request req) async {
  if (req.url.path == '/shops') return http.Response(jsonEncode({'shops': _shops, 'total': _shops.length}), 200);
  if (req.url.path == '/shops/cities') return http.Response('["Pune"]', 200);
  return http.Response('[]', 200);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('a shop detail response (services, no range) still gets its price range', () {
    final shop = ShopModel.fromJson({
      ..._shop('x', 'X'),
      'min_service_price': null, 'max_service_price': null,
      'services': [
        {'id': '1', 'name': 'Cut', 'description': '', 'price': 30},
        {'id': '2', 'name': 'Shave', 'description': '', 'price': 10},
        {'id': '3', 'name': 'Spa', 'description': '', 'price': 20},
      ],
    });
    expect([shop.minServicePrice, shop.maxServicePrice], [10, 30]);
  });

  group('Category list "Sort by"', () {
    List<String> order(WidgetTester tester) {
      final names = ['Shop A', 'Shop B', 'Shop C', 'Shop D'];
      names.sort((x, y) => tester.getTopLeft(find.text(x)).dy.compareTo(tester.getTopLeft(find.text(y)).dy));
      return names;
    }

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Sort by'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('price low-high, high-low and best rating', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: CategoryScreen(category: 'Salon', initialCity: 'Pune')));
        await tester.pumpAndSettle();
        expect(order(tester), ['Shop A', 'Shop B', 'Shop C', 'Shop D']);

        // Low to high by each shop's cheapest service; shops without services last.
        await pick(tester, 'Price: Low to High');
        expect(order(tester), ['Shop B', 'Shop C', 'Shop A', 'Shop D']);

        // High to low by each shop's dearest service.
        await pick(tester, 'Price: High to Low');
        expect(order(tester), ['Shop C', 'Shop A', 'Shop B', 'Shop D']);

        // Highest average first; a tie goes to the shop with more reviews.
        await pick(tester, 'Best Rating');
        expect(order(tester), ['Shop C', 'Shop B', 'Shop A', 'Shop D']);

        // Choosing the active sort again switches it off.
        await pick(tester, 'Best Rating');
        expect(order(tester), ['Shop A', 'Shop B', 'Shop C', 'Shop D']);

        // Price range shown on the card.
        expect(find.text('10–30'), findsOneWidget);

        // "Sort by" sits on the same line as By Name / By Address, same height.
        final chip = tester.getRect(find.ancestor(of: find.text('By Name'), matching: find.byType(AnimatedContainer)).first);
        final sort = tester.getRect(find.ancestor(of: find.text('Sort by'), matching: find.byType(AnimatedContainer)).first);
        expect(sort.center.dy, moreOrLessEquals(chip.center.dy, epsilon: 0.5));
        expect(sort.height, chip.height);

        // "Clear" appears once something is filtered or sorted, and resets all of it.
        expect(find.text('Clear'), findsNothing);
        await pick(tester, 'Price: High to Low');
        await tester.tap(find.text('By Address'));
        await tester.enterText(find.byType(TextField), 'Main');
        await tester.pump();
        expect(find.text('Clear'), findsOneWidget);
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('Clear'), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
        expect(find.text('Sort by'), findsOneWidget);
        expect(order(tester), ['Shop A', 'Shop B', 'Shop C', 'Shop D']);
      }, () => MockClient(_api));
    });
  });

  testWidgets('a promoted shop in a category shows Open once (not on the photo too)', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final promoted = {..._shop('p', 'Promo Salon', min: 10, max: 20), 'is_promoted': true, 'active_promotions': [
      {'id': 'f', 'title': 'Featured Promotion', 'description': '', 'is_active': true,
       'valid_until': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()}]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: CategoryScreen(category: 'Salon', initialCity: 'Pune')));
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PromotedShopCard');
      expect(card, findsOneWidget);
      // Narrow enough that two fit side by side on a phone: (900 - 40 - 12) / 2, capped at 260.
      expect(tester.getSize(card).width, 260);
      expect(find.descendant(of: card, matching: find.text('Open')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((req) async => req.url.path == '/shops'
        ? http.Response(jsonEncode({'shops': [promoted], 'total': 1}), 200)
        : _api(req)));
  });

  test('Featured Promotion is ₹10/day everywhere the owner sees it', () {
    expect(PromotionScreen.pricePerDay, 10);
  });

  group('Bottom tabs', () {
    testWidgets('My Queue opens at once and reloads every time it is opened', (tester) async {
      var statusCalls = 0;
      var inQueue = false;
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.byIcon(Icons.confirmation_number_outlined).last); // the bottom bar
        await tester.pump(const Duration(seconds: 1));
        expect(find.text("You're not in any queue"), findsOneWidget);
        expect(find.text('Shop Q'), findsNothing);
        final before = statusCalls;

        // Join a queue somewhere else, go to History and back: the tab shows it.
        inQueue = true;
        await tester.tap(find.byIcon(Icons.history_outlined).last);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byIcon(Icons.confirmation_number_outlined).last); // the bottom bar
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(); // draw the reloaded list
        expect(statusCalls, greaterThan(before));
        expect(find.text('Shop Q'), findsOneWidget);

        // Leave the screen so the background queue monitor stops.
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((req) async {
        if (req.url.path == '/queues/status') {
          statusCalls++;
          return http.Response(
              jsonEncode(inQueue
                  ? [
                      {'id': 'q1', 'shop_id': 's1', 'shop_name': 'Shop Q', 'token_number': 7, 'status': 'waiting',
                       'display_status': 'waiting', 'position': 4, 'people_ahead': 3, 'estimated_wait_minutes': 30,
                       'joined_at': DateTime.now().toUtc().toIso8601String()}
                    ]
                  : []),
              200);
        }
        return _api(req);
      }));
    });
  });
}
