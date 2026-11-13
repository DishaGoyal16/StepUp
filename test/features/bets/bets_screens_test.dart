import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/features/bets/bet_widgets.dart';
import 'package:stepup/features/bets/bets_environment.dart';
import 'package:stepup/features/bets/points_summary_card.dart';

import '../../support/harness.dart';
import 'bets_support.dart';

const _riya = BuddySummary(uid: kBuddy, displayName: 'Riya Verma');
const _kabir = BuddySummary(uid: 'buddy2', displayName: 'Kabir Singh');

Future<void> settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class Boot {
  Boot(this.h)
      : uid = h.user!.uid,
        env = BetsEnvironment.of(h.deps);

  final Harness h;
  final String uid;
  final BetsEnvironment env;

  /// A bet I created (I am the challenger).
  StepBet mine({
    String id = 'bet1',
    BetStatus status = BetStatus.pending,
    int stake = 50,
    int target = 10000,
    int days = 7,
    String? winnerUid,
    BetResolution? resolution,
    int mySteps = 0,
    int theirSteps = 0,
    DateTime? expiresAt,
  }) =>
      _bet(
        id: id,
        challenger: uid,
        opponent: kBuddy,
        challengerName: 'Aarav Sharma',
        opponentName: 'Riya Verma',
        status: status,
        stake: stake,
        target: target,
        days: days,
        winnerUid: winnerUid,
        resolution: resolution,
        cSteps: mySteps,
        oSteps: theirSteps,
        expiresAt: expiresAt,
      );

  /// A bet someone else created for me (I am the opponent).
  StepBet incoming({
    String id = 'inv1',
    BetStatus status = BetStatus.pending,
    int stake = 50,
    int target = 10000,
    int days = 7,
    String? winnerUid,
    BetResolution? resolution,
    int mySteps = 0,
    int theirSteps = 0,
    DateTime? expiresAt,
  }) =>
      _bet(
        id: id,
        challenger: kBuddy,
        opponent: uid,
        challengerName: 'Riya Verma',
        opponentName: 'Aarav Sharma',
        status: status,
        stake: stake,
        target: target,
        days: days,
        winnerUid: winnerUid,
        resolution: resolution,
        cSteps: theirSteps,
        oSteps: mySteps,
        expiresAt: expiresAt,
      );

  StepBet _bet({
    required String id,
    required String challenger,
    required String opponent,
    required String challengerName,
    required String opponentName,
    required BetStatus status,
    required int stake,
    required int target,
    required int days,
    String? winnerUid,
    BetResolution? resolution,
    required int cSteps,
    required int oSteps,
    DateTime? expiresAt,
  }) {
    final start = DateTime.utc(2026, 11, 11, 18, 30); // Thu 12 Nov 00:00 IST
    final started = status == BetStatus.active || status == BetStatus.completed;
    return makeBet(
      id: id,
      challengerUid: challenger,
      opponentUid: opponent,
      challengerName: challengerName,
      opponentName: opponentName,
      status: status,
      stake: stake,
      target: target,
      days: days,
      startAt: started ? start : null,
      endAt: started ? start.add(Duration(days: days)) : null,
      challengerSteps: cSteps,
      opponentSteps: oSteps,
      winnerUid: winnerUid,
      resolution: resolution,
      settledAt: status == BetStatus.completed ? DateTime.utc(2026, 11, 13, 1) : null,
      expiresAt: expiresAt,
    );
  }

  void points({int available = 500, int reserved = 50}) =>
      h.firestore.setProfile(profileWithPoints(uid, available: available, reserved: reserved));
}

