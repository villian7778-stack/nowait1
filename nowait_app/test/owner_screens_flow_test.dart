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
import 'package:nowait_app/screens/owner/subscription_screen.dart';

/// Stateful fake of the backend calls the three owner screens make, shaped exactly like the
/// real API (notably: promotions come back wrapped as {"promotions": [...]}).
class _Backend {
  String subStatus = 'active';
  bool failCancelAfterDoing = false;
  DateTime subEnd = DateTime.now().toUtc().add(const Duration(days: 20));
  final List<Map<String, dynamic>> promos = [];
  final calls = <String>[];

  Map<String, dynamic> get _subStatusJson {
    final active = subStatus == 'active' && subEnd.isAfter(DateTime.now().toUtc());
    return {
      'has_active_subscription': active,
      'subscription': {
        'id': 'sub', 'shop_id': 's1', 'plan': 'basic', 'status': subStatus,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': subEnd.toIso8601String(),
        'days_remaining': subEnd.difference(DateTime.now().toUtc()).inDays,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      'trial_available': false,
    };
  }

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    Object body = {};
    var code = 200;
    final path = r.url.path;
    if (path.endsWith('/payments/reconcile/shop/s1')) {
      body = {'activated': []};
    } else if (path.endsWith('/subscriptions/shop/s1')) {
      if (r.method == 'DELETE') {
        subStatus = 'cancelled';
        if (failCancelAfterDoing) return http.Response('Internal Server Error', 500);
        body = {'has_active_subscription': false, 'subscription': _subStatusJson['subscription']};
      } else {
        body = _subStatusJson;
      }
    } else if (path.endsWith('/promotions/shop/s1')) {
      if (r.method == 'POST') {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        promos.removeWhere((p) => p['title'] != 'Featured Promotion'); // one scheme at a time
        final row = {
          'id': 'p${promos.length + 1}', 'shop_id': 's1', 'title': b['title'], 'description': b['description'],
          'valid_until': b['valid_until'], 'is_active': true, 'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        promos.add(row);
        body = row;
        code = 201;
      } else {
        body = {'promotions': promos};
      }
    } else if (path.contains('/promotions/') && r.method == 'PUT') {
      final id = path.split('/').last;
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      final row = promos.firstWhere((p) => p['id'] == id);
      row.addAll(b);
      body = row;
    } else if (path.contains('/promotions/') && r.method == 'DELETE') {
      promos.removeWhere((p) => p['id'] == path.split('/').last);
      return http.Response('', 204);
    } else {
      return http.Response('{}', 404);
    }
    return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
  }
}

ShopModel _shop({bool active = true}) => ShopModel.fromJson({
      'id': 's1', 'name': 'Lux hair spa', 'category': 'Salon', 'address': 'a', 'city': 'c', 'owner_id': 'o',
      'is_open': active, 'has_active_subscription': active,
    });

Future<void> _open(WidgetTester tester, _Backend backend, Widget screen, Future<void> Function() body) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
    await body();
  }, () => MockClient(backend.handle));
}

