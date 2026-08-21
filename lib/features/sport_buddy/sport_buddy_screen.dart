import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/sport_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────
final selectedSportFilterProvider = StateProvider<String>((ref) => 'Badminton');
final matchRequestsProvider =
    StateProvider<Map<String, MatchRequestStatus>>((ref) => {});

// ─────────────────────────────────────────────────────────
// SPORT BUDDY SCREEN
// ─────────────────────────────────────────────────────────
class SportBuddyScreen extends ConsumerWidget {
  const SportBuddyScreen({super.key});

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
      appBar: AppBar(
        title: const Text('Sport Buddy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded,
                color: AppColors.secondary),
            tooltip: 'Sessions',
            onPressed: () => context.go('/sport-buddy/sessions'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sport filter chips
          _SportFilterBar(
            sports: user.sports.isNotEmpty
                ? user.sports
                : AppConstants.supportedSports.take(5).toList(),
            selected: selectedSport,
            onSelected: (s) =>
                ref.read(selectedSportFilterProvider.notifier).state = s,
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(20, 0, 20, 100),
              children: [
                _MatchingInfoBanner(skillLevel: skillLevel, sport: selectedSport),
                const SizedBox(height: 16),
                SectionHeader(
                  title: '🎯 Best Matches',
                  actionLabel: 'See All',
                  onAction: () => context.go('/sport-buddy/matches'),
                ),
                const SizedBox(height: 12),
                if (matches.isEmpty)
                  _NoMatches(sport: selectedSport)
                else
                  ...matches.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MatchCard(
                          match: e.value,
                          onRequest: () => _sendRequest(ref, e.value.id),
                          status: ref.watch(matchRequestsProvider)[e.value.id],
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendRequest(WidgetRef ref, String matchId) {
    final current = ref.read(matchRequestsProvider);
    ref.read(matchRequestsProvider.notifier).state = {
      ...current,
      matchId: MatchRequestStatus.sent,
    };
  }
}

// ─────────────────────────────────────────────────────────
// SPORT FILTER BAR
// ─────────────────────────────────────────────────────────
class _SportFilterBar extends StatelessWidget {
  final List<String> sports;
  final String selected;
  final void Function(String) onSelected;

  const _SportFilterBar({
    required this.sports,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        itemCount: sports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sport = sports[i];
          final isSelected = sport == selected;
          return GestureDetector(
            onTap: () => onSelected(sport),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondary.withOpacity(0.2)
                    : AppColors.darkCard,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: isSelected
                      ? AppColors.secondary
                      : AppColors.darkBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                sport,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? AppColors.secondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MATCHING INFO BANNER
// ─────────────────────────────────────────────────────────
class _MatchingInfoBanner extends StatelessWidget {
  final String skillLevel;
  final String sport;
  const _MatchingInfoBanner(
      {required this.skillLevel, required this.sport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Text('🤝', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matching you for $sport ($skillLevel)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Score = 40% skill fit + 30% reliability + 30% preference match',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MATCH CARD
// ─────────────────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final SportMatch match;
  final VoidCallback onRequest;
  final MatchRequestStatus? status;

  const _MatchCard({
    required this.match,
    required this.onRequest,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = status == MatchRequestStatus.sent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isSent
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.secondary.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(match.avatarEmoji,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(match.userName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      '${match.department} · ${match.hostel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              MatchScoreChip(percent: match.matchPercent),
            ],
          ),
          const SizedBox(height: 14),

          // Score breakdown
          _ScoreRow('Skill Fit', match.skillFitScore, AppColors.primary),
          const SizedBox(height: 5),
          _ScoreRow('Reliability',
              match.reliabilityScore, AppColors.secondary),
          const SizedBox(height: 5),
          _ScoreRow('Preference Fit',
              match.preferenceFitScore, AppColors.accent),
          const SizedBox(height: 12),

          // Match reasons chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: match.matchReasons.map((r) => _ReasonChip(r)).toList(),
          ),
          if (match.mismatchReasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: match.mismatchReasons
                  .map((r) => _ReasonChip(r, isPositive: false))
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),

          // Availability + action
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📅 ${match.availableDays.take(3).join(', ')}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                    Text(
                      '⏰ ${match.availableTimes.first}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: isSent ? null : onRequest,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isSent ? null : AppColors.primaryGradient,
                    color:
                        isSent ? AppColors.darkBorder : null,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    isSent ? '✓ Requested' : 'Connect',
                    style: TextStyle(
                      fontSize: 13,
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
    ).animate().fadeIn().slideY(begin: 0.1);
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ScoreRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: AppColors.darkBorder,
            valueColor: AlwaysStoppedAnimation(color),
            borderRadius: BorderRadius.circular(3),
            minHeight: 5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(value * 100).round()}%',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color),
        ),
      ],
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String text;
  final bool isPositive;
  const _ReasonChip(this.text, {this.isPositive = true});

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? AppColors.primary : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '${isPositive ? '✓' : '~'} $text',
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final String sport;
  const _NoMatches({required this.sport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No matches for $sport yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Try a different sport or expand your availability',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
