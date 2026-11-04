import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    _shop('n1', 'Orange Salon', 'Salon', 'Nagpur', scheme: true),
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

      expect(find.text('Trending Shops'), findsOneWidget);
      // Above Explore
      expect(tester.getTopLeft(find.text('Trending Shops')).dy, lessThan(tester.getTopLeft(find.text('Explore')).dy));
      expect((await _featuredNames(tester)).toSet(), {'Pune Cuts', 'Style Hub', 'Fix Garage'});

      // Tabs: All, Salon, Garage. No Beauty Parlor / Hospital tab (none promoted there).
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Salon'), findsWidgets);
      expect(find.text('Garage'), findsWidgets);
      expect(find.text('Beauty Parlor'), findsNothing);
      expect(find.text('Hospital & Clinic'), findsNothing);

      // Garage tab shows only the garage.
      await tester.tap(find.descendant(of: find.byType(FeaturedShopsSection), matching: find.text('Garage')).first); // the tab (cards also show the category)
      await tester.pump(const Duration(milliseconds: 300));
      expect(await _featuredNames(tester), ['Fix Garage']);
      await tester.tap(find.descendant(of: find.byType(FeaturedShopsSection), matching: find.text('Salon')).first);
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
    expect(find.text('Salon'), findsOneWidget); // category
    expect(find.text('Pune Cuts Road'), findsOneWidget); // address
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('(12)'), findsOneWidget);
    expect(find.text('2 · ~20 min'), findsOneWidget);
    expect(find.text('Offer'), findsOneWidget);
    expect(find.textContaining('10% off'), findsNothing, reason: 'the offer itself shows on the shop page');
    // "Offer" sits on the rating line, to the right of the rating.
    expect(tester.getCenter(find.text('Offer')).dy, moreOrLessEquals(tester.getCenter(find.text('4.6')).dy, epsilon: 1));
    expect(tester.getTopLeft(find.text('Offer')).dx, greaterThan(tester.getTopRight(find.text('(12)')).dx));

    await pumpCard(_shop('p2', 'Style Hub', 'Hospital/Clinic', 'Pune', promoted: true, open: false));
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Hospital & Clinic'), findsOneWidget);
    expect(find.text('Style Hub Road'), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // no reviews yet
    expect(find.text('Offer'), findsNothing);
  });

  testWidgets('changing the city updates Featured, and hides it when the city has no promoted shop',
      (tester) async {
    await http.runWithClient(() async {
      await _pumpHome(tester, city: 'Pune');
      expect(find.text('Trending Shops'), findsOneWidget);

      await tester.tap(find.text('Pune').first); // city pill in the header
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('Nagpur').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Nagpur').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Trending Shops'), findsNothing);
      expect(find.byType(FeaturedShopCard), findsNothing);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Open Now'), findsNothing); // section removed
    }, () => MockClient(_api));
  });

  testWidgets('Explore cards show the full category name and the open / shops line', (tester) async {
    await http.runWithClient(() async {
      for (final size in const [Size(360, 780), Size(393, 852)]) {
        await _pumpHome(tester, city: 'Pune', size: size);
        for (final name in ['Salon', 'Beauty Parlour', 'Hospital/Clinics', 'Garage']) {
          final text = find.text(name).last; // the Explore card (Featured tabs come first)
          expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: name);
          final card = find.ancestor(of: text, matching: find.byType(Container)).first;
          final cardRect = tester.getRect(card);
          expect(cardRect.contains(tester.getTopLeft(text)) && tester.getBottomRight(text).dx <= cardRect.right,
              isTrue, reason: '$name must be drawn inside its card');
        }
        for (final info in ['2 open · 2 shops', '0 open · 1 shops']) {
          for (final e in find.text(info).evaluate()) {
            expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
    }, () => MockClient(_api));
  });

  testWidgets('Explore: 2 x 2 grid - Salon | Beauty Parlour over Hospital/Clinics | Garage', (tester) async {
    await http.runWithClient(() async {
      for (final city in ['Pune', 'Nagpur']) { // with and without Featured above
        await _pumpHome(tester, city: city);
        Rect cardOf(String name) =>
            tester.getRect(find.ancestor(of: find.text(name).last, matching: find.byType(Container)).last);
        final salon = cardOf('Salon'), beauty = cardOf('Beauty Parlour');
        final hospital = cardOf('Hospital/Clinics'), garage = cardOf('Garage');
        const half = (393 - 40 - 12) / 2;
        for (final r in [salon, beauty, hospital, garage]) {
          expect(r.width, moreOrLessEquals(half, epsilon: 1));
          expect(r.height, moreOrLessEquals(salon.height, epsilon: 0.5));
        }
        expect(salon.top, moreOrLessEquals(beauty.top, epsilon: 0.5), reason: 'same row ($city)');
        expect(hospital.top, moreOrLessEquals(garage.top, epsilon: 0.5));
        expect(hospital.top, greaterThan(salon.bottom));
        expect(salon.left, moreOrLessEquals(20, epsilon: 1));
        expect(beauty.left, greaterThan(salon.right));
        await tester.pumpWidget(const SizedBox());
      }
    }, () => MockClient(_api));
  });

  for (final size in const [Size(360, 780), Size(393, 852), Size(412, 915)]) {
    testWidgets('home does not scroll, two Featured cards side by side '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      await http.runWithClient(() async {
        for (final city in ['Pune', 'Nagpur']) { // with and without Featured
          await _pumpHome(tester, city: city, size: size);
          final home = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
          expect(home.axis, Axis.vertical);
          expect(home.maxScrollExtent, 0, reason: 'everything fits on one screen ($city)');
          if (city == 'Pune') {
            final cards = find.byType(FeaturedShopCard);
            final a = tester.getRect(cards.at(0)), b = tester.getRect(cards.at(1));
            expect(a.left, moreOrLessEquals(20, epsilon: 1));
            expect(b.right, lessThanOrEqualTo(size.width - 20 + 1), reason: 'second card fully visible');
            expect(a.height, b.height);
          }
          await tester.pumpWidget(const SizedBox());
        }
      }, () => MockClient(_api));
    });
  }

  testWidgets('large system font (130%): Explore and Featured cards lay out without overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await http.runWithClient(() async {
      for (final size in const [Size(360, 780), Size(393, 852)]) {
        for (final city in ['Pune', 'Nagpur']) {
          await _pumpHome(tester, city: city, size: size);
          expect(find.text('Explore'), findsOneWidget); // any overflow above fails the test
          await tester.pumpWidget(const SizedBox());
        }
      }
    }, () => MockClient(_api));
  });

  testWidgets('Featured row scrolls on its own and pauses while touched', (tester) async {
    await http.runWithClient(() async {
      await _pumpHome(tester, city: 'Pune');
      final row = find.descendant(of: find.byType(FeaturedShopsSection), matching: find.byType(Scrollable)).last;
      double offset() => tester.state<ScrollableState>(row).position.pixels;
      expect(offset(), 0);

      await tester.pump(const Duration(milliseconds: 4100)); // first move starts
      await tester.pump(const Duration(milliseconds: 1500)); // and finishes
      final moved = offset();
      expect(moved, greaterThan(0), reason: 'moved by itself');

      // A touch pauses it: nothing moves for the next few seconds.
      // Press and hold on the row (no tap, so no shop page opens), then let go.
      final gesture = await tester.startGesture(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(offset(), moved);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(_api));
  });

  // Smallest: 360x780 (most current small Androids). The test font is much wider and taller
  // than the app's real fonts, so a size that only just fits for real can fail here.
  for (final size in const [Size(360, 780), Size(393, 852), Size(412, 915), Size(430, 932)]) {
    testWidgets('fits on one screen at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await http.runWithClient(() async {
        // With Featured: Featured + Explore on the first screen.
        await _pumpHome(tester, city: 'Pune', size: size);
        final exploreBottom = tester.getBottomLeft(find.text('Garage').last).dy; // last Explore card text
        expect(tester.getTopLeft(find.text('Trending Shops')).dy, greaterThan(0));
        expect(exploreBottom, lessThanOrEqualTo(_visibleBottom(tester)),
            reason: 'Explore must be fully visible together with Featured');

        // Without Featured: only the four Explore cards, all on the first screen.
        await tester.pumpWidget(const SizedBox());
        await _pumpHome(tester, city: 'Nagpur', size: size);
        expect(find.text('Trending Shops'), findsNothing);
        expect(find.text('Open Now'), findsNothing);
        for (final name in ['Salon', 'Beauty Parlour', 'Hospital/Clinics', 'Garage']) {
          expect(tester.getBottomLeft(find.text(name)).dy, lessThanOrEqualTo(_visibleBottom(tester)), reason: name);
        }
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(_api));
    });
  }
}

