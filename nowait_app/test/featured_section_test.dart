import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/customer/featured_section.dart';
import 'package:nowait_app/screens/customer/home_screen.dart';
import 'package:nowait_app/screens/customer/shop_details_screen.dart';

Map<String, dynamic> _shop(String id, String name, String category, String city,
        {bool promoted = false, bool open = true, bool scheme = false, double rating = 0, int reviews = 0}) =>
    {
      'id': id, 'name': name, 'category': category, 'address': '$name Road', 'city': city,
      'is_open': open, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': 2,
      'images': <String>[], 'is_promoted': promoted, 'avg_review_rating': rating, 'review_count': reviews,
      'active_promotions': [
        if (promoted)
          {'id': 'f$id', 'title': 'Featured Promotion', 'description': '', 'is_active': true,
           'valid_until': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()},
        if (scheme)
          {'id': 's$id', 'title': '10% off haircut', 'description': 'Weekdays', 'is_active': true,
           'valid_until': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()},
      ],
    };

/// Pune: promoted salons and a promoted garage (no promoted parlour / hospital). Nagpur: none.
final _byCity = <String, List<Map<String, dynamic>>>{
  'Pune': [
    _shop('p1', 'Pune Cuts', 'Salon', 'Pune', promoted: true, scheme: true, rating: 4.6, reviews: 12),
    _shop('p2', 'Style Hub', 'Salon', 'Pune', promoted: true, open: false),
    _shop('p3', 'Fix Garage', 'Garage', 'Pune', promoted: true),
    _shop('p4', 'Plain Parlour', 'Beauty Parlour', 'Pune'),
    _shop('p5', 'City Clinic', 'Hospital/Clinic', 'Pune'),
  ],
  'Nagpur': [
    _shop('n1', 'Orange Salon', 'Salon', 'Nagpur'),
    _shop('n2', 'Nagpur Garage', 'Garage', 'Nagpur'),
  ],
};

Future<http.Response> _api(http.Request req) async {
  switch (req.url.path) {
    case '/shops':
      final city = req.url.queryParameters['city'];
      final shops = city == null ? _byCity.values.expand((s) => s).toList() : (_byCity[city] ?? []);
      return http.Response(jsonEncode({'shops': shops, 'total': shops.length}), 200);
    case '/shops/cities':
      return http.Response(jsonEncode(_byCity.keys.toList()), 200);
    case '/notifications':
      return http.Response(jsonEncode({'notifications': [], 'unread_count': 0}), 200);
  }
  return http.Response('[]', 200);
}

Future<void> _pumpHome(WidgetTester tester, {required String city, Size size = const Size(393, 852)}) async {
  SharedPreferences.setMockInitialValues({'selected_city': city});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: 40, bottom: 24); // status bar + gesture bar
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Bottom edge of the visible area above the bottom navigation bar.
double _visibleBottom(WidgetTester tester) =>
    tester.getTopLeft(find.byIcon(Icons.home_rounded).last).dy - 10;

