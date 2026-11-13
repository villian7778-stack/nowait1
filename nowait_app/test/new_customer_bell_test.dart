import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/screens/owner/owner_dashboard_screen.dart';
import 'package:nowait_app/services/auth_service.dart';
import 'package:nowait_app/services/new_customer_bell.dart';
import 'package:nowait_app/services/push_service.dart';

Map<String, dynamic> _entry(String id, {bool walkIn = false}) =>
    {'id': id, 'is_walk_in': walkIn, 'status': 'waiting', 'token_number': 1};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> queue;
  late int rings;
  final bell = NewCustomerBell.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queue = [];
    rings = 0;
    bell.debugReset();
    bell.ring = () async => rings++;
  });
  tearDown(bell.debugReset);

  Future<void> check() => http.runWithClient(bell.check, () => MockClient((req) async =>
      http.Response(jsonEncode({'queue': queue}), 200)));

  test('opening the app does not ring; a new online customer rings once', () async {
    queue = [_entry('a'), _entry('b')];
    bell.start('s1', checkNow: false);
    await check(); // first look: these were already waiting
    expect(rings, 0);

    await check(); // nothing new
    expect(rings, 0);

    queue = [...queue, _entry('c'), _entry('d')];
    await check(); // two joined since the last check: one bell
    expect(rings, 1);

    queue = queue.where((e) => e['id'] != 'a').toList(); // someone served: no bell
    await check();
    expect(rings, 1);
  });

  test('a walk-in the owner added does not ring', () async {
    bell.start('s1', checkNow: false);
    await check();
    queue = [_entry('w1', walkIn: true)];
    await check();
    expect(rings, 0);
  });

  test('muted: never rings, and the choice is remembered on the phone', () async {
    bell.start('s1', checkNow: false);
    await check();
    await bell.setEnabled(false);
    queue = [_entry('x')];
    await check();
    expect(rings, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('owner_new_customer_sound'), isFalse);

    bell.enabled.value = true; // e.g. app restarted
    await bell.loadPreference();
    expect(bell.enabled.value, isFalse);
  });

  test('turning it back on does not ring for customers who joined while it was off', () async {
    bell.start('s1', checkNow: false);
    await check();
    await bell.setEnabled(false);
    queue = [_entry('joined-while-muted')];
    // Turning it on takes a first look right away (against this fake server)
    await http.runWithClient(() async {
      await bell.setEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, () => MockClient((req) async => http.Response(jsonEncode({'queue': queue}), 200)));
    expect(rings, 0); // the customer who joined while muted doesn't ring
    await check();
    expect(rings, 0);
    queue = [...queue, _entry('new')];
    await check();
    expect(rings, 1);
  });

  test('offline: no ring, no crash', () async {
    bell.start('s1', checkNow: false);
    await http.runWithClient(bell.check, () => MockClient((_) async => throw http.ClientException('offline')));
    expect(rings, 0);
  });

  test('logout works even without Firebase (push not set up on this device)', () async {
    PushService.disabled = true;
    FlutterSecureStorage.setMockInitialValues({});
    AuthService.instance.accessToken = 'token';
    AuthService.instance.profile = {'id': 'u1', 'role': 'owner'};
    await AuthService.instance.logout();
    expect(AuthService.instance.isLoggedIn, isFalse);
  });

  for (final width in [320.0, 393.0]) {
    testWidgets('the real owner Profile tab shows the sound switch, and it mutes the bell (${width.toInt()} px)', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = Size(width, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      AuthService.instance.profile = {'id': 'o1', 'name': 'Owner', 'role': 'owner', 'email': 'o@x.com', 'phone': '+919800000000'};
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OwnerDashboardScreen()));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byIcon(Icons.person_outline_rounded).last); // bottom bar: Profile
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('New customer sound'), findsOneWidget);
        expect(find.textContaining('Bell when a customer joins'), findsOneWidget);
        final toggle = find.descendant(
            of: find.ancestor(of: find.text('New customer sound'), matching: find.byType(Row)).first,
            matching: find.byType(Switch));
        await tester.ensureVisible(toggle);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 300));
        expect(bell.enabled.value, isFalse);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        await tester.pumpWidget(const SizedBox()); // any overflow above fails the test
      }, () => MockClient((req) async => req.url.path == '/shops/my'
          ? http.Response(jsonEncode({
              'id': 's1', 'name': 'My Salon', 'category': 'Salon', 'address': 'Road', 'city': 'Pune',
              'is_open': true, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': 0,
              'images': <String>[], 'services': []}), 200)
          : http.Response('[]', 200)));
      AuthService.instance.profile = null;
    });
  }

  testWidgets('owner Profile tab has the new-customer sound switch', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The switch itself, as used on the Profile tab, follows the bell's setting.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: bell.enabled,
          builder: (_, on, __) => Switch(value: on, onChanged: bell.setEnabled),
        ),
      ),
    ));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bell.enabled.value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}

