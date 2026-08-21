import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/settings_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/activity_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────
final homeUserProvider = Provider<UserModel?>((ref) {
  return ref.read(localUserRepositoryProvider).getCurrentUser() ??
      ref.read(localUserRepositoryProvider).createDemoUser();
});

final homeSummaryProvider = Provider<DailyActivitySummary>((ref) {
  final repo = ref.read(localActivityRepositoryProvider);
  return repo.getTodaySummary() ?? repo.demoTodaySummary();
});

// ─────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(homeUserProvider);
    final summary = ref.watch(homeSummaryProvider);
    final isDemoMode = ref.watch(demoModeProvider);
    final stepGoal = ref.watch(dailyStepGoalProvider);

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final progress = summary.verifiedSteps / stepGoal;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, user, isDemoMode),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDemoMode || user.isDemoUser)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: DemoModeBanner(),
                    ),
                  _StepProgressCard(
                    summary: summary,
                    progress: progress,
                    stepGoal: stepGoal,
                    user: user,
                  ),
                  const SizedBox(height: 20),
                  _XPStreakRow(user: user),
                  const SizedBox(height: 24),
                  _QuickActionsGrid(user: user),
                  const SizedBox(height: 24),
                  _IntegrityOverview(summary: summary),
                  const SizedBox(height: 24),
                  _WeeklyBarChart(
                      summaries: ref
                          .read(localActivityRepositoryProvider)
                          .demoWeeklySummaries()),
                  const SizedBox(height: 24),
                  _ActiveChallengesPreview(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(
      BuildContext context, UserModel user, bool isDemoMode) {
    final now = DateTime.now();
    final greeting = _greeting(now.hour);
    return SliverAppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floating: true,
      pinned: false,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  user.name.split(' ').first,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                CoinDisplay(amount: user.stepCoins, fontSize: 15),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => context.go('/profile'),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Center(
                      child: Text(user.avatarEmoji,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _greeting(int hour) {
    if (hour < 12) return 'Good Morning 🌅';
    if (hour < 17) return 'Good Afternoon ☀️';
    if (hour < 21) return 'Good Evening 🌆';
    return 'Good Night 🌙';
  }
}

// ─────────────────────────────────────────────────────────
// STEP PROGRESS CARD
// ─────────────────────────────────────────────────────────
class _StepProgressCard extends StatelessWidget {
  final DailyActivitySummary summary;
  final double progress;
  final int stepGoal;
  final UserModel user;

  const _StepProgressCard({
    required this.summary,
    required this.progress,
    required this.stepGoal,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E1A2B), Color(0xFF0D1520)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: AppShadows.glow(AppColors.primary),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY\'S STEPS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 1.5,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmt(summary.verifiedSteps),
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        height: 1.0,
                      ),
                    ).animate().fadeIn(duration: 500.ms),
                    Text(
                      '/ ${_fmt(stepGoal)} goal',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    IntegrityBadge(
                      label:
                          '${summary.integrityLabel} Integrity (${(summary.integrityScore * 100).round()}%)',
                      score: summary.integrityScore,
                    ),
                  ],
                ),
              ),
              CircularPercentIndicator(
                radius: 55,
                lineWidth: 8,
                percent: progress.clamp(0.0, 1.0),
                center: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                progressColor: AppColors.primary,
                backgroundColor: AppColors.darkBorder,
                circularStrokeCap: CircularStrokeCap.round,
                animation: true,
                animationDuration: 800,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(
                label: 'Verified',
                value: _fmt(summary.verifiedSteps),
                color: AppColors.primary,
              ),
              _div(),
              _MiniStat(
                label: 'Suspicious',
                value: _fmt(summary.suspiciousSteps),
                color: AppColors.danger,
              ),
              _div(),
              _MiniStat(
                label: 'Distance',
                value: '${(summary.distanceMeters / 1000).toStringAsFixed(1)}km',
                color: AppColors.secondary,
              ),
              _div(),
              _MiniStat(
                label: 'Active',
                value:
                    '${summary.walkingMinutes + summary.runningMinutes}min',
                color: AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2);
  }

  Widget _div() => Container(
      width: 1, height: 28, color: AppColors.darkBorder, margin: const EdgeInsets.symmetric(horizontal: 8));

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          Text(label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// XP + STREAK ROW
// ─────────────────────────────────────────────────────────
class _XPStreakRow extends StatelessWidget {
  final UserModel user;
  const _XPStreakRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            emoji: '⚡',
            label: 'Level ${user.level} — ${user.levelTitle}',
            value: '${user.xp} XP',
            color: AppColors.secondary,
            progress: user.levelProgress,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoTile(
            emoji: '🔥',
            label: 'Day Streak',
            value: '${user.currentStreak} days',
            color: AppColors.danger,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }
}

class _InfoTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;
  final double? progress;

  const _InfoTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.darkBorder,
              valueColor: AlwaysStoppedAnimation(color),
              borderRadius: BorderRadius.circular(4),
              minHeight: 4,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// QUICK ACTIONS
// ─────────────────────────────────────────────────────────
class _QuickActionsGrid extends ConsumerWidget {
  final UserModel user;
  const _QuickActionsGrid({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _Action('Activity', '🏃', '/activity', AppColors.primary),
      _Action('Challenges', '🏆', '/challenges', AppColors.accent),
      _Action('Find Buddy', '🤝', '/sport-buddy', AppColors.secondary),
      _Action('Leaderboard', '📊', '/profile/leaderboard', AppColors.danger),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Quick Access'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: actions.map((a) => _QuickActionTile(action: a)).toList(),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }
}

class _Action {
  final String label;
  final String emoji;
  final String route;
  final Color color;
  const _Action(this.label, this.emoji, this.route, this.color);
}

class _QuickActionTile extends StatelessWidget {
  final _Action action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(action.route),
      child: Container(
        decoration: BoxDecoration(
          color: action.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border:
              Border.all(color: action.color.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(action.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: action.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// INTEGRITY OVERVIEW
// ─────────────────────────────────────────────────────────
class _IntegrityOverview extends StatelessWidget {
  final DailyActivitySummary summary;
  const _IntegrityOverview({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '🛡 Today\'s Integrity',
          actionLabel: 'Details',
          onAction: () => context.go('/activity'),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _IBar('✅ Genuine', summary.verifiedSteps,
                      summary.importedSteps, AppColors.primary),
                  _IBar('🚫 Suspicious', summary.suspiciousSteps,
                      summary.importedSteps, AppColors.danger),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      Flexible(
                        flex: summary.verifiedSteps,
                        child: Container(color: AppColors.primary),
                      ),
                      Flexible(
                        flex: summary.suspiciousSteps,
                        child: Container(
                            color: AppColors.danger.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Prototype integrity engine (rule-based v1) — '
                '${summary.importedSteps} imported → ${summary.verifiedSteps} verified',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }
}

class _IBar extends StatelessWidget {
  final String label;
  final int steps;
  final int total;
  final Color color;
  const _IBar(this.label, this.steps, this.total, this.color);

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (steps / total * 100).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text('$steps steps ($pct%)',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// WEEKLY BAR CHART (simple custom paint)
// ─────────────────────────────────────────────────────────
class _WeeklyBarChart extends StatelessWidget {
  final List<DailyActivitySummary> summaries;
  const _WeeklyBarChart({required this.summaries});

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();
    final maxSteps = summaries
        .map((s) => s.verifiedSteps)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '📈 7-Day Verified Steps'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summaries.asMap().entries.map((e) {
                final s = e.value;
                final ratio =
                    maxSteps > 0 ? s.verifiedSteps / maxSteps : 0.0;
                final isToday = e.key == summaries.length - 1;
                final day = DateFormat('E').format(s.date).substring(0, 2);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration:
                              Duration(milliseconds: 400 + e.key * 50),
                          height: (100 * ratio).clamp(4.0, 100.0),
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary
                                : AppColors.primary.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day,
                          style: TextStyle(
                            fontSize: 10,
                            color: isToday
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 500.ms);
  }
}

// ─────────────────────────────────────────────────────────
// ACTIVE CHALLENGES PREVIEW
// ─────────────────────────────────────────────────────────
class _ActiveChallengesPreview extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenges =
        ref.read(localChallengeRepositoryProvider).getActiveChallenges();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '🏆 Active Challenges',
          actionLabel: 'See All',
          onAction: () => context.go('/challenges'),
        ),
        const SizedBox(height: 12),
        ...challenges.take(2).map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChallengePreviewTile(challenge: c),
            )),
      ],
    ).animate().fadeIn(delay: 600.ms);
  }
}

class _ChallengePreviewTile extends StatelessWidget {
  final challenge;
  const _ChallengePreviewTile({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final progress = challenge.progressPercent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(challenge.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(challenge.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              XPDisplay(amount: challenge.xpReward),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.darkBorder,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_fmt(challenge.stepsRemaining)} steps remaining',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