Map<String, dynamic> _featured({required int daysLeft, required int totalDays}) {
  final now = DateTime.now().toUtc();
  return {
    'id': 'f1', 'shop_id': 's1', 'title': 'Featured Promotion',
    'description': 'Shop promoted for $totalDays days in total (extended by 3 days)',
    'valid_until': now.add(Duration(days: daysLeft)).toIso8601String(),
    'is_active': true,
    'created_at': now.subtract(Duration(days: totalDays - daysLeft)).toIso8601String(),
  };
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('Subscription cancel', () {
    testWidgets('needs exactly CANCEL, then returns to the shop page', (tester) async {
      final backend = _Backend();
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop()))),
                  child: const Text('My shop page'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('My shop page'));
        await tester.pumpAndSettle();

        expect(find.text('Subscription Active'), findsOneWidget);
        await tester.tap(find.text('Cancel Subscription'));
        await tester.pumpAndSettle();
        expect(find.textContaining('NO REFUND'), findsOneWidget);
        expect(find.textContaining('inactive'), findsWidgets);

        Future<void> tryConfirm(String typed) async {
          await tester.enterText(find.byType(TextField), typed);
          await tester.pump();
          await tester.tap(find.text('Cancel Subscription').last, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(backend.calls.where((c) => c.startsWith('DELETE')), isEmpty, reason: '"$typed" must not confirm');
        }

        await tryConfirm('');
        await tryConfirm('cancel');
        await tryConfirm('CANCEL ');
        await tryConfirm(' CANCEL');
        await tryConfirm('CAN CEL');

        await tester.enterText(find.byType(TextField), 'CANCEL');
        await tester.pump();
        await tester.tap(find.text('Cancel Subscription').last);
        await tester.pumpAndSettle();

        expect(backend.calls.where((c) => c.startsWith('DELETE')), hasLength(1));
        // Straight back on the shop page, with the confirmation message.
        expect(find.text('My shop page'), findsOneWidget);
        expect(find.byType(SubscriptionScreen), findsNothing);
        expect(find.textContaining('Subscription cancelled'), findsOneWidget);
      }, () => MockClient(backend.handle));
    });

    testWidgets('if the server errors, the screen reloads the real state and shows the message', (tester) async {
      final backend = _Backend()..failCancelAfterDoing = true;
      await _open(tester, backend, SubscriptionScreen(shop: _shop()), () async {
        await tester.tap(find.text('Cancel Subscription'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'CANCEL');
        await tester.pump();
        await tester.tap(find.text('Cancel Subscription').last);
        await tester.pumpAndSettle();
        // The cancel did go through on the server, so the reloaded screen shows inactive, not stuck.
        expect(find.text('Subscription Inactive'), findsOneWidget);
        expect(find.textContaining('Something went wrong on our end'), findsOneWidget);
      });
    });
  });

  group('Promotion screen', () {
    testWidgets('shows days left, expiry and total of the running promotion', (tester) async {
      final backend = _Backend()..promos.add(_featured(daysLeft: 5, totalDays: 10));
      await _open(tester, backend, PromotionScreen(shop: _shop()), () async {
        expect(find.text('Promotion is active'), findsOneWidget);
        expect(find.text('10 days'), findsOneWidget); // total promoted
        expect(find.text('Days left'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('Expires on'), findsOneWidget);
        expect(find.textContaining('extended by 3 days'), findsOneWidget);
        expect(find.text('Add More Days'), findsOneWidget);
        expect(find.textContaining('Extend Promotion'), findsOneWidget);
      });
    });

    testWidgets('with no promotion it offers to pay and activate', (tester) async {
      await _open(tester, _Backend(), PromotionScreen(shop: _shop()), () async {
        expect(find.text('Promotion is active'), findsNothing);
        expect(find.text('Select Duration'), findsOneWidget);
        expect(find.textContaining('Pay & Activate'), findsOneWidget);
      });
    });

    testWidgets('extend dialog states the new end date', (tester) async {
      final backend = _Backend()..promos.add(_featured(daysLeft: 5, totalDays: 10));
      await _open(tester, backend, PromotionScreen(shop: _shop()), () async {
        await tester.tap(find.textContaining('Extend Promotion'));
        await tester.pumpAndSettle();
        expect(find.textContaining('extends it to'), findsOneWidget);
        final end = DateTime.now().add(const Duration(days: 12));
        const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        expect(find.textContaining('${end.day} ${m[end.month - 1]} ${end.year}'), findsWidgets);
      });
    });

    testWidgets('an expired promotion is not shown as active', (tester) async {
      final backend = _Backend()..promos.add(_featured(daysLeft: -1, totalDays: 7));
      await _open(tester, backend, PromotionScreen(shop: _shop()), () async {
        expect(find.text('Promotion is active'), findsNothing);
      });
    });
  });

  group('Scheme screen', () {
    testWidgets('create → active card on top → edit → update → cancel', (tester) async {
      final backend = _Backend();
      await _open(tester, backend, SchemeScreen(shop: _shop()), () async {
        expect(find.text('Scheme is active'), findsNothing);
        await tester.enterText(find.widgetWithText(TextField, 'e.g. 20% Off on Weekdays'), '20% off');
        await tester.enterText(find.widgetWithText(TextField, 'Describe the offer in detail...'), 'Weekdays only');
        await tester.pump();
        await tester.tap(find.text('7 Days'));
        await tester.pump();
        await tester.tap(find.text('Save Scheme'));
        await tester.pumpAndSettle();

        expect(backend.promos, hasLength(1));
        expect(find.text('Scheme is active'), findsOneWidget);
        expect(find.text('20% off'), findsOneWidget);
        expect(find.text('7'), findsOneWidget); // days left
        expect(find.text('Edit Scheme'), findsOneWidget);
        expect(find.text('Cancel Scheme'), findsOneWidget);

        // Edit → form with current values → update for 15 days
        await tester.tap(find.text('Edit Scheme'));
        await tester.pumpAndSettle();
        expect(find.text('Update Scheme'), findsOneWidget);
        expect(find.text('Discard changes'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, '20% off'), '25% off');
        await tester.tap(find.text('15 Days'));
        await tester.pump();
        await tester.tap(find.text('Update Scheme'));
        await tester.pumpAndSettle();

        expect(backend.promos, hasLength(1), reason: 'still exactly one scheme');
        expect(backend.promos.first['title'], '25% off');
        expect(find.text('Scheme is active'), findsOneWidget);
        expect(find.text('25% off'), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
        expect(backend.calls.where((c) => c.startsWith('PUT')), hasLength(1));

        // Cancel the scheme (let the success snackbar go away first, it floats over the buttons)
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel Scheme'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel Scheme').last);
        await tester.pumpAndSettle();
        expect(backend.promos, isEmpty);
        expect(find.text('Scheme is active'), findsNothing);
        expect(find.text('Save Scheme'), findsOneWidget);
      });
    });

    testWidgets('an existing scheme is shown on open, ignoring the featured promotion', (tester) async {
      final backend = _Backend()
        ..promos.add(_featured(daysLeft: 5, totalDays: 5))
        ..promos.add({
          'id': 'sc1', 'shop_id': 's1', 'title': 'Diwali offer', 'description': '10% off',
          'valid_until': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
          'is_active': true, 'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      await _open(tester, backend, SchemeScreen(shop: _shop()), () async {
        expect(find.text('Scheme is active'), findsOneWidget);
        expect(find.text('Diwali offer'), findsOneWidget);
        expect(find.text('Featured Promotion'), findsNothing);
      });
    });
  });
}
