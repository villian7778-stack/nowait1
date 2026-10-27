import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/main.dart';
import 'package:nowait_app/services/api_client.dart';
import 'package:nowait_app/services/app_update_service.dart';
import 'package:nowait_app/services/locale_service.dart';
import 'package:nowait_app/widgets/gradient_button.dart';

void main() {
  setUpAll(() async {
    AppUpdateService.debugPlatformOverride = 'android';
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NOWAIT', packageName: 'com.nowaitt.nowaitt_app', version: '1.0.0', buildNumber: '3',
      buildSignature: '', installerStore: null);
    await AppUpdateService.instance.init();
  });
  setUp(() => AppUpdateService.instance.debugReset());

  group('Double taps', () {
    Future<void> pumpButton(WidgetTester tester, Widget button) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: button))));

    testWidgets('GradientButton runs a slow action once however often it is tapped', (tester) async {
      var calls = 0;
      final done = Completer<void>();
      await pumpButton(tester, GradientButton(label: 'Pay', onPressed: () { calls++; return done.future; }));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Pay'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget); // shows it's working
      done.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay'));
      await tester.pump();
      expect(calls, 2); // usable again once the first one finished
    });

    testWidgets('GhostButton is protected the same way', (tester) async {
      var calls = 0;
      final done = Completer<void>();
      await pumpButton(tester, GhostButton(label: 'Retry', onPressed: () { calls++; return done.future; }));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(calls, 1);
      done.complete();
      await tester.pumpAndSettle();
    });
  });

  group('Forced update', () {
    testWidgets('an out-of-date build sees only the update screen', (tester) async {
      await tester.pumpWidget(const NoWaitApp());
      await tester.pump();
      final l = LocaleService.instance;
      expect(find.text(l.tr('continueWithGoogle')), findsOneWidget);

      AppUpdateService.instance.markRequired('https://play.google.com/store/apps/details?id=com.nowaitt.nowaitt_app');
      await tester.pump();
      expect(find.text(l.tr('updateRequiredTitle')), findsOneWidget);
      expect(find.text(l.tr('updateNow')), findsOneWidget);
      expect(find.text(l.tr('continueWithGoogle')), findsNothing); // the app can't be used
    });

    test('every request tells the server which build it is', () async {
      late http.Request sent;
      await http.runWithClient(() => ApiClient.instance.get('/shops'), () => MockClient((req) async {
        sent = req;
        return http.Response('[]', 200);
      }));
      expect(sent.headers['X-App-Build'] ?? sent.headers['x-app-build'], '3');
      expect(sent.headers.keys.map((k) => k.toLowerCase()), contains('x-app-platform'));
    });

    test('a 426 answer from the server switches on the update screen', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({'detail': 'Please update', 'update_required': true, 'store_url': 'https://example.com/app'}), 426));
      await expectLater(http.runWithClient(() => ApiClient.instance.get('/shops'), () => client),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 426)));
      expect(AppUpdateService.instance.updateRequired, isTrue);
    });

    test('the version check can also switch it off again', () async {
      AppUpdateService.instance.markRequired(null);
      await http.runWithClient(() => AppUpdateService.instance.check(), () => MockClient((req) async {
        expect(req.url.path, '/app/version');
        expect(req.url.queryParameters['build'], '3');
        return http.Response(jsonEncode({'update_required': false, 'store_url': ''}), 200);
      }));
      expect(AppUpdateService.instance.updateRequired, isFalse);
    });

    test('offline: nothing changes and nothing crashes', () async {
      await http.runWithClient(() => AppUpdateService.instance.check(),
          () => MockClient((_) async => throw http.ClientException('offline')));
      expect(AppUpdateService.instance.updateRequired, isFalse);
    });
  });
}
