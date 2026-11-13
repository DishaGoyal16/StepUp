import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/challenges/challenge_models.dart';
import '../../data/challenges/challenge_repository.dart';
import '../auth/session_controller.dart';
import 'challenge_detail_view_model.dart';
import 'challenge_logic.dart';
import 'challenge_widgets.dart';

/// Details of one challenge: rules, dates, my live progress, join / leave,
/// leaderboard (or hostel ranking / buddy head-to-head) and the final result.
class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  Timer? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    // Keeps the countdown fresh while the screen is open.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) return const Scaffold(body: LoadingState());
    final deps = context.read<AppDependencies>();
    return ChangeNotifierProvider<ChallengeDetailViewModel>(
      key: ValueKey('${user.uid}/${widget.challengeId}'),
      create: (c) => ChallengeDetailViewModel(
        repository: c.read<ChallengeRepository>(),
        challengeId: widget.challengeId,
        uid: user.uid,
        myHostelId: session.profile?.hostelId,
        clock: deps.clock,
        loadHostels: deps.hostels.load,
        watchDailySummaries: (uid) => deps.firestore.watchDailySummaries(uid, limit: 35),
      )..start(),
      child: _DetailView(tick: _tick),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.tick});

  final int tick;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChallengeDetailViewModel>();
    final state = vm.challenge;
    return Scaffold(
      appBar: AppBar(title: const Text('Challenge')),
      body: SafeArea(
        child: state.loading
            ? const LoadingState()
            : state.error != null
                ? ErrorState(message: state.error!, onRetry: () => vm.refresh())
                : RefreshIndicator(
                    onRefresh: () => runAction(context, () => vm.refresh()),
                    child: _DetailBody(vm: vm, challenge: state.data!),
                  ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final isBuddy = c.type == ChallengeType.buddy;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _HeaderCard(vm: vm, challenge: c),
        const SizedBox(height: 12),
        const NoteBanner(
          text: 'Only verified steps count. Raw, pending or rejected steps never add to your progress.',
        ),
        if (c.type == ChallengeType.interHostel) ...[
          const SizedBox(height: 12),
          _HostelsCard(vm: vm),
        ],
        if (isBuddy && (vm.hasInviteForMe || vm.waitingForBuddy)) ...[
          const SizedBox(height: 12),
          _BuddyInviteCard(vm: vm, challenge: c),
        ],
        if (vm.myProgress != null) ...[
          const SizedBox(height: 12),
          _MyProgressCard(vm: vm, challenge: c),
        ],
        if (!isBuddy) ...[
          const SizedBox(height: 12),
          _JoinArea(vm: vm, challenge: c),
        ],
        if (isBuddy && c.status != ChallengeStatus.pending && c.status != ChallengeStatus.cancelled) ...[
          const SizedBox(height: 12),
          _BuddyVersus(vm: vm, challenge: c),
        ],
        if (c.status == ChallengeStatus.completed) ...[
          const SizedBox(height: 12),
          _ResultCard(vm: vm, challenge: c),
        ],
        if (vm.showLeaderboard && !isBuddy) ...[
          const SizedBox(height: 12),
          _LeaderboardSection(vm: vm, challenge: c),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = challenge;
    final mine = vm.mine;
    final countdown = vm.countdown;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.title, style: t.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChallengeChip(typeLabel(c.type), icon: Icons.flag_outlined),
              ChallengeChip.status(c.status),
              if (mine != null && mine.status != ParticipantStatus.left)
                ChallengeChip(
                  participantStatusLabel(mine.status),
                  background: Colors.white,
                  foreground: AppColors.primary,
                  icon: Icons.check_circle_outline,
                ),
            ],
          ),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(c.description, style: t.bodyMedium),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Text('Rules', style: t.titleMedium),
          InfoRow(icon: Icons.track_changes_outlined, text: targetText(c)),
          InfoRow(icon: Icons.event_outlined, text: scheduleText(c)),
          if (countdown != null)
            InfoRow(icon: Icons.timer_outlined, text: countdown, bold: true),
          InfoRow(
            icon: Icons.people_outline,
            text: c.maxParticipants != null && c.maxParticipants! > 0
                ? '${formatCount(c.participantCount)} of ${formatCount(c.maxParticipants!)} participants'
                : (c.participantCount == 1 ? '1 participant' : '${formatCount(c.participantCount)} participants'),
          ),
          if (c.type == ChallengeType.interHostel)
            InfoRow(icon: Icons.apartment_outlined, text: aggregationRule(c), bold: true),
          if (c.rewardPoints > 0)
            InfoRow(
              icon: Icons.stars_outlined,
              text: c.type == ChallengeType.individual
                  ? 'Completion reward: ${formatCount(c.rewardPoints)} points'
                  : 'Winner reward: ${formatCount(c.rewardPoints)} points',
            ),
        ],
      ),
    );
  }
}

