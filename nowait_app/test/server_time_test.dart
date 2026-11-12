import 'package:flutter_test/flutter_test.dart';
import 'package:nowait_app/models/models.dart';

void main() {
  test('server times (UTC) are shown in the phone\'s own time zone', () {
    // 14:05 UTC = 7:35 PM in India; whatever this machine's zone is, the value must be local.
    final t = serverTime('2026-11-12T14:05:00+00:00');
    expect(t.isUtc, isFalse);
    expect(t, DateTime.utc(2026, 11, 12, 14, 5).toLocal());
    // Same instant written differently
    expect(serverTime('2026-11-12T14:05:00Z'), t);
    expect(serverTime('2026-11-12T19:35:00+05:30'), t);
    // No time zone given: it is UTC, never taken as local time
    expect(serverTime('2026-11-12T14:05:00'), t);
  });

  test('visit history uses local time for the visit', () {
    final v = VisitHistory.fromJson({
      'id': 'v1', 'shop_id': 's1', 'shop_name': 'Shop', 'shop_category': 'Salon', 'shop_city': 'Pune',
      'token_number': 3, 'status': 'completed',
      'joined_at': '2026-11-12T17:25:00+00:00', 'served_at': '2026-11-12T17:40:00+00:00',
    });
    expect(v.joinedAt, DateTime.utc(2026, 11, 12, 17, 25).toLocal());
    expect(v.joinedAt.isUtc, isFalse);
    expect(v.servedAt, DateTime.utc(2026, 11, 12, 17, 40).toLocal());
  });
}
