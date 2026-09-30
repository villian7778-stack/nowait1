import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nowait_app/screens/auth/forgot_password_screen.dart';
import 'package:nowait_app/screens/auth/login_screen.dart';
import 'package:nowait_app/services/locale_service.dart';
import 'package:nowait_app/theme/app_theme.dart';
import 'package:nowait_app/widgets/gradient_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _required = 'Please enter your email address';
const _invalid = 'Please enter a valid email address';

Future<void> _pump(WidgetTester t, Widget home) async {
  // Wide surface: the test font is wider than the real fonts (avoids false overflows).
  t.view.physicalSize = const Size(700, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await t.pump(const Duration(milliseconds: 1000)); // login screen has endless animations
}

Future<void> _openLoginEmailStep(WidgetTester t) async {
  await _pump(t, const LoginScreen());
  await t.tap(find.byType(GradientButton).first); // "Continue with Email"
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('login email step', () {
    testWidgets('no message before the user does anything', (t) async {
      await _openLoginEmailStep(t);
      expect(find.text(_required), findsNothing);
      expect(find.text(_invalid), findsNothing);
    });

    testWidgets('Continue with empty email shows "required"', (t) async {
      await _openLoginEmailStep(t);
      await t.tap(find.byType(GradientButton).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_required), findsOneWidget);
    });

    for (final bad in ['abc', 'abc@', 'abc@xyz', 'a b@c.com', '@x.com', 'a@b@c.com']) {
      testWidgets('invalid "$bad" shows the error on Continue', (t) async {
        await _openLoginEmailStep(t);
        await t.enterText(find.byType(TextField).first, bad);
        await t.tap(find.byType(GradientButton).first);
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text(_invalid), findsOneWidget);
      });
    }

    testWidgets('error clears once the email becomes valid', (t) async {
      await _openLoginEmailStep(t);
      await t.enterText(find.byType(TextField).first, 'abc');
      await t.tap(find.byType(GradientButton).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_invalid), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'rahul@example.com');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_invalid), findsNothing);
    });
  });

  group('forgot password', () {
    testWidgets('empty and invalid emails show messages', (t) async {
      await _pump(t, const ForgotPasswordScreen());
      expect(find.text(_required), findsNothing);
      await t.tap(find.byType(GradientButton).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_required), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'not-an-email');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_invalid), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'ok@example.com');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(_invalid), findsNothing);
      expect(find.text(_required), findsNothing);
    });
  });
}