Future<Boot> boot(
  WidgetTester tester, {
  required String location,
  List<StepBet> Function(Boot)? bets,
  List<BuddySummary> buddies = const [],
  int available = 500,
  int reserved = 50,
  List<LedgerEntry> ledgerEntries = const [],
}) async {
  useTallView(tester);
  final h = Harness.create(signedIn: true, withProfile: true);
  final b = Boot(h)..points(available: available, reserved: reserved);
  if (bets != null) b.env.fakeSource!.setBets(bets(b));
  b.env.fakeBuddies!.setBuddies(buddies);
  b.env.fakeSource!.setLedger(ledgerEntries);
  await h.pumpApp(tester, initialLocation: location);
  await settle(tester);
  return b;
}

Future<void> tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await settle(tester);
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('Bets list /bets', () {
    testWidgets('shows points, virtual-points notice, segments and an incoming invite first',
        (tester) async {
      final b = await boot(
        tester,
        location: '/bets',
        available: 420,
        reserved: 80,
        bets: (b) => [
          b.incoming(),
          b.mine(id: 'act', status: BetStatus.active, mySteps: 4200, theirSteps: 6100),
        ],
      );
      expect(find.text('Step bets'), findsOneWidget);
      expect(find.byKey(const Key('points-available')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('points-available'))).data, '420');
      expect(tester.widget<Text>(find.byKey(const Key('points-reserved'))).data, '80');
      expect(find.byKey(const Key('virtual-points-notice')), findsOneWidget);
      expect(find.textContaining('Virtual points only'), findsOneWidget);
      for (final label in ['Pending (1)', 'Active (1)', 'Completed', 'Cancelled/Declined/Expired', 'History (2)']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // default segment = Pending because an invite awaits me
      expect(find.text('Riya Verma'), findsOneWidget);
      expect(find.text('Challenged you'), findsOneWidget);
      expect(find.text('10,000 steps'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('50 points'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget, reason: 'status chip');
      expect(b.uid, isNotEmpty);
      await finish(tester);
    });

    testWidgets('active card shows both participants\' verified progress', (tester) async {
      await boot(
        tester,
        location: '/bets',
        bets: (b) => [b.mine(id: 'act', status: BetStatus.active, mySteps: 4200, theirSteps: 6100)],
      );
      expect(find.text('Active'), findsWidgets);
      expect(find.text('4,200 / 10,000 steps'), findsOneWidget);
      expect(find.text('6,100 / 10,000 steps'), findsOneWidget);
      expect(find.text('42% of target (verified steps)'), findsOneWidget);
      expect(find.text('You challenged them'), findsOneWidget);
      expect(find.textContaining('Fri 13 Nov'), findsNothing, reason: 'window is 12 Nov to 18 Nov');
      expect(find.text('Thu 12 Nov to Wed 18 Nov'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('segments filter and show empty states', (tester) async {
      await boot(
        tester,
        location: '/bets',
        bets: (b) => [
          b.mine(id: 'act', status: BetStatus.active),
          b.mine(id: 'done', status: BetStatus.completed, winnerUid: b.uid, resolution: BetResolution.higherSteps, mySteps: 12000, theirSteps: 11000),
          b.mine(id: 'dec', status: BetStatus.declined),
          b.mine(id: 'exp', status: BetStatus.expired),
        ],
      );
      await tapChip(tester, 'Completed (1)');
      expect(find.text('You won!'), findsOneWidget);
      await tapChip(tester, 'Cancelled/Declined/Expired (2)');
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      await tapChip(tester, 'Pending');
      expect(find.text('No pending bets'), findsOneWidget);
      expect(find.text('Create a bet'), findsOneWidget);
      await tapChip(tester, 'History (4)');
      expect(find.byType(BetCard), findsNWidgets(4));
      await finish(tester);
    });

    testWidgets('empty state when I have no bets at all', (tester) async {
      await boot(tester, location: '/bets');
      expect(find.text('No active bets'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('stream error shows a retry that recovers', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      final b = Boot(h);
      b.env.fakeSource!.streamError = const AppException(code: 'unavailable', message: 'x');
      await h.pumpApp(tester, initialLocation: '/bets');
      await settle(tester);
      expect(find.text('Could not load your bets.'), findsOneWidget);
      b.env.fakeSource!
        ..streamError = null
        ..setBets([b.mine(status: BetStatus.active)]);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Could not load your bets.'), findsNothing);
      expect(find.byType(BetCard), findsOneWidget);
      await finish(tester);
    });

    testWidgets('tapping a card opens the detail; the app bar opens the ledger', (tester) async {
      await boot(tester, location: '/bets', bets: (b) => [b.incoming()]);
      await tester.tap(find.text('Riya Verma'));
      await settle(tester);
      expect(find.text('Bet details'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.byTooltip('Points ledger'));
      await settle(tester);
      expect(find.text('Points ledger'), findsWidgets);
      await finish(tester);
    });

    testWidgets('New bet button opens the create screen', (tester) async {
      await boot(tester, location: '/bets');
      await tester.tap(find.text('New bet'));
      await settle(tester);
      expect(find.text('Create step bet'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Create bet /bets/new', () {
    testWidgets('shows the virtual-points notice, rules and expiry', (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya, _kabir]);
      expect(find.byKey(const Key('virtual-points-notice')), findsOneWidget);
      expect(find.textContaining('VIRTUAL POINTS ONLY'), findsOneWidget);
      expect(find.textContaining('No real money'), findsOneWidget);
      expect(find.textContaining('higher number of verified steps'), findsOneWidget);
      expect(find.textContaining('tie refunds both stakes'), findsOneWidget);
      expect(find.textContaining('only one of you'), findsOneWidget);
      expect(find.textContaining('If nobody reaches'), findsOneWidget);
      expect(find.textContaining('48 hours'), findsOneWidget);
      expect(find.textContaining('next midnight (IST)'), findsOneWidget);
      expect(find.text('Sat 14 Nov to Fri 20 Nov'), findsNothing);
      expect(find.textContaining('Sat 14 Nov to Fri 20 Nov (IST)'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('without buddies it explains and offers to find buddies', (tester) async {
      await boot(tester, location: '/bets/new');
      expect(find.text('You need an accepted buddy first'), findsOneWidget);
      expect(find.text('Find buddies'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await finish(tester);
    });

    testWidgets('send button needs a buddy; choosing one enables it and updates the preview',
        (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya, _kabir], available: 500);
      FilledButton send() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge'));
      expect(send().onPressed, isNull);
      await tester.tap(find.byKey(const Key('buddy-buddy1')));
      await settle(tester);
      expect(send().onPressed, isNotNull);
      final summary = find.byKey(const Key('bet-summary'));
      expect(find.descendant(of: summary, matching: find.text('50')), findsOneWidget, reason: 'reserved now');
      expect(find.descendant(of: summary, matching: find.text('450')), findsOneWidget, reason: 'available after');
      await tester.enterText(find.byKey(const Key('stake-field')), '200');
      await settle(tester);
      expect(find.descendant(of: summary, matching: find.text('300')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('stake above available points is rejected inline and disables send', (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya], available: 100);
      await tester.tap(find.byKey(const Key('buddy-buddy1')));
      await tester.enterText(find.byKey(const Key('stake-field')), '150');
      await settle(tester);
      expect(find.text('You only have 100 points available.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge')).onPressed, isNull);
      await finish(tester);
    });

    testWidgets('invalid target and stake show errors', (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya], available: 5000);
      await tester.tap(find.byKey(const Key('buddy-buddy1')));
      await tester.enterText(find.byKey(const Key('target-field')), '500');
      await tester.enterText(find.byKey(const Key('stake-field')), '5');
      await settle(tester);
      expect(find.textContaining('at least 1,000 steps'), findsOneWidget);
      expect(find.textContaining('between 10 and 1,000 points'), findsWidgets);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge')).onPressed, isNull);
      await finish(tester);
    });

    testWidgets('duration slider changes the label', (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya]);
      expect(find.text('7 days'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byKey(const Key('duration-slider')));
      expect(slider.min, 1);
      expect(slider.max, 30);
      slider.onChanged!(3);
      await settle(tester);
      expect(find.text('3 days'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('?buddy= preselects that buddy', (tester) async {
      await boot(tester, location: '/bets/new?buddy=buddy2', buddies: [_riya, _kabir]);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge')).onPressed, isNotNull);
      await finish(tester);
    });

    testWidgets('?buddy= of a non-buddy shows a warning', (tester) async {
      await boot(tester, location: '/bets/new?buddy=stranger', buddies: [_riya]);
      expect(find.textContaining('not one of your accepted buddies'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge')).onPressed, isNull);
      await finish(tester);
    });

    testWidgets('submitting calls createStepBet once with the form values and opens the new bet', (tester) async {
      final b = await boot(tester, location: '/bets/new', buddies: [_riya, _kabir], available: 500);
      b.h.functions.on('createStepBet', (p) {
        b.env.fakeSource!.upsertBet(b.mine(id: 'created1', stake: 75, target: 12000, days: 3));
        return {'betId': 'created1', 'duplicate': false};
      });
      await tester.tap(find.byKey(const Key('buddy-buddy2')));
      await tester.enterText(find.byKey(const Key('target-field')), '12000');
      await tester.enterText(find.byKey(const Key('stake-field')), '75');
      (tester.widget<Slider>(find.byKey(const Key('duration-slider')))).onChanged!(3);
      await settle(tester);
      final button = find.widgetWithText(FilledButton, 'Send challenge');
      await tester.tap(button);
      await settle(tester);
      final calls = b.h.functions.callsTo('createStepBet').toList();
      expect(calls, hasLength(1));
      expect(calls.single.params['opponentUid'], 'buddy2');
      expect(calls.single.params['targetSteps'], 12000);
      expect(calls.single.params['durationDays'], 3);
      expect(calls.single.params['stakePoints'], 75);
      expect(find.text('Bet details'), findsOneWidget);
      expect(find.text('Waiting for Riya Verma'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('server error (insufficient points) is shown friendly and the form stays', (tester) async {
      final b = await boot(tester, location: '/bets/new', buddies: [_riya], available: 500);
      b.h.functions.failNext(
        'createStepBet',
        AppException.fromCallable(
            code: 'failed-precondition',
            message: 'not enough points',
            details: {'reason': 'INSUFFICIENT_POINTS'}),
      );
      await tester.tap(find.byKey(const Key('buddy-buddy1')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send challenge'));
      await settle(tester);
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      expect(find.text('You do not have enough available points for this stake.'), findsOneWidget);
      expect(find.text('Create step bet'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send challenge')).onPressed, isNotNull);
      await finish(tester);
    });

    testWidgets('not-a-buddy error is friendly', (tester) async {
      final b = await boot(tester, location: '/bets/new', buddies: [_riya]);
      b.h.functions.failNext(
        'createStepBet',
        AppException.fromCallable(code: 'failed-precondition', details: {'reason': 'NOT_BUDDIES'}),
      );
      await tester.tap(find.byKey(const Key('buddy-buddy1')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send challenge'));
      await settle(tester);
      expect(find.text('You can only bet with an accepted buddy.'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Bet detail /bets/:id', () {
    testWidgets('incoming pending bet: notice, terms, accept confirms then calls respondStepBet',
        (tester) async {
      final b = await boot(
        tester,
        location: '/bets/inv1',
        bets: (b) => [b.incoming(stake: 80, target: 15000, days: 5)],
        available: 500,
      );
      b.h.functions.on('respondStepBet', (p) => {'ok': true});
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Riya Verma'), findsWidgets);
      expect(find.text('Riya Verma challenged you'), findsOneWidget);
      expect(find.byKey(const Key('virtual-points-notice')), findsWidgets);
      expect(find.text('15,000'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
      expect(find.text('160'), findsOneWidget, reason: 'winner gets both stakes');
      expect(find.byKey(const Key('countdown')), findsOneWidget);
      expect(find.text('Expires in 1d 22h'), findsOneWidget);
      expect(find.byKey(const Key('respond-panel')), findsOneWidget);
      expect(find.text('Cancel bet'), findsNothing);

      await tester.tap(find.text('Accept bet'));
      await settle(tester);
      expect(find.text('Accept this bet?'), findsOneWidget);
      expect(find.textContaining('reserves 80 points'), findsWidgets);
      expect(find.textContaining('VIRTUAL POINTS ONLY'), findsWidgets);
      expect(b.h.functions.callsTo('respondStepBet'), isEmpty, reason: 'nothing sent before confirming');
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await settle(tester);
      final call = b.h.functions.callsTo('respondStepBet').single;
      expect(call.params, {'betId': 'inv1', 'accept': true});
      expect(find.textContaining('Bet accepted'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('"Not now" in the confirm dialog sends nothing', (tester) async {
      final b = await boot(tester, location: '/bets/inv1', bets: (b) => [b.incoming()]);
      await tester.tap(find.text('Accept bet'));
      await settle(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(b.h.functions.callsTo('respondStepBet'), isEmpty);
      expect(b.h.functions.callsTo('cancelStepBet'), isEmpty);
      await finish(tester);
    });

    testWidgets('decline calls respondStepBet(accept:false)', (tester) async {
      final b = await boot(tester, location: '/bets/inv1', bets: (b) => [b.incoming()]);
      b.h.functions.on('respondStepBet', (p) => {'ok': true});
      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await settle(tester);
      expect(b.h.functions.callsTo('respondStepBet').single.params, {'betId': 'inv1', 'accept': false});
      await finish(tester);
    });

    testWidgets('accept is disabled when I do not have enough available points', (tester) async {
      await boot(
        tester,
        location: '/bets/inv1',
        bets: (b) => [b.incoming(stake: 300)],
        available: 120,
      );
      expect(find.byKey(const Key('insufficient-note')), findsOneWidget);
      expect(find.textContaining('You need 300 points available'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept bet')).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Decline')).onPressed, isNotNull);
      await finish(tester);
    });

    testWidgets('server rejection on accept (expired) is shown as friendly text', (tester) async {
      final b = await boot(tester, location: '/bets/inv1', bets: (b) => [b.incoming()]);
      b.h.functions.failNext(
        'respondStepBet',
        AppException.fromCallable(code: 'failed-precondition', details: {'reason': 'BET_EXPIRED'}),
      );
      await tester.tap(find.text('Accept bet'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await settle(tester);
      expect(find.byKey(const Key('action-error')), findsOneWidget);
      expect(find.textContaining('has expired'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an invite past 48 h cannot be accepted', (tester) async {
      await boot(
        tester,
        location: '/bets/inv1',
        bets: (b) => [b.incoming(expiresAt: kNow.subtract(const Duration(minutes: 5)))],
      );
      expect(find.textContaining('can no longer be accepted'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept bet')).onPressed, isNull);
      await finish(tester);
    });

    testWidgets('challenger sees Cancel while pending; cancel calls cancelStepBet', (tester) async {
      final b = await boot(tester, location: '/bets/bet1', bets: (b) => [b.mine(stake: 60)]);
      b.h.functions.on('cancelStepBet', (p) => {'ok': true});
      expect(find.byKey(const Key('cancel-panel')), findsOneWidget);
      expect(find.text('Waiting for Riya Verma'), findsOneWidget);
      expect(find.text('Accept bet'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel bet'));
      await settle(tester);
      expect(find.textContaining('stake of 60 points will be released'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel bet'));
      await settle(tester);
      expect(b.h.functions.callsTo('cancelStepBet').single.params, {'betId': 'bet1'});
      await finish(tester);
    });

    testWidgets('active bet: progress for both, countdown, no actions', (tester) async {
      await boot(
        tester,
        location: '/bets/act',
        bets: (b) => [b.mine(id: 'act', status: BetStatus.active, mySteps: 2500, theirSteps: 10000)],
      );
      expect(find.byKey(const Key('progress-card')), findsOneWidget);
      expect(find.text('2,500 / 10,000 steps'), findsOneWidget);
      expect(find.text('10,000 / 10,000 steps'), findsOneWidget);
      expect(find.text('Ends in 5d 12h'), findsOneWidget);
      expect(find.text('Accept bet'), findsNothing);
      expect(find.text('Cancel bet'), findsNothing);
      expect(find.byKey(const Key('result-panel')), findsNothing);
      await finish(tester);
    });

    testWidgets('completed: I won - result from winnerUid and resolution', (tester) async {
      await boot(
        tester,
        location: '/bets/done',
        bets: (b) => [
          b.mine(
              id: 'done',
              status: BetStatus.completed,
              stake: 100,
              winnerUid: b.uid,
              resolution: BetResolution.higherSteps,
              mySteps: 12000,
              theirSteps: 11000)
        ],
      );
      expect(tester.widget<Text>(find.byKey(const Key('result-headline'))).data, 'You won!');
      expect(find.textContaining('You had more verified steps'), findsOneWidget);
      expect(find.textContaining('You received 200 points'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('completed: opponent won because only they reached the target', (tester) async {
      await boot(
        tester,
        location: '/bets/done',
        bets: (b) => [
          b.mine(
              id: 'done',
              status: BetStatus.completed,
              stake: 100,
              winnerUid: kBuddy,
              resolution: BetResolution.onlyOneReachedTarget,
              mySteps: 3000,
              theirSteps: 10500)
        ],
      );
      expect(tester.widget<Text>(find.byKey(const Key('result-headline'))).data, 'Riya Verma won');
      expect(find.text('Only Riya Verma reached the target of 10,000 steps.'), findsOneWidget);
      expect(find.text('You lost your stake of 100 points.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('completed: refund (nobody reached / tie) is shown as a draw', (tester) async {
      await boot(
        tester,
        location: '/bets/done',
        bets: (b) => [
          b.mine(id: 'done', status: BetStatus.completed, resolution: BetResolution.refundNoneReached)
        ],
      );
      expect(tester.widget<Text>(find.byKey(const Key('result-headline'))).data, 'Draw - stakes refunded');
      expect(find.textContaining('Nobody reached the target'), findsOneWidget);
      expect(find.text('Both stakes of 50 points were returned.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('cancelled / declined / expired bets explain what happened', (tester) async {
      await boot(
        tester,
        location: '/bets/x1',
        bets: (b) => [b.mine(id: 'x1', status: BetStatus.declined)],
      );
      expect(find.byKey(const Key('closed-panel')), findsOneWidget);
      expect(find.textContaining('Riya Verma declined this bet'), findsOneWidget);
      expect(find.text('Accept bet'), findsNothing);
      await finish(tester);
    });

    testWidgets('unknown bet id shows not found', (tester) async {
      await boot(tester, location: '/bets/ghost');
      expect(find.text('Bet not found'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('read error (not my bet / offline) shows an error with retry', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      final b = Boot(h);
      b.env.fakeSource!.streamError = const AppException(code: 'permission-denied', message: 'x');
      await h.pumpApp(tester, initialLocation: '/bets/other');
      await settle(tester);
      expect(find.textContaining('Could not load this bet'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Ledger /bets/ledger', () {
    testWidgets('balance (available + reserved) and entries with readable text', (tester) async {
      await boot(
        tester,
        location: '/bets/ledger',
        available: 450,
        reserved: 50,
        ledgerEntries: [
          ledger('1', LedgerType.reserve,
              delta: -50, reservedDelta: 50, balanceAfter: 450, reservedAfter: 50, note: 'Stake reserved for step bet'),
          ledger('2', LedgerType.reward, refType: 'DAILY_GOAL', refId: 'd1', delta: 10, balanceAfter: 500),
          ledger('3', LedgerType.betWin, delta: 100, reservedDelta: -50, balanceAfter: 600),
        ],
      );
      expect(tester.widget<Text>(find.byKey(const Key('points-available'))).data, '450');
      expect(tester.widget<Text>(find.byKey(const Key('points-reserved'))).data, '50');
      expect(find.text('Total 500 virtual points (available + reserved in open bets).'), findsOneWidget);
      expect(find.text('Stake reserved for a step bet'), findsOneWidget);
      expect(find.text('moved to reserved'), findsOneWidget);
      expect(find.text('-50'), findsOneWidget);
      expect(find.text('Daily goal reward'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('Won a step bet'), findsOneWidget);
      expect(find.textContaining('Balance after: 450 available, 50 reserved'), findsOneWidget);
      expect(find.byKey(const Key('virtual-points-notice')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('empty ledger shows an empty state', (tester) async {
      await boot(tester, location: '/bets/ledger');
      expect(find.text('No points activity yet'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('paginates with Load more', (tester) async {
      final entries = [
        for (var i = 0; i < 35; i++)
          ledger('e$i', LedgerType.reward, refType: 'DAILY_GOAL', refId: 'd$i', delta: 10, note: 'entry $i'),
      ];
      final b = await boot(tester, location: '/bets/ledger', ledgerEntries: entries);
      expect(find.text('entry 0'), findsOneWidget);
      expect(find.text('entry 29'), findsOneWidget);
      expect(find.text('entry 30'), findsNothing);
      expect(b.env.fakeSource!.ledgerFetches, 1);
      await tester.tap(find.text('Load more'));
      await settle(tester);
      expect(find.text('entry 34'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(b.env.fakeSource!.ledgerFetches, 2);
      await finish(tester);
    });

    testWidgets('load failure shows an error and Try again recovers', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      final b = Boot(h);
      b.env.fakeSource!
        ..setLedger([ledger('1', LedgerType.adjustment, refType: 'ADMIN', delta: 25)])
        ..failNextLedger = AppException.fromCallable(code: 'unavailable');
      await h.pumpApp(tester, initialLocation: '/bets/ledger');
      await settle(tester);
      expect(find.textContaining('Network problem'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Points adjustment'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a bet-related entry opens that bet', (tester) async {
      await boot(
        tester,
        location: '/bets/ledger',
        bets: (b) => [b.mine(id: 'bet1')],
        ledgerEntries: [ledger('1', LedgerType.reserve, delta: -50, reservedDelta: 50, refId: 'bet1')],
      );
      await tester.tap(find.text('Stake reserved for a step bet'));
      await settle(tester);
      expect(find.text('Bet details'), findsOneWidget);
      await finish(tester);
    });
  });

  group('routing', () {
    testWidgets('/bets/new and /bets/ledger are not treated as bet ids', (tester) async {
      await boot(tester, location: '/bets/new', buddies: [_riya]);
      expect(find.text('Create step bet'), findsOneWidget);
      expect(find.text('Bet not found'), findsNothing);
      await finish(tester);
      await boot(tester, location: '/bets/ledger');
      expect(find.text('Points ledger'), findsWidgets);
      expect(find.text('Bet not found'), findsNothing);
      await finish(tester);
    });

    test('BetsPaths builds the create URL', () {
      expect(BetsPaths.create(), '/bets/new');
      expect(BetsPaths.create(buddyUid: 'abc'), '/bets/new?buddy=abc');
      expect(BetsPaths.ledger, '/bets/ledger');
    });
  });

  group('PointsSummaryCard', () {
    testWidgets('shows available and reserved and is tappable only with onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            PointsSummaryCard(balance: 1250, reserved: 100, onTap: () => taps++),
            const PointsSummaryCard(balance: 0, reserved: 0),
          ]),
        ),
      ));
      expect(find.text('1,250'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('available'), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.text('1,250'));
      expect(taps, 1);
    });
  });
}
