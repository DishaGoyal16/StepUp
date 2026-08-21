import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thapar_stepup/widgets/common_widgets.dart';
import 'package:thapar_stepup/app/theme/app_theme.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  // ─────────────────────────────────────────────────────────
  // CoinDisplay
  // ─────────────────────────────────────────────────────────
  group('CoinDisplay', () {
    testWidgets('renders amount under 1000 as plain number', (tester) async {
      await tester.pumpWidget(_wrap(const CoinDisplay(amount: 450)));
      expect(find.text('450'), findsOneWidget);
      expect(find.text('🪙'), findsOneWidget);
    });

    testWidgets('renders 1000+ as K-formatted', (tester) async {
      await tester.pumpWidget(_wrap(const CoinDisplay(amount: 2500)));
      expect(find.text('2.5K'), findsOneWidget);
    });

    testWidgets('renders 1000 as 1.0K', (tester) async {
      await tester.pumpWidget(_wrap(const CoinDisplay(amount: 1000)));
      expect(find.text('1.0K'), findsOneWidget);
    });

    testWidgets('renders 0 as plain zero', (tester) async {
      await tester.pumpWidget(_wrap(const CoinDisplay(amount: 0)));
      expect(find.text('0'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // XPDisplay
  // ─────────────────────────────────────────────────────────
  group('XPDisplay', () {
    testWidgets('shows XP amount with suffix', (tester) async {
      await tester.pumpWidget(_wrap(const XPDisplay(amount: 350)));
      expect(find.text('350 XP'), findsOneWidget);
      expect(find.text('⚡'), findsOneWidget);
    });

    testWidgets('shows 0 XP', (tester) async {
      await tester.pumpWidget(_wrap(const XPDisplay(amount: 0)));
      expect(find.text('0 XP'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // IntegrityBadge
  // ─────────────────────────────────────────────────────────
  group('IntegrityBadge', () {
    testWidgets('displays label text', (tester) async {
      await tester.pumpWidget(
          _wrap(const IntegrityBadge(label: 'Excellent', score: 0.95)));
      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shield icon is present', (tester) async {
      await tester.pumpWidget(
          _wrap(const IntegrityBadge(label: 'Good', score: 0.80)));
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    });

    testWidgets('renders for low integrity score', (tester) async {
      await tester.pumpWidget(
          _wrap(const IntegrityBadge(label: 'Poor', score: 0.30)));
      expect(find.text('Poor'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // MatchScoreChip
  // ─────────────────────────────────────────────────────────
  group('MatchScoreChip', () {
    testWidgets('displays percent correctly', (tester) async {
      await tester.pumpWidget(_wrap(const MatchScoreChip(percent: 87)));
      expect(find.text('87% Match'), findsOneWidget);
    });

    testWidgets('displays 100% match', (tester) async {
      await tester.pumpWidget(_wrap(const MatchScoreChip(percent: 100)));
      expect(find.text('100% Match'), findsOneWidget);
    });

    testWidgets('displays low match score', (tester) async {
      await tester.pumpWidget(_wrap(const MatchScoreChip(percent: 52)));
      expect(find.text('52% Match'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // SectionHeader
  // ─────────────────────────────────────────────────────────
  group('SectionHeader', () {
    testWidgets('displays title', (tester) async {
      await tester
          .pumpWidget(_wrap(const SectionHeader(title: 'Today\'s Activity')));
      expect(find.text('Today\'s Activity'), findsOneWidget);
    });

    testWidgets('displays action label when provided', (tester) async {
      await tester.pumpWidget(_wrap(SectionHeader(
        title: 'Challenges',
        actionLabel: 'See All',
        onAction: () {},
      )));
      expect(find.text('Challenges'), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);
    });

    testWidgets('no action label when not provided', (tester) async {
      await tester
          .pumpWidget(_wrap(const SectionHeader(title: 'Stats')));
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('See All'), findsNothing);
    });

    testWidgets('action callback fires on tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(SectionHeader(
        title: 'Test',
        actionLabel: 'Go',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('Go'));
      expect(tapped, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────
  // StatCard
  // ─────────────────────────────────────────────────────────
  group('StatCard', () {
    testWidgets('displays all fields', (tester) async {
      await tester.pumpWidget(_wrap(const StatCard(
        label: 'Verified Steps',
        value: '7.9K',
        emoji: '✅',
      )));
      expect(find.text('Verified Steps'), findsOneWidget);
      expect(find.text('7.9K'), findsOneWidget);
      expect(find.text('✅'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // DemoModeBanner
  // ─────────────────────────────────────────────────────────
  group('DemoModeBanner', () {
    testWidgets('shows demo mode text', (tester) async {
      await tester.pumpWidget(_wrap(const DemoModeBanner()));
      expect(find.textContaining('DEMO MODE'), findsOneWidget);
    });

    testWidgets('shows science icon', (tester) async {
      await tester.pumpWidget(_wrap(const DemoModeBanner()));
      expect(find.byIcon(Icons.science_rounded), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // GradientButton
  // ─────────────────────────────────────────────────────────
  group('GradientButton', () {
    testWidgets('shows text', (tester) async {
      await tester.pumpWidget(_wrap(GradientButton(
        text: 'Start',
        onPressed: () {},
      )));
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('shows loading indicator when isLoading=true', (tester) async {
      await tester.pumpWidget(_wrap(const GradientButton(
        text: 'Loading',
        isLoading: true,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('fires callback on tap', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(_wrap(GradientButton(
        text: 'Go',
        onPressed: () => pressed = true,
      )));
      await tester.tap(find.byType(GestureDetector).first);
      expect(pressed, isTrue);
    });

    testWidgets('shows icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(GradientButton(
        text: 'Run',
        icon: Icons.play_arrow_rounded,
        onPressed: () {},
      )));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────
  // StepProgressRing
  // ─────────────────────────────────────────────────────────
  group('StepProgressRing', () {
    testWidgets('renders without error for zero progress', (tester) async {
      await tester.pumpWidget(_wrap(const StepProgressRing(
        progress: 0.0,
        currentSteps: 0,
        goalSteps: 10000,
      )));
      // Should render without throwing
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('renders without error for full progress', (tester) async {
      await tester.pumpWidget(_wrap(const StepProgressRing(
        progress: 1.0,
        currentSteps: 10000,
        goalSteps: 10000,
      )));
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('shows formatted step count', (tester) async {
      await tester.pumpWidget(_wrap(const StepProgressRing(
        progress: 0.5,
        currentSteps: 5000,
        goalSteps: 10000,
      )));
      expect(find.text('5.0K'), findsOneWidget);
    });

    testWidgets('shows steps under 1000 unformatted', (tester) async {
      await tester.pumpWidget(_wrap(const StepProgressRing(
        progress: 0.05,
        currentSteps: 500,
        goalSteps: 10000,
      )));
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('clamps progress above 1.0', (tester) async {
      // Should not throw even with progress > 1
      await tester.pumpWidget(_wrap(const StepProgressRing(
        progress: 1.5,
        currentSteps: 15000,
        goalSteps: 10000,
      )));
      expect(find.byType(CustomPaint), findsOneWidget);
    });
  });
}
