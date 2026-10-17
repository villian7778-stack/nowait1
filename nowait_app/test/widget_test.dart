import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nowait_app/main.dart';
import 'package:nowait_app/services/locale_service.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App launches on the sign-in screen when logged out', (WidgetTester tester) async {
    await tester.pumpWidget(const NoWaitApp());
    await tester.pump();
    final l = LocaleService.instance;
    expect(find.text(l.tr('continueWithGoogle')), findsOneWidget);
    expect(find.text(l.tr('continueWithEmail')), findsOneWidget);
  });
}
