import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/core/widgets/widgets.dart';
import 'package:stepup/data/leaderboard/leaderboard_models.dart';
import 'package:stepup/features/leaderboard/leaderboard_list.dart';

Widget _host(Widget child, {double width = 360}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

const _entries = [
  LeaderboardEntry(rank: 1, id: 'a', name: 'Asha Rao', value: 10000, hostelId: 'agira'),
  LeaderboardEntry(rank: 2, id: 'b', name: 'Bhavya Singh', value: 5000),
  LeaderboardEntry(rank: 3, id: 'c', name: 'A Very Long Name That Must Be Truncated Politely', value: 0),
];

double _bar(WidgetTester tester, int index) =>
    tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).at(index)).value!;

void main() {
  testWidgets('renders rank, avatar, name, hostel, steps and progress relative to the leader',
      (tester) async {
    await tester.pumpWidget(_host(LeaderboardList(
      entries: _entries,
      hostelNameOf: (id) => id == 'agira' ? 'Agira Hall' : null,
    )));
    expect(find.byType(RankBadge), findsNWidgets(3));
    expect(find.byType(AvatarCircle), findsNWidgets(3));
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Agira Hall'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget);
    expect(find.text('steps'), findsNWidgets(3));
    expect(_bar(tester, 0), 1.0);
    expect(_bar(tester, 1), 0.5);
    expect(_bar(tester, 2), 0.0);
    expect(tester.takeException(), isNull, reason: 'long names do not overflow at 360 px');
  });

  testWidgets('progressBase overrides the leader (e.g. the daily goal) and clamps at 100%',
      (tester) async {
    await tester.pumpWidget(_host(const LeaderboardList(entries: _entries, progressBase: 20000)));
    expect(_bar(tester, 0), 0.5);
    expect(_bar(tester, 1), 0.25);
    await tester.pumpWidget(_host(const LeaderboardList(entries: _entries, progressBase: 4000)));
    expect(_bar(tester, 0), 1.0);
    expect(_bar(tester, 1), 1.0);
  });

  testWidgets('highlights only my row', (tester) async {
    await tester.pumpWidget(_host(LeaderboardList(
      entries: _entries,
      isMine: (e) => e.id == 'b',
    )));
    expect(find.text('You'), findsOneWidget);
    final card = tester.widget<AppCard>(find.ancestor(
      of: find.text('Bhavya Singh'),
      matching: find.byType(AppCard),
    ));
    expect(card.color, AppColors.mint);
    final other = tester.widget<AppCard>(find.ancestor(
      of: find.text('Asha Rao'),
      matching: find.byType(AppCard),
    ));
    expect(other.color, isNull);
  });

  testWidgets('hostel rows emphasise the ranking metric', (tester) async {
    const hostel = [
      LeaderboardEntry(
        rank: 1,
        id: 'vyom',
        name: 'Vyom Hall',
        value: 4200,
        participants: 1,
        total: 4200,
        average: 4200,
        isHostel: true,
      ),
    ];
    await tester.pumpWidget(_host(const LeaderboardList(entries: hostel)));
    expect(find.text('1 participant · Total 4,200 · Avg 4,200'), findsOneWidget);
    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
    expect(find.byType(AvatarCircle), findsNothing);

    FontWeight? weightOf(String start) {
      final rich = tester.widget<RichText>(find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('1 participant'),
      ));
      FontWeight? found;
      rich.text.visitChildren((s) {
        if (s is TextSpan && (s.text ?? '').startsWith(start)) found = s.style?.fontWeight;
        return true;
      });
      return found;
    }

    expect(weightOf('Avg'), FontWeight.w800, reason: 'average is the ranking metric');
    expect(weightOf('Total'), isNot(FontWeight.w800));

    await tester.pumpWidget(_host(const LeaderboardList(
      entries: hostel,
      hostelMetric: HostelMetric.total,
    )));
    expect(weightOf('Total'), FontWeight.w800, reason: 'total is the ranking metric');
    expect(weightOf('Avg'), isNot(FontWeight.w800));
    expect(find.text('total steps'), findsOneWidget);
  });

  testWidgets('hostel row tolerates missing optional figures', (tester) async {
    const hostel = [
      LeaderboardEntry(rank: 1, id: 'vyom', name: 'Vyom Hall', value: 4200, isHostel: true),
    ];
    await tester.pumpWidget(_host(const LeaderboardList(entries: hostel)));
    expect(find.text('Avg 4,200'), findsOneWidget, reason: 'falls back to the ranking value');
    await tester.pumpWidget(_host(const LeaderboardList(
      entries: hostel,
      hostelMetric: HostelMetric.total,
    )));
    expect(find.text('Total 4,200'), findsOneWidget);
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(_host(const LeaderboardList(entries: [])));
    expect(find.byType(LeaderboardRow), findsNothing);
  });
}
