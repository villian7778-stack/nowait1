import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/screens/customer/queue_status_screen.dart';
import 'package:nowait_app/screens/owner/manage_shop_screen.dart';
import 'package:nowait_app/widgets/walk_in_tag.dart';

ShopModel _shop() => ShopModel.fromJson({
      'id': 's1', 'name': 'My Salon', 'category': 'Salon', 'address': 'Road', 'city': 'Pune',
      'is_open': true, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': 2,
      'images': <String>[],
      'services': [
        {'id': 'cut', 'shop_id': 's1', 'name': 'Haircut', 'description': '', 'price': 100, 'duration_minutes': 20},
        {'id': 'shave', 'shop_id': 's1', 'name': 'Shave', 'description': '', 'price': 50, 'duration_minutes': 10},
      ],
    });

/// Fake server: the owner's queue holds an online customer (#10) and, once added, walk-ins.
class _Server {
  final queue = <Map<String, dynamic>>[
    {'id': 'q10', 'user_id': 'c1', 'is_walk_in': false, 'customer_name': 'Asha', 'customer_phone': '',
     'token_number': 10, 'status': 'serving', 'position': 1, 'service_id': null, 'service_ids': [],
     'service_names': [], 'selected_services': [], 'coming_at': null, 'joined_at': '2026-11-12T10:00:00Z'},
  ];
  final walkInBodies = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (path == '/queues/shop/s1/walk-in' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      walkInBodies.add(body);
      final token = 11 + walkInBodies.length - 1;
      queue.add({'id': 'w$token', 'user_id': null, 'is_walk_in': true, 'customer_name': 'Walk-in customer',
        'customer_phone': '', 'token_number': token, 'status': 'waiting', 'position': queue.length + 1,
        'service_id': null, 'service_ids': body['service_ids'], 'service_names': [], 'selected_services': [],
        'coming_at': null, 'joined_at': '2026-11-12T10:05:00Z'});
      return http.Response(jsonEncode({'id': 'w$token', 'token_number': token, 'status': 'waiting',
        'is_walk_in': true, 'service_names': [], 'total_duration_minutes': 30}), 201);
    }
    if (path == '/queues/shop/s1') {
      return http.Response(jsonEncode({
        'shop_id': 's1', 'shop_name': 'My Salon', 'is_open': true, 'queue_paused': false, 'max_queue_size': null,
        'active_count': queue.length, 'limit_reached': false, 'limit_request_pending': false,
        'total_waiting': queue.length - 1, 'now_serving_token': 10, 'queue': queue,
      }), 200);
    }
    if (path == '/queues/shop/s1/public') {
      return http.Response(jsonEncode({
        'shop_id': 's1', 'shop_name': 'My Salon', 'total_waiting': 2, 'now_serving_token': 10, 'avg_wait_minutes': 10,
        'queue': [
          {'token_number': 10, 'status': 'serving', 'service_names': ['Haircut'], 'total_duration_minutes': 20, 'position': 1, 'is_walk_in': false},
          {'token_number': 11, 'status': 'waiting', 'service_names': ['Shave'], 'total_duration_minutes': 10, 'position': 2, 'is_walk_in': true},
          {'token_number': 12, 'status': 'waiting', 'service_names': ['Haircut'], 'total_duration_minutes': 20, 'position': 3, 'is_walk_in': false},
        ],
      }), 200);
    }
    if (path.startsWith('/shops/s1')) return http.Response(jsonEncode({..._shopJson()}), 200);
    return http.Response('[]', 200);
  }

  Map<String, dynamic> _shopJson() => {
        'id': 's1', 'name': 'My Salon', 'category': 'Salon', 'address': 'Road', 'city': 'Pune',
        'is_open': true, 'has_active_subscription': true, 'avg_wait_minutes': 10, 'queue_count': queue.length,
        'images': <String>[], 'services': [],
      };
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('owner adds a walk-in: picks services, gets the next token, sees the Walk-in tag', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final server = _Server();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: ManageShopScreen(shop: _shop())));
      await _settle(tester);
      expect(find.byType(WalkInTag), findsNothing);

      // The button sits above "Live Queue"
      final button = find.text('Add Walk-in Customer');
      expect(button, findsOneWidget);
      expect(tester.getTopLeft(button).dy, lessThan(tester.getTopLeft(find.text('Live Queue')).dy));

      await tester.tap(button);
      await _settle(tester);
      expect(find.text('Haircut'), findsWidgets);
      expect(find.text('Shave'), findsWidgets);

      // Nothing chosen yet: asks for a service, sends nothing
      await tester.tap(find.text('Add to Queue'));
      await _settle(tester);
      expect(find.text('Choose at least one service.'), findsOneWidget);
      expect(server.walkInBodies, isEmpty);

      // Pick both services
      await tester.tap(find.text('Haircut').last);
      await tester.tap(find.text('Shave').last);
      await tester.pump();
      expect(find.textContaining('2 selected · ₹150 · 30 min'), findsOneWidget);
      await tester.tap(find.text('Add to Queue'));
      await _settle(tester);

      expect(server.walkInBodies.single['service_ids'], ['cut', 'shave']);
      expect(find.textContaining('Walk-in customer added · Token #11'), findsWidgets); // confirmation
      // In the live queue with the tag, the online customer without it
      expect(find.byType(WalkInTag), findsOneWidget);
      expect(find.text('Walk-in customer'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(server.handle));
  });

  testWidgets('customers see walk-ins in the queue with the Walk-in tag', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final entry = QueueEntry.fromJson({
      'id': 'q12', 'shop_id': 's1', 'shop_name': 'My Salon', 'shop_category': 'Salon',
      'token_number': 12, 'display_status': 'almostThere', 'position': 3, 'people_ahead': 2, 'estimated_wait_minutes': 30,
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: QueueStatusScreen(entry: entry)));
      await _settle(tester);
      expect(find.byType(WalkInTag, skipOffstage: false), findsOneWidget); // only token #11
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(_Server().handle));
  });

  test('public queue item reads the walk-in flag (old servers without it: not a walk-in)', () {
    expect(PublicQueueItem.fromJson({'token_number': 1, 'is_walk_in': true}).isWalkIn, isTrue);
    expect(PublicQueueItem.fromJson({'token_number': 2}).isWalkIn, isFalse);
  });
}
