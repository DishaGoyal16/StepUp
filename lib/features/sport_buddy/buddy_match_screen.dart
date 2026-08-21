import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/sport_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';
import 'sport_buddy_screen.dart';

// ─────────────────────────────────────────────────────────
// BUDDY MATCH SCREEN (all matches expanded view)
// ─────────────────────────────────────────────────────────
class BuddyMatchScreen extends ConsumerWidget {
  const BuddyMatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();
    final selectedSport = ref.watch(selectedSportFilterProvider);
    final skillLevel = user.skillLevels[selectedSport] ?? 'Intermediate';
    final matches = ref
        .read(localSportBuddyRepositoryProvider)
        .getDemoMatches(selectedSport, skillLevel);

    return Scaffold(
      appBar: AppBar(title: Text('Matches for $selectedSport')),
      body: matches.isEmpty
          ? const Center(child: Text('No matches found'))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final m = matches[i];
                return _SimpleMatchTile(match: m);
              },
            ),
    );
  }
}

class _SimpleMatchTile extends ConsumerWidget {
  final SportMatch match;
  const _SimpleMatchTile({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(matchRequestsProvider)[match.id];
    final isSent = status == MatchRequestStatus.sent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Text(match.avatarEmoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.userName,
                    style: Theme.of(context).textTheme.titleMedium),
                Text('${match.skillLevel} · ${match.campusZone}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(
                    'Reliability: ${(match.reliabilityScore * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MatchScoreChip(percent: match.matchPercent),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: isSent
                    ? null
                    : () {
                        final current = ref.read(matchRequestsProvider);
                        ref
                            .read(matchRequestsProvider.notifier)
                            .state = {
                          ...current,
                          match.id: MatchRequestStatus.sent,
                        };
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient:
                        isSent ? null : AppColors.primaryGradient,
                    color: isSent ? AppColors.darkBorder : null,
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    isSent ? '✓ Sent' : 'Connect',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSent
                          ? AppColors.textSecondary
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
