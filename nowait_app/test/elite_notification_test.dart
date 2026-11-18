import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/screens/customer/notifications_screen.dart';
import 'package:nowait_app/services/locale_service.dart';

Map<String, dynamic> _notif(String id, String body) => {
      'id': id, 'type': 'promotion', 'title': '⭐ Elite Promotion · Jai Salon', 'body': body,
      'shop_name': 'Jai Salon', 'shop_id': 's1', 'is_read': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  for (final lang in ['en', 'hi', 'mr']) {
    for (final width in [320.0, 393.0]) {
      testWidgets('Elite Promotion notification shows Elite, and Offer active only with an offer ($lang, ${width.toInt()} px)',
          (tester) async {
        await LocaleService.instance.setLanguage(lang);
        final l = LocaleService.instance;
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await http.runWithClient(() async {
          await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text(l.tr('promotionsTab')));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          expect(find.text('⭐ Elite Promotion · Jai Salon'), findsNWidgets(2));
          expect(find.text(l.tr('eliteBadge')), findsNWidgets(2)); // on both
          expect(find.text(l.tr('offerActiveTag')), findsOneWidget); // only the one with an offer
          await tester.pumpWidget(const SizedBox()); // any overflow above fails the test
        }, () => MockClient((req) async => req.url.path == '/notifications'
            // utf-8 like the real server (the titles have emoji)
            ? http.Response.bytes(utf8.encode(jsonEncode({
                'unread_count': 2,
                'notifications': [
                  _notif('n1', '🎁 Offer active: 20% off haircut. Open NoWaitt to explore the shop and get your service.'),
                  _notif('n2', 'Now featured in Pune. Open NoWaitt to explore the shop and get your service.'),
                ],
              })), 200, headers: {'content-type': 'application/json; charset=utf-8'})
            : http.Response('{}', 200)));
      });
    }
  }

  tearDownAll(() => LocaleService.instance.setLanguage('en'));
}
