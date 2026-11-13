import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/campus_activity.dart';

/// "Campus activity" block: active challenges, upcoming hostel competitions,
/// buddies available and my leaderboard position. Every row shows a friendly
/// empty message when its feature has nothing (yet).
class HomeCampusActivity extends StatelessWidget {
  const HomeCampusActivity({super.key, required this.activity, this.loading = false});

  final CampusActivity? activity;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final a = activity ?? CampusActivity.empty;
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Campus activity', style: t.titleMedium),
          const SizedBox(height: 8),
          if (loading)
            const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
          else ...[
            _Row(
              icon: Icons.emoji_events_outlined,
              title: 'Active challenges',
              value: a.activeChallenges == null ? null : '${a.activeChallenges}',
              empty: 'No active challenges yet',
            ),
            _Row(
              icon: Icons.apartment_outlined,
              title: 'Upcoming hostel competitions',
              value: a.upcomingHostelCompetitions == null ? null : '${a.upcomingHostelCompetitions}',
              empty: 'Nothing scheduled yet',
            ),
            _Row(
              icon: Icons.group_outlined,
              title: 'Buddies available',
              value: a.buddiesAvailable == null ? null : '${a.buddiesAvailable}',
              empty: 'Find buddies to train with',
            ),
            _Row(
              icon: Icons.leaderboard_outlined,
              title: 'My leaderboard position',
              value: a.myLeaderboardRank == null ? null : '#${a.myLeaderboardRank}',
              empty: 'Not ranked yet',
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.value, required this.empty});

  final IconData icon;
  final String title;
  final String? value;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyMedium),
                if (value == null)
                  Text(empty, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          if (value != null) Text(value!, style: t.titleMedium),
        ],
      ),
    );
  }
}
