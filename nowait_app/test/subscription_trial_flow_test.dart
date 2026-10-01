import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/owner/subscription_screen.dart';

/// A tiny fake backend for the Subscription screen: remembers whether the free month has been
/// started and answers the three calls the screen makes.
class _FakeBackend {
  _FakeBackend({required this.trialAvailable});
  bool trialAvailable;
  bool trialStarted = false;
  final calls = <String>[];

  Map<String, dynamic> get _status {
    if (trialStarted) {
      final end = DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String();
      return {
        'has_active_subscription': true,
        'subscription': {
          'id': 'sub', 'shop_id': 's1', 'plan': 'trial', 'status': 'active',
          'started_at': DateTime.now().toUtc().toIso8601String(), 'expires_at': end,
          'days_remaining': 30, 'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        'trial_available': false,
      };
    }
    return {'has_active_subscription': false, 'subscription': null, 'trial_available': trialAvailable};
  }

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    Map<String, dynamic> body;
    var code = 200;
    if (r.url.path.endsWith('/payments/reconcile/shop/s1')) {
      body = {'activated': []};
    } else if (r.url.path.endsWith('/subscriptions/shop/s1/start-trial')) {
      if (!trialAvailable) {
        return http.Response(jsonEncode({'detail': 'The free trial has already been used with this email or mobile number.'}), 409);
      }
      trialStarted = true;
      trialAvailable = false;
      body = _status;
      code = 201;
    } else if (r.url.path.endsWith('/subscriptions/shop/s1')) {
      body = _status;
    } else {
      return http.Response('{}', 404);
    }
    return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
  }
}

ShopModel _shop() => ShopModel.fromJson({
      'id': 's1', 'name': 'Lux hair spa', 'category': 'Salon', 'address': 'a', 'city': 'c', 'owner_id': 'o',
      'is_open': false, 'has_active_subscription': false,
    });

Future<void> _open(WidgetTester tester, _FakeBackend backend, Future<void> Function() body) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(home: SubscriptionScreen(shop: _shop())));
    await tester.pumpAndSettle();
    await body();
  }, () => MockClient(backend.handle));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('new owner sees only the free trial; after activating, the 1 and 3 month plans appear', (tester) async {
    final backend = _FakeBackend(trialAvailable: true);
    await _open(tester, backend, () async {
      // Before activating: the trial offer, no paid plans, no pay button.
      expect(find.text('1 Month Free Trial'), findsOneWidget);
      expect(find.text('Activate Free Trial'), findsOneWidget);
      expect(find.text('Start Your Free Month'), findsOneWidget);
      expect(find.text('₹49'), findsNothing);
      expect(find.text('₹130'), findsNothing);
      expect(find.textContaining('Activate  ·'), findsNothing);

      await tester.tap(find.text('Activate Free Trial'));
      await tester.pumpAndSettle();

      expect(backend.calls, contains('POST /subscriptions/shop/s1/start-trial'));
      expect(find.text('Free Trial Active'), findsOneWidget);
      expect(find.text('Activate Free Trial'), findsNothing);
      // Exactly two plans: 1 month and 3 months — no yearly plan.
      expect(find.text('₹49'), findsOneWidget);
      expect(find.text('per month'), findsOneWidget);
      expect(find.text('₹130'), findsOneWidget);
      expect(find.text('per 3 months'), findsOneWidget);
      expect(find.text('₹2,999'), findsNothing);
      expect(find.text('per year'), findsNothing);

      // Choosing a plan while the trial is running asks to extend, as before.
      await tester.tap(find.text('Renew / Upgrade Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription already active'), findsOneWidget);
      expect(find.textContaining('Do you want to extend it by 1 month?'), findsOneWidget);
      expect(find.text('Extend'), findsOneWidget);
    });
  });

  testWidgets('3-month plan shows the extend question for 3 months', (tester) async {
    final backend = _FakeBackend(trialAvailable: true);
    await _open(tester, backend, () async {
      await tester.tap(find.text('Activate Free Trial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per 3 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renew / Upgrade Plan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Do you want to extend it by 3 months?'), findsOneWidget);
    });
  });

  testWidgets('an owner who already used their free month goes straight to the paid plans', (tester) async {
    final backend = _FakeBackend(trialAvailable: false);
    await _open(tester, backend, () async {
      expect(find.text('1 Month Free Trial'), findsNothing);
      expect(find.text('Activate Free Trial'), findsNothing);
      expect(find.text('Choose Your Plan'), findsOneWidget);
      expect(find.text('Activate  ·  ₹49/month'), findsOneWidget);

      await tester.tap(find.text('per 3 months'));
      await tester.pumpAndSettle();
      expect(find.text('Activate  ·  ₹130/3 months'), findsOneWidget);
    });
  });

  testWidgets('if the server says the trial was already used, the plans are shown instead', (tester) async {
    final backend = _FakeBackend(trialAvailable: true);
    await _open(tester, backend, () async {
      backend.trialAvailable = false; // used elsewhere (e.g. another device) after the screen loaded
      await tester.tap(find.text('Activate Free Trial'));
      await tester.pumpAndSettle();
      expect(find.textContaining('free trial has already been used'), findsOneWidget);
      expect(find.text('Activate Free Trial'), findsNothing);
      expect(find.text('Activate  ·  ₹49/month'), findsOneWidget);
    });
  });
}
