import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/owner/owner_dashboard_screen.dart';
import 'package:nowait_app/services/locale_service.dart';

/// Fake server for the owner dashboard. The summary answer depends on the date choice, like the real one.
class _Backend {
  final summaryQueries = <Map<String, String>>[];

  Map<String, dynamic> summary(Map<String, String> q) {
    if (q.containsKey('from_date')) {
      return {'period': 'custom', 'total_joined': 9, 'total_served': 7, 'total_cancelled': 1, 'total_skipped': 1,
        'cancel_rate_pct': 11.1, 'skip_rate_pct': 11.1, 'peak_hour': 11, 'estimated_income': 1234567.0};
    }
    final week = q['period'] == 'week';
    return {'period': q['period'], 'total_joined': week ? 40 : 6, 'total_served': week ? 32 : 5, 'total_cancelled': 2,
      'total_skipped': 1, 'cancel_rate_pct': 5.0, 'skip_rate_pct': 2.5, 'peak_hour': 10,
      'estimated_income': week ? 9875.5 : 1240.0};
  }

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    Object body = {};
    if (path.endsWith('/shops/my')) {
      body = {'id': 's1', 'name': 'Royal Gents Salon', 'category': 'Salon', 'address': 'a', 'city': 'Khamgaon',
        'owner_id': 'o', 'is_open': true, 'has_active_subscription': true, 'services': []};
    } else if (path.endsWith('/analytics/shops/s1/summary')) {
      summaryQueries.add(r.url.queryParameters);
      body = summary(r.url.queryParameters);
    } else if (path.endsWith('/analytics/shops/s1/hourly')) {
      body = [for (var h = 0; h < 24; h++) {'hour': h, 'count': h == 10 ? 4 : 0}];
    } else if (path.endsWith('/analytics/shops/s1/staff')) {
      body = [];
    }
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  }
}

Future<void> _openAnalytics(WidgetTester tester, _Backend backend) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: OwnerDashboardScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.bar_chart_outlined));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalyticsSummary income', () {
    test('reads estimated_income, and an older server without it means 0', () {
      final s = AnalyticsSummary.fromJson({'total_served': 3, 'estimated_income': 480.5});
      expect(s.estimatedIncome, 480.5);
      expect(AnalyticsSummary.fromJson({'total_served': 3}).estimatedIncome, 0);
      expect(AnalyticsSummary.fromJson({'estimated_income': 120}).estimatedIncome, 120); // whole number from JSON
    });

    test('rupees use Indian digit grouping and whole rupees', () {
      expect(AnalyticsSummary.formatRupees(0), '₹0');
      expect(AnalyticsSummary.formatRupees(999), '₹999');
      expect(AnalyticsSummary.formatRupees(1000), '₹1,000');
      expect(AnalyticsSummary.formatRupees(12450), '₹12,450');
      expect(AnalyticsSummary.formatRupees(123456), '₹1,23,456');
      expect(AnalyticsSummary.formatRupees(1234567), '₹12,34,567');
      expect(AnalyticsSummary.formatRupees(12345678), '₹1,23,45,678');
      expect(AnalyticsSummary.formatRupees(1240.4), '₹1,240');
      expect(AnalyticsSummary.formatRupees(1240.5), '₹1,241');
      expect(AnalyticsSummary.formatRupees(-250), '-₹250');
    });
  });

  group('Analytics page', () {
    testWidgets('shows total income, customers served and the "approximate" note', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _openAnalytics(tester, backend);

        expect(find.text('Total Income'), findsOneWidget);
        expect(find.text('₹1,240'), findsOneWidget);
        expect(find.text('Approx.'), findsOneWidget);
        expect(find.text('Customers Served'), findsOneWidget);
        expect(find.text('Today'), findsWidgets);   // the choice button and the income card's date line
        expect(
          find.text('Income is an approximate value. It is calculated from the services customers selected when joining the queue, using your current service prices.'),
          findsOneWidget,
        );
        // The served count sits in the income card (the existing "Served" tile shows it too).
        expect(find.text('5'), findsWidgets);
      }, () => MockClient(backend.handle));
    });

    testWidgets('income follows the date choice: week, then a custom range', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await _openAnalytics(tester, backend);

        await tester.tap(find.text('Week'));
        await tester.pumpAndSettle();
        expect(backend.summaryQueries.last['period'], 'week');
        expect(find.text('₹9,876'), findsOneWidget);          // 9875.5 rounded to whole rupees
        expect(find.text('Last 7 days'), findsOneWidget);
        expect(find.text('₹1,240'), findsNothing);

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        // Pick both dates (the pickers open on today, so just confirm them).
        await tester.tap(find.text('From date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('To date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        final q = backend.summaryQueries.last;
        expect(q.containsKey('from_date') && q.containsKey('to_date'), isTrue, reason: 'custom range is sent to the server');
        expect(find.text('₹12,34,567'), findsOneWidget);       // Indian grouping for a big amount
        expect(find.text('7'), findsWidgets);                  // customers served for that range
        expect(find.textContaining('Income is an approximate value'), findsOneWidget);
      }, () => MockClient(backend.handle));
    });

    testWidgets('the note is translated', (tester) async {
      final backend = _Backend();
      await http.runWithClient(() async {
        await LocaleService.instance.setLanguage(kLangHi);
        addTearDown(() => LocaleService.instance.setLanguage(kLangEn));
        await _openAnalytics(tester, backend);
        expect(find.text('कुल आय'), findsOneWidget);
        expect(find.textContaining('अनुमानित मूल्य है'), findsOneWidget);
      }, () => MockClient(backend.handle));
    });
  });
}