/// Names on the Featured row, in order, scrolling it sideways so lazily built cards are seen too.
Future<List<String>> _featuredNames(WidgetTester tester) async {
  final names = <String>[];
  void collect() {
    for (final c in tester.widgetList<FeaturedShopCard>(find.byType(FeaturedShopCard))) {
      if (!names.contains(c.shop.name)) names.add(c.shop.name);
    }
  }
  final row = find.ancestor(of: find.byType(FeaturedShopCard).first, matching: find.byType(Scrollable)).first;
  collect();
  for (var i = 0; i < 6; i++) {
    await tester.drag(row, const Offset(-250, 0));
    await tester.pump(const Duration(milliseconds: 200));
    collect();
  }
  await tester.drag(row, const Offset(5000, 0)); // back to the start
  await tester.pump(const Duration(milliseconds: 300));
  return names;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('shuffle: only promoted, subscribed shops, and the first one changes between loads', () {
    final shops = List.generate(
        6,
        (i) => ShopModel.fromJson({
              ..._shop('$i', 'S$i', 'Salon', 'Pune', promoted: i != 5),
              'has_active_subscription': i != 4,
            }));
    final firsts = <String>{};
    for (var seed = 0; seed < 40; seed++) {
      final out = shuffledFeaturedShops(shops, Random(seed));
      expect(out.map((s) => s.id).toSet(), {'0', '1', '2', '3'});
      firsts.add(out.first.id);
    }
    expect(firsts.length, greaterThan(1), reason: 'every promoted shop should get turns at the front');
  });

  testWidgets('Featured shows the city\'s promoted shops with tabs only for their categories', (tester) async {
    await http.runWithClient(() async {
      await _pumpHome(tester, city: 'Pune');

      expect(find.text('Featured'), findsOneWidget);
      // Above Explore
      expect(tester.getTopLeft(find.text('Featured')).dy, lessThan(tester.getTopLeft(find.text('Explore')).dy));
      expect((await _featuredNames(tester)).toSet(), {'Pune Cuts', 'Style Hub', 'Fix Garage'});

      // Tabs: All, Salon, Garage. No Beauty Parlor / Hospital tab (none promoted there).
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Salon'), findsWidgets);
      expect(find.text('Garage'), findsWidgets);
      expect(find.text('Beauty Parlor'), findsNothing);
      expect(find.text('Hospital & Clinic'), findsNothing);

      // Garage tab shows only the garage.
      await tester.tap(find.descendant(of: find.byType(FeaturedShopsSection), matching: find.text('Garage')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await _featuredNames(tester), ['Fix Garage']);
      await tester.tap(find.descendant(of: find.byType(FeaturedShopsSection), matching: find.text('Salon')));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await _featuredNames(tester)).toSet(), {'Pune Cuts', 'Style Hub'});
      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await _featuredNames(tester)).length, 3);

      // A tap opens the shop page (join queue / get token).
      await tester.pump(const Duration(seconds: 2)); // let the row stop scrolling
      await tester.tap(find.byType(FeaturedShopCard).first);
      await tester.pump(); // start the page transition
      await tester.pump(const Duration(seconds: 1)); // and finish it
      expect(find.byType(ShopDetailsScreen), findsOneWidget);
    }, () => MockClient(_api));
  });

  testWidgets('card: photo, name, category · address, rating, open/closed, queue, Offer badge', (tester) async {
    Future<void> pumpCard(Map<String, dynamic> json) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: FeaturedShopCard(shop: ShopModel.fromJson(json), width: 300, onTap: () {}),
            ),
          ),
        ));

    await pumpCard(_shop('p1', 'Pune Cuts', 'Salon', 'Pune', promoted: true, scheme: true, rating: 4.6, reviews: 12));
    expect(find.text('Pune Cuts'), findsOneWidget);
    expect(find.text('Salon · Pune Cuts Road'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('(12)'), findsOneWidget);
    expect(find.text('2 · ~20 min'), findsOneWidget);
    expect(find.text('Offer'), findsOneWidget);
    expect(find.textContaining('10% off'), findsNothing, reason: 'the offer itself shows on the shop page');

    await pumpCard(_shop('p2', 'Style Hub', 'Hospital/Clinic', 'Pune', promoted: true, open: false));
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Hospital & Clinic · Style Hub Road'), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // no reviews yet
    expect(find.text('Offer'), findsNothing);
  });

  testWidgets('changing the city updates Featured, and hides it when the city has no promoted shop',
      (tester) async {
    await http.runWithClient(() async {
      await _pumpHome(tester, city: 'Pune');
      expect(find.text('Featured'), findsOneWidget);

      await tester.tap(find.text('Pune').first); // city pill in the header
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('Nagpur').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Nagpur').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Featured'), findsNothing);
      expect(find.byType(FeaturedShopCard), findsNothing);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Open Now'), findsOneWidget);
    }, () => MockClient(_api));
  });

  for (final size in const [Size(360, 740), Size(393, 852), Size(412, 915), Size(430, 932)]) {
    testWidgets('fits on one screen at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await http.runWithClient(() async {
        // With Featured: Featured + Explore on the first screen, Open Now below.
        await _pumpHome(tester, city: 'Pune', size: size);
        final exploreBottom = tester.getBottomLeft(find.text('Garage').last).dy; // last Explore card text
        expect(tester.getTopLeft(find.text('Featured')).dy, greaterThan(0));
        expect(exploreBottom, lessThanOrEqualTo(_visibleBottom(tester)),
            reason: 'Explore must be fully visible together with Featured');

        // Without Featured: Explore + Open Now on the first screen.
        await tester.pumpWidget(const SizedBox());
        await _pumpHome(tester, city: 'Nagpur', size: size);
        expect(find.text('Featured'), findsNothing);
        final openNowCard = find.text('Orange Salon');
        expect(openNowCard, findsWidgets);
        final openNowBottom = tester.getBottomLeft(find.text('Open Now')).dy + 196;
        expect(openNowBottom, lessThanOrEqualTo(_visibleBottom(tester) + 1),
            reason: 'Explore and Open Now must both fit');
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(_api));
    });
  }
}

