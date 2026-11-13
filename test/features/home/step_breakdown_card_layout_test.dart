import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/features/home/home_view_model.dart';
import 'package:stepup/features/home/step_breakdown_card.dart';

/// Regression for a defect found on a real phone (360 x 804 dp): the 2x2 tile grid used a fixed
/// childAspectRatio and the tiles overflowed ("RenderFlex overflowed by 1.3 / 19 pixels") because the tile height
/// depends on font size and the "N suspicious" caption.
void main() {
  Future<void> pumpAt(WidgetTester tester, {required double width, double textScale = 1}) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: StepBreakdownCard(
              breakdown: StepBreakdown(raw: 12345, verified: 10234, pending: 120, rejected: 1991, suspicious: 1500),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final (w, scale) in [(360.0, 1.0), (320.0, 1.0), (360.0, 1.3), (411.0, 1.0), (360.0, 2.0)]) {
    testWidgets('no overflow at ${w}dp, text scale $scale', (tester) async {
      await pumpAt(tester, width: w, textScale: scale);
      expect(tester.takeException(), isNull);
      expect(find.text('1,500 suspicious'), findsOneWidget);
      expect(find.text('10,234'), findsOneWidget);
    });
  }
}
