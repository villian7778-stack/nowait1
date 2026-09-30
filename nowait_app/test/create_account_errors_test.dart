import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nowait_app/screens/auth/create_account_screen.dart';
import 'package:nowait_app/services/locale_service.dart';
import 'package:nowait_app/theme/app_theme.dart';
import 'package:nowait_app/widgets/gradient_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, {double w = 700, double h = 900, double scale = 1.0}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  // Wide surface on purpose: the test font is wider than the real fonts, so a phone-sized
  // surface would report header overflows that don't exist on a device.
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: const CreateAccountScreen(),
  ));
  await t.pumpAndSettle();
}

Finder _submit() => find.byType(GradientButton);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no errors are shown before the first submit', (t) async {
    await _pump(t);
    expect(find.text('Please give a valid contact number'), findsNothing);
    expect(find.text('Please enter your full name'), findsNothing);
  });

  testWidgets('submitting an empty form flags every field in red', (t) async {
    await _pump(t);
    await t.tap(_submit(), warnIfMissed: false);
    await t.pumpAndSettle();
    for (final msg in [
      'Please enter your full name',
      'Please give a valid contact number',
      'Please enter your email address',
      'Please enter a password',
      'Please confirm your password',
      'Please select your state',
      'Please select your city',
      'Please choose an account type',
      'Please accept the Terms & Privacy Policy',
    ]) {
      expect(find.text(msg, skipOffstage: false), findsOneWidget, reason: msg);
    }
  });

  testWidgets('short phone number shows the valid-contact message', (t) async {
    await _pump(t);
    final phone = find.byType(TextField).at(1);
    await t.enterText(phone, '98765');
    // leave the field (touch elsewhere) so it counts as "touched"
    await t.tap(find.byType(TextField).at(0));
    await t.pumpAndSettle();
    expect(find.text('Please give a valid contact number'), findsOneWidget);
    await t.enterText(phone, '9876543210');
    await t.pumpAndSettle();
    expect(find.text('Please give a valid contact number'), findsNothing);
  });
}
