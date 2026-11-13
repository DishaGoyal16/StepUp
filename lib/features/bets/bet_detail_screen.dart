import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/bets/bet_models.dart';
import '../../domain/day_key.dart';
import '../auth/session_controller.dart';
import 'bet_rules.dart';
import 'bet_widgets.dart';
import 'bets_environment.dart';
import 'bets_view_models.dart';

/// `/bets/:id` - one bet: participants, verified progress, countdown, the
/// actions that apply to me, and the server-decided result.
class BetDetailScreen extends StatefulWidget {
  const BetDetailScreen({super.key, required this.betId});

  final String betId;

  @override
  State<BetDetailScreen> createState() => _BetDetailScreenState();
}

class _BetDetailScreenState extends State<BetDetailScreen> {
  BetDetailViewModel? _vm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vm != null) return;
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    _vm = BetDetailViewModel(
      betId: widget.betId,
      myUid: uid,
      repository: context.read<BetsEnvironment>().repository,
      clock: context.read<AppDependencies>().clock,
    )..start();
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool showNotice = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              if (showNotice) ...[
                const SizedBox(height: 12),
                const VirtualPointsNotice(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _accept(BetDetailViewModel vm, StepBet bet) async {
    final ok = await _confirm(
      title: 'Accept this bet?',
      body: BetText.reserveNotice(bet.stakePoints),
      confirmLabel: 'Accept',
      showNotice: true,
    );
    if (!ok || !mounted) return;
    if (await vm.accept() && mounted) {
      _snack('Bet accepted. It starts at the next midnight (IST).');
    }
  }

  Future<void> _decline(BetDetailViewModel vm, StepBet bet) async {
    final ok = await _confirm(
      title: 'Decline this bet?',
      body: '${bet.challengerName}\'s stake will be released. Nothing is taken from you.',
      confirmLabel: 'Decline',
    );
    if (!ok || !mounted) return;
    if (await vm.decline() && mounted) _snack('Bet declined.');
  }

  Future<void> _cancel(BetDetailViewModel vm, StepBet bet) async {
    final ok = await _confirm(
      title: 'Cancel this bet?',
      body: 'Your reserved stake of ${pointsLabel(bet.stakePoints)} will be released back to you.',
      confirmLabel: 'Cancel bet',
    );
    if (!ok || !mounted) return;
    if (await vm.cancel() && mounted) _snack('Bet cancelled. Your stake was released.');
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    return Scaffold(
      appBar: AppBar(leading: const BetsBackButton(), title: const Text('Bet details')),
      body: SafeArea(
        child: vm == null
            ? const LoadingState()
            : ListenableBuilder(
                listenable: vm,
                builder: (context, _) {
                  if (vm.hasError) {
                    return ErrorState(
                      message: 'Could not load this bet. It may not be one of yours.',
                      onRetry: vm.start,
                    );
                  }
                  if (vm.loading) return const LoadingState();
                  final bet = vm.bet;
                  if (bet == null) {
                    return const EmptyState(
                      icon: Icons.search_off,
                      title: 'Bet not found',
                      message: 'This bet does not exist or is not one of yours.',
                    );
                  }
                  return _content(context, vm, bet);
                },
              ),
      ),
    );
  }

  Widget _content(BuildContext context, BetDetailViewModel vm, StepBet bet) {
    final me = vm.myUid;
    final other = bet.otherUid(me);
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Participants
        AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Person(name: 'You', fullName: bet.nameOf(me)),
                  Text('vs', style: t.titleMedium?.copyWith(color: AppColors.textMuted)),
                  _Person(name: bet.nameOf(other), fullName: bet.nameOf(other)),
                ],
              ),
              const SizedBox(height: 12),
              BetStatusChip(status: bet.status),
              Ticking(
                builder: (context) {
                  final c = BetText.countdown(bet, vm.now);
                  if (c == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 18, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            c,
                            key: const Key('countdown'),
                            style: t.bodyMedium
                                ?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Terms
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The bet', style: t.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Target',
                      value: formatInt(bet.targetSteps),
                      caption: 'verified steps',
                      icon: Icons.directions_walk,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Duration',
                      value: BetText.durationDays(bet.durationDays),
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Stake (each)',
                      value: formatInt(bet.stakePoints),
                      caption: 'virtual points',
                      icon: Icons.stars_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Winner gets',
                      value: formatInt(bet.potPoints),
                      caption: 'virtual points',
                      icon: Icons.emoji_events_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._dates(context, bet),
            ],
          ),
        ),
        // Progress
        if (bet.status == BetStatus.active || bet.status == BetStatus.completed) ...[
          const SizedBox(height: 12),
          AppCard(
            key: const Key('progress-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verified steps', style: t.titleMedium),
                const SizedBox(height: 12),
                StepProgressRow(
                  name: 'You',
                  steps: bet.stepsOf(me),
                  target: bet.targetSteps,
                  highlight: true,
                ),
                const SizedBox(height: 12),
                StepProgressRow(
                  name: bet.nameOf(other),
                  steps: bet.stepsOf(other),
                  target: bet.targetSteps,
                ),
              ],
            ),
          ),
        ],
        // Result
        if (bet.status == BetStatus.completed) ...[
          const SizedBox(height: 12),
          _ResultPanel(bet: bet, me: me),
        ],
        // Closed without play
        if (bet.status.closedWithoutPlay) ...[
          const SizedBox(height: 12),
          AppCard(
            key: const Key('closed-panel'),
            child: Text(BetText.closedExplanation(bet, me)),
          ),
        ],
        // Actions
        if (bet.status == BetStatus.pending) ...[
          const SizedBox(height: 12),
          _actions(context, vm, bet),
        ],
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How the winner is decided', style: t.titleMedium),
              const SizedBox(height: 8),
              for (final line in BetText.winnerRule)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(line, style: t.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const VirtualPointsNotice(compact: true),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _dates(BuildContext context, StepBet bet) {
    String day(DateTime d) => DayKey.label(DayKey.of(d));
    final rows = <(String, String)>[
      if (bet.createdAt != null) ('Created', day(bet.createdAt!)),
      if (bet.status == BetStatus.pending && bet.expiresAt != null)
        ('Answer by', '${day(bet.expiresAt!)} (${BetLimits.expiryHours} hours)'),
      if (bet.startAt != null) ('Starts', '${day(bet.startAt!)}, midnight IST'),
      if (bet.lastDayInstant != null) ('Last day', day(bet.lastDayInstant!)),
      if (bet.settledAt != null) ('Settled', day(bet.settledAt!)),
    ];
    final t = Theme.of(context).textTheme;
    return [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(r.$1, style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ),
              Expanded(child: Text(r.$2, style: t.bodyMedium)),
            ],
          ),
        ),
    ];
  }

  Widget _actions(BuildContext context, BetDetailViewModel vm, StepBet bet) {
    final t = Theme.of(context).textTheme;
    if (vm.isOpponent) {
      return AppCard(
        key: const Key('respond-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${bet.challengerName} challenged you', style: t.titleMedium),
            const SizedBox(height: 8),
            const VirtualPointsNotice(),
            const SizedBox(height: 8),
            Text(BetText.reserveNotice(bet.stakePoints)),
            Text(BetText.startRule, style: t.bodyMedium),
            if (vm.inviteExpired) ...[
              const SizedBox(height: 8),
              Text(
                'This invite is past its ${BetLimits.expiryHours} hour limit and can no longer be accepted.',
                style: t.bodyMedium?.copyWith(color: AppColors.error),
              ),
            ] else if (vm.insufficientToAccept) ...[
              const SizedBox(height: 8),
              Text(
                'You need ${pointsLabel(bet.stakePoints)} available to accept, but you have '
                '${pointsLabel(vm.points!.available)}.',
                key: const Key('insufficient-note'),
                style: t.bodyMedium?.copyWith(color: AppColors.error),
              ),
            ],
            if (vm.actionError != null) ...[
              const SizedBox(height: 8),
              Text(vm.actionError!,
                  key: const Key('action-error'),
                  style: t.bodyMedium?.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Accept bet',
              icon: Icons.check,
              loading: vm.busy,
              onPressed: vm.canAccept ? () => _accept(vm, bet) : null,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Decline',
              onPressed: vm.canRespond ? () => _decline(vm, bet) : null,
            ),
          ],
        ),
      );
    }
    return AppCard(
      key: const Key('cancel-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Waiting for ${bet.opponentName}', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Your stake of ${pointsLabel(bet.stakePoints)} is reserved. ${BetText.expiry}',
          ),
          if (vm.actionError != null) ...[
            const SizedBox(height: 8),
            Text(vm.actionError!,
                key: const Key('action-error'),
                style: t.bodyMedium?.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Cancel bet',
            icon: Icons.close,
            onPressed: vm.canCancel ? () => _cancel(vm, bet) : null,
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.name, required this.fullName});

  final String name;
  final String fullName;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          AvatarCircle(name: fullName.isEmpty ? name : fullName, radius: 30),
          const SizedBox(height: 6),
          SizedBox(
            width: 110,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

/// Result of a COMPLETED bet, from the server fields `winnerUid` and
/// `resolution` only.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.bet, required this.me});

  final StepBet bet;
  final String me;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final won = bet.winnerUid == me;
    final moved = BetText.pointsMoved(bet, me);
    return AppCard(
      key: const Key('result-panel'),
      color: won ? AppColors.mint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bet.isRefund ? Icons.handshake_outlined : Icons.emoji_events,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  BetText.resultHeadline(bet, me),
                  key: const Key('result-headline'),
                  style: t.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(BetText.resolution(bet, me), key: const Key('result-reason')),
          if (moved.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(moved, key: const Key('result-points'), style: t.titleSmall),
          ],
        ],
      ),
    );
  }
}
