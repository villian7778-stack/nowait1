import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's fonts ship inside the app (assets/google_fonts/), so nothing is downloaded on the
/// first start. With downloading switched off, every weight the app uses must load from there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every Inter / Plus Jakarta Sans weight loads without the internet', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const weights = [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800];
    // google_fonts only prints (doesn't throw) when a font is missing: catch what it prints
    final printed = <String>[];
    await runZoned(
      () => GoogleFonts.pendingFonts([
        for (final w in [...weights, FontWeight.w900]) GoogleFonts.inter(fontWeight: w),
        for (final w in weights) GoogleFonts.plusJakartaSans(fontWeight: w),
      ]),
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
    );
    expect(printed.where((l) => l.contains('unable to load font')), isEmpty, reason: printed.join('\n'));
  });

  test('the font licenses ship with the fonts', () async {
    for (final file in ['OFL-Inter.txt', 'OFL-PlusJakartaSans.txt']) {
      final text = await rootBundle.loadString('assets/google_fonts/$file');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });
}
