import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/services/locale_service.dart';

void main() {
  test('the no-refund notice says "for any reason" in every language, and the FAQ matches it', () async {
    SharedPreferences.setMockInitialValues({});
    final l = LocaleService.instance;
    final markers = {'en': 'No refund will be given for any reason', 'hi': 'किसी भी कारण से कोई रिफंड नहीं', 'mr': 'कोणत्याही कारणास्तव परतावा'};
    for (final entry in markers.entries) {
      await l.setLanguage(entry.key);
      expect(l.tr('noRefundPolicy'), contains(entry.value), reason: entry.key);
      expect(l.faqs.any((f) => f.$2 == l.tr('noRefundPolicy')), isTrue, reason: 'FAQ answer (${entry.key})');
    }
    await l.setLanguage('en');
  });
}
