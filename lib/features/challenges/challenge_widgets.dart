import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/challenges/challenge_models.dart';
import 'action_result.dart';
import 'challenge_logic.dart';

/// Shows the message of an [ActionResult] (if any) in a snackbar.
void showResult(BuildContext context, ActionResult result) {
  final message = result.message;
  if (message == null || !context.mounted) return;
  _show(ScaffoldMessenger.of(context), message);
}

void _show(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs a user action and shows its outcome in a snackbar. The messenger is
/// captured before the first `await`, so this is safe across async gaps.
Future<void> runAction(BuildContext context, Future<ActionResult> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await action();
  final message = result.message;
  if (message != null) _show(messenger, message);
}

/// Small rounded label (type, status, "Joined", ...).
class ChallengeChip extends StatelessWidget {
  const ChallengeChip(this.label, {super.key, this.background = AppColors.mint, this.foreground = AppColors.text, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  /// Colour of a challenge status chip.
  factory ChallengeChip.status(ChallengeStatus s, {Key? key}) {
    final (bg, fg) = switch (s) {
      ChallengeStatus.active => (AppColors.primary, Colors.white),
      ChallengeStatus.upcoming => (const Color(0xFFFFF1CC), const Color(0xFF6B4E00)),
      ChallengeStatus.pending => (const Color(0xFFFFF1CC), const Color(0xFF6B4E00)),
      ChallengeStatus.completed => (AppColors.grey, AppColors.text),
      ChallengeStatus.cancelled => (const Color(0xFFF8DAD6), const Color(0xFF7A1F14)),
    };
    return ChallengeChip(statusLabel(s), key: key, background: bg, foreground: fg);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Rounded progress bar with an accessible label.
class ChallengeProgressBar extends StatelessWidget {
  const ChallengeProgressBar({super.key, required this.fraction, this.semanticsLabel, this.height = 10});

  final double fraction;
  final String? semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      value: '${(fraction * 100).floor()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: AppColors.mint,
          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
        ),
      ),
    );
  }
}

/// A line with a leading icon (used for goal, dates, participants, ...).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: bold ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : t.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft informational banner.
class NoteBanner extends StatelessWidget {
  const NoteBanner({super.key, required this.text, this.icon = Icons.verified_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.button)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Discovery card of one challenge: title, type, goal, dates, status,
/// participants and - when I joined - my progress bar.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.now,
    this.mine,
    this.onTap,
    this.caption,
    this.footer,
  });

  final Challenge challenge;
  final DateTime now;

  /// My participation (only passed when joined / completed).
  final ChallengeParticipation? mine;
  final VoidCallback? onTap;

  /// Extra line, e.g. whether my hostel is competing.
  final String? caption;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = challenge;
    final countdown = countdownText(c, now, mine: mine);
    final p = mine;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(c.title, style: t.titleMedium)),
              const SizedBox(width: 8),
              ChallengeChip.status(c.status),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChallengeChip(typeLabel(c.type), icon: Icons.flag_outlined),
              if (p != null)
                ChallengeChip(
                  participantStatusLabel(p.status),
                  background: Colors.white,
                  foreground: AppColors.primary,
                  icon: Icons.check_circle_outline,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(targetText(c), style: t.bodyMedium),
          const SizedBox(height: 4),
          Text(
            scheduleText(c),
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (countdown != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(countdown, style: t.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.people_outline, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                c.participantCount == 1 ? '1 participant' : '${formatCount(c.participantCount)} participants',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              if (c.rewardPoints > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.stars_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text('${formatCount(c.rewardPoints)} points', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption!, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
          if (p != null) ...[
            const SizedBox(height: 10),
            ChallengeProgressBar(
              fraction: progressFraction(p.progress, c.target),
              semanticsLabel: 'My progress in ${c.title}',
            ),
            const SizedBox(height: 4),
            Text(
              '${progressText(c, p.progress)} - ${progressPercent(p.progress, c.target)}%',
              style: t.bodySmall,
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}

/// One row of a student ranking (rank, avatar, name, hostel, value, %).
class LeaderboardRowTile extends StatelessWidget {
  const LeaderboardRowTile({
    super.key,
    required this.row,
    required this.valueLabel,
    required this.isMe,
    this.hostelLabel,
  });

  final LeaderboardRow row;
  final String valueLabel;
  final bool isMe;
  final String? hostelLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? AppColors.mint : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: isMe ? AppColors.primary : AppColors.grey),
      ),
      child: Row(
        children: [
          RankBadge(rank: row.rank),
          const SizedBox(width: 10),
          AvatarCircle(name: row.name, photoUrl: row.photoUrl, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(row.name, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      const ChallengeChip('You', background: AppColors.primary, foreground: Colors.white),
                    ],
                  ],
                ),
                if (hostelLabel != null && hostelLabel!.isNotEmpty)
                  Text(
                    hostelLabel!,
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(valueLabel, style: t.labelLarge),
              Text('${row.progressPct}%', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hostel ranking table of an INTER_HOSTEL challenge.
class HostelRankingTable extends StatelessWidget {
  const HostelRankingTable({
    super.key,
    required this.rows,
    required this.valueLabelOf,
    required this.myHostelId,
  });

  final List<LeaderboardRow> rows;
  final String Function(LeaderboardRow row) valueLabelOf;
  final String? myHostelId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = t.bodySmall?.copyWith(color: AppColors.textMuted);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 32, child: Text('Rank', style: muted)),
              const SizedBox(width: 10),
              Expanded(child: Text('Hostel', style: muted)),
              Text('Result', style: muted),
            ],
          ),
        ),
        for (final r in rows)
          Container(
            key: ValueKey('hostel-row-${r.id}'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: r.id == myHostelId ? AppColors.mint : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: r.id == myHostelId ? AppColors.primary : AppColors.grey),
            ),
            child: Row(
              children: [
                RankBadge(rank: r.rank),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(r.name, style: t.labelLarge, overflow: TextOverflow.ellipsis)),
                          if (r.id == myHostelId) ...[
                            const SizedBox(width: 6),
                            const ChallengeChip('Your hostel', background: AppColors.primary, foreground: Colors.white),
                          ],
                        ],
                      ),
                      if (r.participants != null)
                        Text(
                          r.participants == 1 ? '1 participant' : '${r.participants} participants',
                          style: muted,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(valueLabelOf(r), style: t.labelLarge),
              ],
            ),
          ),
      ],
    );
  }
}
