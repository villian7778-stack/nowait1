import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/models/models.dart';
import 'package:nowait_app/services/locale_service.dart';
import 'package:nowait_app/widgets/queue_paused_note.dart';

Widget _host(double width, Widget child, {double textScale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child])),
          ),
        ),
      ),
    );

ShopModel _shop({bool open = true, bool sub = true, bool paused = false}) => ShopModel.fromJson({
      'id': 's', 'name': 'n', 'category': 'Salon', 'address': 'a', 'city': 'c', 'owner_id': 'o',
      'is_open': open, 'has_active_subscription': sub, 'queue_paused': paused,
    });

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('isQueuePausedByOwner only when open + subscribed + paused', () {
    expect(_shop(paused: true).isQueuePausedByOwner, isTrue);
    expect(_shop(paused: true).canAcceptQueue, isFalse);
    expect(_shop(paused: false).isQueuePausedByOwner, isFalse);
    expect(_shop(open: false, paused: true).isQueuePausedByOwner, isFalse);
    expect(_shop(sub: false, paused: true).isQueuePausedByOwner, isFalse);
  });

  for (final lang in ['en', 'hi', 'mr']) {
    for (final width in [120.0, 160.0, 320.0]) {
      for (final fit in [false, true]) {
        testWidgets('no overflow: lang=$lang width=$width fit=$fit', (t) async {
          await LocaleService.instance.setLanguage(lang);
          await t.pumpWidget(_host(width, QueuePausedNote(fontSize: 10, fit: fit), textScale: 1.3));
          expect(t.takeException(), isNull);
          expect(find.byType(QueuePausedNote), findsOneWidget);
        });
      }
    }
  }
}
