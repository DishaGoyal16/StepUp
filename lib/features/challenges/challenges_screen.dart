import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/gamification_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenges =
        ref.read(localChallengeRepositoryProvider).getActiveChallenges();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sports_esports_rounded,
                color: AppColors.accent),
            tooltip: 'Step Battles',
            onPressed: () => context.go('/challenges/bets'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          const _CampusBattleBanner(),
          const SizedBox(height: 20),
          const SectionHeader(title: '🔥 Active Challenges'),
          const SizedBox(height: 12),
          ...challenges.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ChallengeCard(challenge: c),
              )),
          const SizedBox(height: 8),
          const SectionHeader(title: '🏅 Completed'),
          const SizedBox(height: 12),
          const _CompletedPlaceholder(),
        ],
      ),
    );
  }
}

// ─── Campus Battle Banner ────────────────────────────────────
class _CampusBattleBanner extends StatelessWidget {
  const _CampusBattleBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/challenges/bets'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.battleGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadows.glow(AppColors.danger),
        ),
        child: Row(
          children: [
            const Text('⚔️', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step Battles',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wager StepCoins. Beat your rival\'s verified steps.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: const Text(
                'Play',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.1),
    );
  }
}

// ─── Challenge Card ───────────────────────────────────────────
class _ChallengeCard extends StatelessWidget {
  final ChallengeModel challenge;
  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final progress = challenge.progressPercent;
    final timeLeft = challenge.endDate.difference(DateTime.now());
    final isExpiringSoon = timeLeft.inHours < 6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isExpiringSoon
              ? AppColors.warning.withOpacity(0.4)
              : AppColors.darkBorder,
        ),
        boxShadow: isExpiringSoon
            ? AppShadows.glow(AppColors.warning)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(challenge.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(_typeLabel(challenge.type),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _typeColor(challenge.type),
                            )),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  XPDisplay(amount: challenge.xpReward, fontSize: 13),
                  const SizedBox(height: 2),
                  CoinDisplay(amount: challenge.coinReward, fontSize: 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.darkBorder,
            valueColor: AlwaysStoppedAnimation(_typeColor(challenge.type)),
            borderRadius: BorderRadius.circular(6),
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_fmt(challenge.currentSteps)} / ${_fmt(challenge.targetSteps)} steps',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                isExpiringSoon
                    ? '⏰ ${timeLeft.inHours}h left!'
                    : _timeLeftLabel(timeLeft),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isExpiringSoon
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (challenge.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              challenge.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Color _typeColor(ChallengeType type) {
    switch (type) {
      case ChallengeType.daily:
        return AppColors.primary;
      case ChallengeType.weekly:
        return AppColors.secondary;
      case ChallengeType.campus:
        return AppColors.accent;
      case ChallengeType.hostel:
        return AppColors.danger;
      case ChallengeType.friend:
        return AppColors.primaryLight;
    }
  }

  String _typeLabel(ChallengeType type) {
    switch (type) {
      case ChallengeType.daily:
        return '🌅 Daily Challenge';
      case ChallengeType.weekly:
        return '📅 Weekly Challenge';
      case ChallengeType.campus:
        return '🏛️ Campus Challenge';
      case ChallengeType.hostel:
        return '🏠 Hostel Challenge';
      case ChallengeType.friend:
        return '🤝 Friend Challenge';
    }
  }

  String _timeLeftLabel(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d left';
    if (d.inHours > 0) return '${d.inHours}h left';
    return '${d.inMinutes}m left';
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _CompletedPlaceholder extends StatelessWidget {
  const _CompletedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Column(
        children: [
          Text('🏅', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text(
            'No completed challenges yet',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Complete active challenges to see them here',
            style: TextStyle(color: AppColors.textHint, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
