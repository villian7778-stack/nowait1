import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nowait_app/widgets/gradient_button.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a long label never runs off a button on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const long = 'Reset Limit  ·  Remove the limit (no cap) for this queue';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(width: double.infinity, child: GhostButton(label: long, icon: Icons.restart_alt_rounded, onPressed: () {})),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: GradientButton(label: long, icon: Icons.payment_rounded, onPressed: () {})),
            ],
          ),
        ),
      ),
    ));
    // An overflow would fail the test; the labels are shortened with "..." instead.
    for (final e in find.text(long).evaluate()) {
      expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isTrue);
    }
    expect(find.text(long), findsNWidgets(2));
  });
}
