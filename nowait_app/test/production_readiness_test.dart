import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/config/app_config.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/customer/reviews_screen.dart';
import 'package:nowait_app/screens/help_support_screen.dart';
import 'package:nowait_app/services/auth_service.dart';

ShopModel _shop() => ShopModel.fromJson({
      'id': 's1', 'name': 'Royal Gents Salon', 'category': 'Salon', 'address': 'a', 'city': 'Akola',
      'owner_id': 'o', 'is_open': true, 'has_active_subscription': true,
    });

Map<String, dynamic> _review(String id, String userId, String name, String text) => {
      'id': id, 'shop_id': 's1', 'user_id': userId, 'queue_entry_id': 'q-$id', 'rating': 2,
      'review': text, 'user_name': name, 'created_at': DateTime.now().toUtc().toIso8601String(),
    };

/// Fake server: two reviews (one written by the signed-in user) and the report endpoint.
class _Backend {
  _Backend({this.reportStatus = 200, this.alreadyReported = false});
  final int reportStatus;
  final bool alreadyReported;
  final reports = <Map<String, dynamic>>[];
  final reportPaths = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    Object body = {};
    var code = 200;
    if (path.endsWith('/reviews/shops/s1')) {
      body = {
        'reviews': [_review('r-mine', 'me', 'Me Myself', 'My own review'), _review('r-other', 'u2', 'Spammer', 'BUY CHEAP NOW')],
        'total': 2, 'page': 1, 'has_more': false, 'avg_rating': 2.0,
      };
    } else if (path.endsWith('/reviews/shops/s1/summary')) {
      body = {'average_rating': 2.0, 'total_reviews': 2, 'rating_distribution': {'2': 2}};
    } else if (path.contains('/report')) {
      reportPaths.add(path);
      reports.add(jsonDecode(r.body) as Map<String, dynamic>);
      code = reportStatus;
      body = code == 200 ? {'reported': true, 'already_reported': alreadyReported} : {'detail': "You can't report your own review."};
    }
    return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
  }
}

Future<void> _openReviews(WidgetTester tester, _Backend backend) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ReviewsScreen(shop: _shop())));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => AuthService.instance.profile = {'id': 'me', 'name': 'Me Myself', 'role': 'customer'});
  tearDown(() => AuthService.instance.profile = null);

  group('Release build guard', () {
    test('a correctly configured build is accepted', () {
      expect(AppConfig.releaseConfigProblem(base: 'https://api.nowaitt.in', sbUrl: 'https://x.supabase.co', sbKey: 'k'), isNull);
    });

    test('builds pointing at a development machine or missing settings are refused', () {
      for (final base in ['http://localhost:8000', 'https://localhost:8000', 'http://10.0.2.2:8000', 'https://192.168.1.5', 'http://api.nowaitt.in']) {
        expect(AppConfig.releaseConfigProblem(base: base, sbUrl: 'https://x.supabase.co', sbKey: 'k'), isNotNull, reason: base);
      }
      expect(AppConfig.releaseConfigProblem(base: 'https://api.nowaitt.in', sbUrl: '', sbKey: 'k'), isNotNull);
      expect(AppConfig.releaseConfigProblem(base: 'https://api.nowaitt.in', sbUrl: 'https://x.supabase.co', sbKey: ''), isNotNull);
    });

    test('policy page addresses are built from the backend address', () {
      expect(AppConfig.legalUrl('privacy'), '${AppConfig.baseUrl}/legal/privacy');
    });
  });

  group('Reporting a review', () {
    testWidgets('you can report other people\'s reviews but not your own', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _openReviews(tester, backend);
        expect(find.text('My own review'), findsOneWidget);
        expect(find.text('BUY CHEAP NOW'), findsOneWidget);
        expect(find.byIcon(Icons.flag_outlined), findsOneWidget); // only on the other person's review

        await tester.tap(find.byIcon(Icons.flag_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Report review'), findsOneWidget);
        await tester.tap(find.text('Spam or advertising'));
        await tester.enterText(find.byType(TextField), 'advertising a different shop');
        await tester.tap(find.text('Send report'));
        await tester.pumpAndSettle();

        expect(backend.reportPaths, ['/reviews/r-other/report']);
        expect(backend.reports.single, {'reason': 'spam', 'details': 'advertising a different shop'});
        expect(find.text('Thanks for telling us. We will look into it.'), findsOneWidget);
        expect(find.text('Report review'), findsNothing); // sheet closed
      }, () => MockClient(backend.handle));
    });

    testWidgets('reporting twice says so instead of pretending it counted', (tester) async {
      final backend = _Backend(alreadyReported: true);
      await http.runWithClient(() async {
        await _openReviews(tester, backend);
        await tester.tap(find.byIcon(Icons.flag_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send report'));
        await tester.pumpAndSettle();
        expect(backend.reports.single['reason'], 'offensive'); // the default choice
        expect(find.text('You have already reported this review.'), findsOneWidget);
      }, () => MockClient(backend.handle));
    });

    testWidgets('a refusal from the server is shown to the user', (tester) async {
      final backend = _Backend(reportStatus: 400);
      await http.runWithClient(() async {
        await _openReviews(tester, backend);
        await tester.tap(find.byIcon(Icons.flag_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send report'));
        await tester.pumpAndSettle();
        expect(find.text("You can't report your own review."), findsOneWidget);
      }, () => MockClient(backend.handle));
    });

    testWidgets('signed out: no report buttons at all', (tester) async {
      AuthService.instance.profile = null;
      final backend = _Backend();
      await http.runWithClient(() async {
        await _openReviews(tester, backend);
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
      }, () => MockClient(backend.handle));
    });
  });

  testWidgets('Help & Support links to every policy page', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HelpSupportScreen()));
    await tester.pumpAndSettle();
    for (final label in ['Privacy Policy', 'Terms of Service', 'Refund & Cancellation Policy', 'How to delete your account']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