class _HostelsCard extends StatelessWidget {
  const _HostelsCard({required this.vm});

  final ChallengeDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final hostels = vm.competingHostels;
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hostels competing', style: t.titleMedium),
          const SizedBox(height: 8),
          if (hostels.isEmpty)
            Text('The competing hostels have not been announced yet.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in hostels)
                  ChallengeChip(
                    h.isMine ? '${h.name} (yours)' : h.name,
                    background: h.isMine ? AppColors.primary : AppColors.mint,
                    foreground: h.isMine ? Colors.white : AppColors.text,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BuddyInviteCard extends StatelessWidget {
  const _BuddyInviteCard({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (vm.waitingForBuddy) {
      return AppCard(
        child: InfoRow(
          icon: Icons.hourglass_top_outlined,
          text: 'Waiting for your buddy to accept. The challenge starts at the next midnight (IST) after they accept.',
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You were challenged', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'If you accept, the challenge starts at the next midnight (IST).',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Decline',
                  onPressed: vm.busy ? null : () => runAction(context, () => vm.respond(accept: false)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'Accept',
                  loading: vm.busy,
                  onPressed: () => runAction(context, () => vm.respond(accept: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MyProgressCard extends StatelessWidget {
  const _MyProgressCard({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = challenge;
    final progress = vm.myProgress ?? 0;
    final done = vm.mine?.isCompleted ?? false;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('My progress', style: t.titleMedium)),
              if (done) const ChallengeChip('Completed', background: AppColors.primary, foreground: Colors.white),
            ],
          ),
          const SizedBox(height: 10),
          ChallengeProgressBar(
            fraction: progressFraction(progress, c.target),
            semanticsLabel: 'My progress',
            height: 12,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(progressText(c, progress), style: t.titleMedium)),
              Text('${vm.myPercent ?? 0}%', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Updates as your verified steps are confirmed by the server.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _JoinArea extends StatelessWidget {
  const _JoinArea({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final decision = vm.joinDecision;
    if (decision == null) return const SizedBox.shrink();
    if (decision.canJoin) {
      return PrimaryButton(
        label: 'Join challenge',
        icon: Icons.directions_walk,
        loading: vm.busy,
        onPressed: () => runAction(context, () => vm.join()),
      );
    }
    if (vm.canLeaveChallenge) {
      return SecondaryButton(
        label: 'Leave challenge',
        icon: Icons.logout,
        onPressed: vm.busy ? null : () => _confirmLeave(context),
      );
    }
    final reason = decision.reason;
    if (reason == null) return const SizedBox.shrink();
    return AppCard(
      color: AppColors.surface,
      child: InfoRow(icon: Icons.info_outline, text: reason),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this challenge?'),
        content: const Text('You will stop competing in it. You can join again while it is still open.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      runAction(context, () => vm.leave());
    }
  }
}

class _BuddyVersus extends StatelessWidget {
  const _BuddyVersus({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lb = vm.leaderboard;
    final rows = vm.buddyRows;
    final daily = vm.myDailyRows;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Head to head', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'First to ${formatCount(challenge.target)} verified steps wins. Both totals below are verified steps.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          if (lb.loading)
            const Padding(padding: EdgeInsets.all(16), child: LoadingState())
          else if (lb.error != null)
            ErrorState(message: lb.error!, onRetry: () => vm.reloadLeaderboard(), compact: true)
          else if (rows.isEmpty)
            Text('No results yet.', style: t.bodyMedium)
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: _Competitor(row: rows[i], challenge: challenge, isMe: rows[i].id == vm.uid)),
                  ],
                ],
              ),
            ),
          if (daily.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Your verified steps per day', style: t.titleSmall),
            const SizedBox(height: 4),
            for (final d in daily)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(d.label, style: t.bodyMedium)),
                    Text(formatCount(d.verified), style: t.labelLarge),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Your buddy\'s daily steps are private; only their total is shown.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Competitor extends StatelessWidget {
  const _Competitor({required this.row, required this.challenge, required this.isMe});

  final LeaderboardRow row;
  final Challenge challenge;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('competitor-${row.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.mint : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: isMe ? AppColors.primary : AppColors.grey),
      ),
      child: Column(
        children: [
          AvatarCircle(name: row.name, photoUrl: row.photoUrl, radius: 26),
          const SizedBox(height: 6),
          Text(isMe ? '${row.name} (you)' : row.name,
              style: t.labelLarge, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(formatCount(row.value), style: t.titleLarge),
          Text(metricUnit(challenge.metric), style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          ChallengeProgressBar(fraction: row.progressPct / 100, semanticsLabel: '${row.name} progress'),
          const SizedBox(height: 4),
          Text('${row.progressPct}% of target', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = vm.result;
    final session = context.read<SessionController>();
    return AppCard(
      color: AppColors.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Final result', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (r == null)
            Text(
              vm.resultError ?? 'The final result is being prepared. Pull down to refresh.',
              style: t.bodyMedium,
            )
          else ...[
            Text(
              r.hasWinner
                  ? winnerText(r, myUid: vm.uid, myHostelId: session.profile?.hostelId)
                  : (challenge.type == ChallengeType.buddy
                      ? 'No winner - nobody reached the target.'
                      : 'No winner for this challenge'),
              style: t.titleLarge,
            ),
            if (r.metricLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(r.metricLabel, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ),
            if (r.ranking.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final e in r.ranking.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      RankBadge(rank: e.rank, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.name,
                          style: (e.uid != null && e.uid == vm.uid) || (e.hostelId != null && e.hostelId == vm.myHostelId)
                              ? t.labelLarge?.copyWith(fontWeight: FontWeight.w800)
                              : t.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(valueText(challenge, e.value), style: t.labelLarge),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LeaderboardSection extends StatelessWidget {
  const _LeaderboardSection({required this.vm, required this.challenge});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isHostel = challenge.type == ChallengeType.interHostel;
    final lb = vm.leaderboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          isHostel ? 'Hostel ranking' : 'Leaderboard',
          subtitle: lb.data?.metricLabel.isNotEmpty == true ? lb.data!.metricLabel : null,
        ),
        if (lb.loading)
          const Padding(padding: EdgeInsets.all(24), child: LoadingState())
        else if (lb.error != null)
          ErrorState(message: lb.error!, onRetry: () => vm.reloadLeaderboard(), compact: true)
        else if (lb.data!.entries.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.leaderboard_outlined,
            title: 'No ranking yet',
            message: 'Rankings appear once participants have verified steps.',
          )
        else ...[
          if (isHostel)
            HostelRankingTable(
              rows: lb.data!.entries,
              myHostelId: vm.myHostelId,
              valueLabelOf: (r) => formatCount(r.value),
            )
          else
            for (final r in lb.data!.entries)
              LeaderboardRowTile(
                row: r,
                isMe: r.id == vm.uid,
                valueLabel: valueText(challenge, r.value),
                hostelLabel: vm.hostelName(r.hostelId),
              ),
          _MyRankFooter(vm: vm, challenge: challenge, board: lb.data!, isHostel: isHostel),
        ],
        if (!lb.loading && lb.error == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Ranking is computed by the server from verified steps only.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// "Your rank" line, shown even when my row is outside the visible top list.
class _MyRankFooter extends StatelessWidget {
  const _MyRankFooter({required this.vm, required this.challenge, required this.board, required this.isHostel});

  final ChallengeDetailViewModel vm;
  final Challenge challenge;
  final ChallengeLeaderboard board;
  final bool isHostel;

  @override
  Widget build(BuildContext context) {
    final rank = board.myRank;
    if (rank == null) return const SizedBox.shrink();
    final visible = board.entries.any((r) => isHostel ? r.id == vm.myHostelId : r.id == vm.uid);
    if (visible) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AppCard(
        color: AppColors.mint,
        child: Row(
          children: [
            const Icon(Icons.person_pin_circle_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isHostel ? 'Your hostel: rank $rank' : 'Your rank: $rank',
                key: const ValueKey('my-rank'),
                style: t.titleMedium,
              ),
            ),
            Text(isHostel ? formatCount(board.myValue) : valueText(challenge, board.myValue), style: t.labelLarge),
          ],
        ),
      ),
    );
  }
}
