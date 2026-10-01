import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/services/auth_service.dart';
import 'package:nowait_app/services/locale_service.dart';
import 'package:nowait_app/widgets/profile_details_card.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileDetailsCard formatting', () {
    test('phone is shown as +91 xxxxx xxxxx whatever the stored format', () {
      for (final raw in ['+919834086519', '9834086519', '09834086519', '+91 98340-86519']) {
        expect(ProfileDetailsCard.formatPhone(raw), '+91 98340 86519', reason: raw);
      }
      expect(ProfileDetailsCard.formatPhone(null), '');
    });

    test('location joins city and state, skipping blanks', () {
      expect(ProfileDetailsCard.formatLocation('Pune', 'Maharashtra'), 'Pune, Maharashtra');
      expect(ProfileDetailsCard.formatLocation('Pune', ''), 'Pune');
      expect(ProfileDetailsCard.formatLocation(null, null), '');
    });
  });

  group('ProfileDetailsCard on screen', () {
    tearDown(() => AuthService.instance.profile = null);

    testWidgets('shows every detail for an owner, with no edit controls', (tester) async {
      AuthService.instance.profile = {
        'name': 'Asha Patil', 'email': 'asha@example.com', 'phone': '+919834086519',
        'role': 'owner', 'city': 'Pune', 'state': 'Maharashtra',
      };
      await tester.pumpWidget(_host(const ProfileDetailsCard()));

      for (final text in ['Asha Patil', 'asha@example.com', '+91 98340 86519', 'Shop Owner', 'Pune, Maharashtra']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('These details cannot be changed.'), findsOneWidget);
      // Read-only: nothing tappable or editable.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('customers are labelled Customer; missing values show a dash', (tester) async {
      AuthService.instance.profile = {'name': 'Ravi', 'role': 'customer', 'phone': '9000000001'};
      await tester.pumpWidget(_host(const ProfileDetailsCard()));

      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Shop Owner'), findsNothing);
      expect(find.text('—'), findsNWidgets(2)); // no email, no city/state
    });
  });

  group('FAQ wording', () {
    // Words a customer would not understand — none of them may appear in any language.
    const jargon = [
      'supabase', 'postgres', 'sql', 'row-level', 'row level', 'rls', 'jwt', 'api', 'database',
      'server', 'encrypt', 'otp', 'backend',
    ];

    test('same questions in every language, no technical terms', () async {
      final l = LocaleService.instance;
      final lists = <String, List<(String, String)>>{};
      for (final lang in [kLangEn, kLangHi, kLangMr]) {
        await l.setLanguage(lang);
        lists[lang] = l.faqs;
      }
      await l.setLanguage(kLangEn);

      expect(lists[kLangHi]!.length, lists[kLangEn]!.length);
      expect(lists[kLangMr]!.length, lists[kLangEn]!.length);

      for (final entry in lists.entries) {
        for (final (q, a) in entry.value) {
          final text = '$q $a'.toLowerCase();
          for (final word in jargon) {
            expect(text.contains(word), isFalse, reason: '"$word" found in ${entry.key}: $q');
          }
        }
      }
    });

    test('personal-data answer is plain and the subscription answer states the new pricing', () {
      final faqs = LocaleService.instance.faqs;
      final safe = faqs.firstWhere((f) => f.$1.contains('personal information'));
      expect(safe.$2, contains('never sell'));
      final sub = faqs.firstWhere((f) => f.$1.contains('subscription'));
      expect(sub.$2, allOf(contains('₹49'), contains('₹130'), contains('free month')));
      expect(faqs.any((f) => f.$1.contains('free trial')), isTrue);
    });
  });
}
