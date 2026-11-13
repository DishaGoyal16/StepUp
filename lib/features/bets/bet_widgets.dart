import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/bets/bet_models.dart';
import '../../domain/day_key.dart';
import 'bet_rules.dart';

/// Where the feature's extra full-screen routes live (not in `AppRoutes`).
abstract final class BetsPaths {
  static const String ledger = '/bets/ledger';

  /// `/bets/new`, optionally with a preselected buddy.
  static String create({String? buddyUid}) => buddyUid == null || buddyUid.isEmpty
      ? AppRoutes.betsCreate
      : '${AppRoutes.betsCreate}?buddy=${Uri.encodeQueryComponent(buddyUid)}';
}

/// Back arrow that also works when the screen was opened with `context.go`.
class BetsBackButton extends StatelessWidget {
  const BetsBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
      );
}

/// The mandatory "virtual points only" notice.
class VirtualPointsNotice extends StatelessWidget {
  const VirtualPointsNotice({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('virtual-points-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              compact ? BetText.virtualPointsShort : BetText.virtualPointsNotice,
              style: t.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured pill with the bet status.
class BetStatusChip extends StatelessWidget {
  const BetStatusChip({super.key, required this.status});

  final BetStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      BetStatus.pending => (const Color(0xFFFFF3D6), AppColors.warning),
      BetStatus.active => (AppColors.mint, AppColors.primary),
      BetStatus.completed => (AppColors.primary, Colors.white),
      _ => (AppColors.grey, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "Name  3,200 / 10,000 steps" with a progress bar. Verified steps only.
class StepProgressRow extends StatelessWidget {
  const StepProgressRow({
    super.key,
    required this.name,
    required this.steps,
    required this.target,
    this.photoUrl,
    this.highlight = false,
  });

  final String name;
  final int steps;
  final int target;
  final String? photoUrl;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = target <= 0 ? 0.0 : (steps / target).clamp(0.0, 1.0);
    final pct = (p * 100).floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: t.titleSmall?.copyWith(fontWeight: highlight ? FontWeight.w700 : null),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${formatInt(steps)} / ${formatInt(target)} steps',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label: '$name: $pct percent of the target',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 10,
              backgroundColor: AppColors.mint,
              color: highlight ? AppColors.primary : AppColors.secondary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$pct% of target (verified steps)',
          style: t.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// A bet in the list.
class BetCard extends StatelessWidget {
  const BetCard({super.key, required this.bet, required this.myUid, required this.now, this.onTap});

  final StepBet bet;
  final String myUid;
  final DateTime now;
  final VoidCallback? onTap;

  static String _day(DateTime d) => DayKey.label(DayKey.of(d));

  String _dates() {
    switch (bet.status) {
      case BetStatus.pending:
        final c = bet.createdAt;
        return c == null ? 'Waiting for an answer' : 'Created ${_day(c)}';
      case BetStatus.active:
        final s = bet.startAt;
        final e = bet.lastDayInstant;
        if (s == null || e == null) return 'Starting soon';
        return '${_day(s)} to ${_day(e)}';
      case BetStatus.completed:
        final s = bet.settledAt;
        return s == null ? 'Completed' : 'Settled ${_day(s)}';
      default:
        final s = bet.settledAt ?? bet.respondedAt ?? bet.createdAt;
        return s == null ? bet.status.label : '${bet.status.label} ${_day(s)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final other = bet.otherNameOf(myUid);
    final incoming = bet.isOpponent(myUid);
    final countdown = BetText.countdown(bet, now);
    return Semantics(
      label: 'Bet with $other, ${bet.status.label}',
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarCircle(name: other, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(other, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                      Text(
                        incoming ? 'Challenged you' : 'You challenged them',
                        style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                BetStatusChip(status: bet.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Fact(Icons.directions_walk, '${formatInt(bet.targetSteps)} steps'),
                _Fact(Icons.calendar_month_outlined, BetText.durationDays(bet.durationDays)),
                _Fact(Icons.stars_rounded, pointsLabel(bet.stakePoints)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_dates(), style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
            if (countdown != null)
              Text(countdown,
                  style: t.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
            if (bet.status == BetStatus.active) ...[
              const SizedBox(height: 12),
              StepProgressRow(
                name: 'You',
                steps: bet.stepsOf(myUid),
                target: bet.targetSteps,
                highlight: true,
              ),
              const SizedBox(height: 8),
              StepProgressRow(
                name: other,
                steps: bet.stepsOf(bet.otherUid(myUid)),
                target: bet.targetSteps,
              ),
            ],
            if (bet.status == BetStatus.completed) ...[
              const SizedBox(height: 8),
              Text(
                BetText.resultHeadline(bet, myUid),
                style: t.titleSmall?.copyWith(color: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
}

/// Text that re-evaluates [builder] every [interval] (live countdowns).
class Ticking extends StatefulWidget {
  const Ticking({
    super.key,
    required this.builder,
    this.interval = const Duration(seconds: 30),
  });

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
