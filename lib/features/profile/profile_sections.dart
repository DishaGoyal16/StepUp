import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/profile_extras/badges.dart';
import '../../data/profile_extras/extras_models.dart';
import 'profile_format.dart';
import 'profile_view_model.dart';

/// Material icon for a badge's `icon` name (from `adminSettings/badges`).
IconData badgeIcon(String name) => switch (name) {
      'directions_walk' => Icons.directions_walk,
      'emoji_events' => Icons.emoji_events,
      'local_fire_department' => Icons.local_fire_department,
      'military_tech' => Icons.military_tech,
      'apartment' => Icons.apartment,
      'star' => Icons.star,
      _ => Icons.workspace_premium,
    };

/// Small inline "could not load" row used inside cards.
class SectionError extends StatelessWidget {
  const SectionError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
}

class SectionLoading extends StatelessWidget {
  const SectionLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      );
}

/// Achievements: earned badges in colour, locked ones greyed with how to earn
/// them. Never awards anything - only displays server-written achievements.
class AchievementsSection extends StatelessWidget {
  const AchievementsSection({super.key, required this.state, required this.onRetry});

  final SectionState<List<BadgeStatus>> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final list = state.data;
    final earned = list?.where((b) => b.earned).length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Achievements',
          subtitle: list == null ? null : '$earned of ${list.length} earned',
        ),
        if (state.loading) const SectionLoading(),
        if (state.failed)
          AppCard(child: SectionError(message: 'Could not load your achievements.', onRetry: onRetry)),
        if (list != null)
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final cols = c.maxWidth >= 560 ? 3 : 2;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final b in list) SizedBox(width: w, child: BadgeTile(status: b)),
                ],
              );
            },
          ),
      ],
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.status});

  final BadgeStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final def = status.definition;
    final earned = status.earned;
    final fg = earned ? AppColors.primary : AppColors.textMuted;
    return Semantics(
      label: earned
          ? 'Badge ${def.title}, earned'
          : 'Badge ${def.title}, locked. How to earn: ${def.howToEarn}',
      child: AppCard(
        key: ValueKey('badge-${def.id}-${earned ? 'earned' : 'locked'}'),
        color: earned ? AppColors.surface : AppColors.background,
        shadow: earned,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: earned ? AppColors.mint : AppColors.grey,
                  child: Icon(badgeIcon(def.icon), color: fg),
                ),
                const Spacer(),
                if (!earned) const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              def.title,
              style: t.titleMedium?.copyWith(color: earned ? AppColors.text : AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            if (earned)
              Text(
                status.awardedAt == null ? 'Earned' : 'Earned ${formatShortDate(status.awardedAt)}',
                style: t.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
              )
            else
              Text(
                'How to earn: ${def.howToEarn}',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Own challenges with status COMPLETED.
class CompletedChallengesSection extends StatelessWidget {
  const CompletedChallengesSection({super.key, required this.state, required this.onRetry});

  final SectionState<List<CompletedChallenge>> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final list = state.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Completed challenges'),
        if (state.loading) const SectionLoading(),
        if (state.failed)
          AppCard(child: SectionError(message: 'Could not load your challenges.', onRetry: onRetry)),
        if (list != null && list.isEmpty)
          AppCard(
            child: EmptyState(
              compact: true,
              icon: Icons.emoji_events_outlined,
              title: 'No completed challenges yet',
              message: 'Join a challenge and finish it to see it here.',
              actionLabel: 'Browse challenges',
              onAction: () => context.go(AppRoutes.challenges),
            ),
          ),
        if (list != null && list.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    key: ValueKey('completed-${list[i].challengeId}'),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.mint,
                      child: Icon(Icons.check, color: AppColors.primary),
                    ),
                    title: Text(list[i].title),
                    subtitle: Text(
                      [
                        if (list[i].completedAt != null) 'Completed ${formatShortDate(list[i].completedAt)}',
                      ].join(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.challengeDetail(list[i].challengeId)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Accepted buddies.
class BuddiesSection extends StatelessWidget {
  const BuddiesSection({super.key, required this.state, required this.onRetry});

  final SectionState<List<BuddySummary>> state;
  final VoidCallback onRetry;

  static const int _preview = 5;

  @override
  Widget build(BuildContext context) {
    final list = state.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Buddies',
          subtitle: list == null ? null : '${list.length} ${list.length == 1 ? 'buddy' : 'buddies'}',
          actionLabel: (list != null && list.isNotEmpty) ? 'See all' : null,
          onAction: () => context.go(AppRoutes.buddies),
        ),
        if (state.loading) const SectionLoading(),
        if (state.failed)
          AppCard(child: SectionError(message: 'Could not load your buddies.', onRetry: onRetry)),
        if (list != null && list.isEmpty)
          AppCard(
            child: EmptyState(
              compact: true,
              icon: Icons.group_outlined,
              title: 'No buddies yet',
              message: 'Find a workout partner who matches your schedule.',
              actionLabel: 'Find buddies',
              onAction: () => context.go(AppRoutes.buddies),
            ),
          ),
        if (list != null && list.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < list.length && i < _preview; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    key: ValueKey('buddy-${list[i].uid}'),
                    leading: AvatarCircle(name: list[i].displayName, photoUrl: list[i].photoUrl, radius: 20),
                    title: Text(list[i].displayName),
                  ),
                ],
                if (list.length > _preview)
                  TextButton(
                    onPressed: () => context.go(AppRoutes.buddies),
                    child: Text('+${list.length - _preview} more'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
