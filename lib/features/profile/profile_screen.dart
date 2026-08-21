import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/gamification_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/gamification_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();

    final badges = GamificationService.evaluateBadges(
      user,
      allBadgesCatalog.map((b) {
        final isEarned = user.earnedBadgeIds.contains(b.id);
        return isEarned
            ? b.copyWith(isUnlocked: true, unlockedAt: DateTime.now())
            : b;
      }).toList(),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildHeroAppBar(context, user),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _StatsRow(user: user),
                  const SizedBox(height: 24),
                  _LevelProgress(user: user),
                  const SizedBox(height: 24),
                  _NavigationTiles(user: user),
                  const SizedBox(height: 24),
                  _BadgesSection(badges: badges),
                  const SizedBox(height: 24),
                  _SportProfileSection(user: user),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildHeroAppBar(BuildContext context, UserModel user) {
    return SliverAppBar(
      backgroundColor: AppColors.darkBg,
      expandedHeight: 200,
      pinned: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_rounded,
              color: AppColors.textSecondary),
          onPressed: () => context.go('/profile/settings'),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0E1E2B), Color(0xFF0D0F14)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary, width: 2.5),
                    boxShadow: AppShadows.glow(AppColors.primary),
                  ),
                  child: Center(
                    child: Text(user.avatarEmoji,
                        style: const TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${user.department} · ${user.year}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: AppColors.secondary.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Level ${user.level} · ${user.levelTitle}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final UserModel user;
  const _StatsRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Verified Steps',
            value: _fmt(user.totalVerifiedSteps),
            emoji: '🚶',
            valueColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'StepCoins',
            value: '${user.stepCoins}',
            emoji: '🪙',
            valueColor: AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Day Streak',
            value: '${user.currentStreak}',
            emoji: '🔥',
            valueColor: AppColors.danger,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

// ─────────────────────────────────────────────────────────
// LEVEL PROGRESS
// ─────────────────────────────────────────────────────────
class _LevelProgress extends StatelessWidget {
  final UserModel user;
  const _LevelProgress({required this.user});

  @override
  Widget build(BuildContext context) {
    final progress = user.levelProgress;
    final xpToNext = user.xpForNextLevel - user.xp;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('⚡ Level ${user.level}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      )),
              Text('${user.xp} XP',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            user.level < 10
                ? '$xpToNext XP to Level ${user.level + 1}'
                : 'Maximum level reached! 🏆',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.darkBorder,
            valueColor:
                const AlwaysStoppedAnimation(AppColors.secondary),
            borderRadius: BorderRadius.circular(6),
            minHeight: 8,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }
}

// ─────────────────────────────────────────────────────────
// NAVIGATION TILES
// ─────────────────────────────────────────────────────────
class _NavigationTiles extends StatelessWidget {
  final UserModel user;
  const _NavigationTiles({required this.user});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _NavTile('🪙 Wallet', '${user.stepCoins} StepCoins',
          AppColors.accent, '/profile/wallet'),
      _NavTile('🏆 Leaderboard', 'Campus rankings',
          AppColors.primary, '/profile/leaderboard'),
      _NavTile('🔒 Privacy', 'Data & permissions',
          AppColors.secondary, '/profile/privacy'),
      _NavTile('⚙️ Settings', 'Theme, goals, demo mode',
          AppColors.textSecondary, '/profile/settings'),
    ];

    return Column(
      children: tiles
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => context.go(t.route),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                      border:
                          Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      children: [
                        Text(t.emoji.substring(0, 2),
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(t.label.substring(3),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                              Text(t.subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                            ],
                          ),
                        ),
                        const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textSecondary,
                            size: 20),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    ).animate().fadeIn(delay: 300.ms);
  }
}

class _NavTile {
  final String emoji;
  final String label;
  final String subtitle;
  final Color color;
  final String route;
  const _NavTile(this.emoji, this.subtitle, this.color, this.route)
      : label = emoji;
}

// ─────────────────────────────────────────────────────────
// BADGES SECTION
// ─────────────────────────────────────────────────────────
class _BadgesSection extends StatelessWidget {
  final List<BadgeModel> badges;
  const _BadgesSection({required this.badges});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '🏅 Badges',
          actionLabel: '${badges.where((b) => b.isUnlocked).length}/${badges.length}',
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: badges.map((b) => _BadgeTile(badge: b)).toList(),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }
}

class _BadgeTile extends StatelessWidget {
  final BadgeModel badge;
  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _rarityColor(badge.rarity);
    return Tooltip(
      message: badge.isUnlocked
          ? badge.name
          : '${badge.name} — Locked\n${badge.description}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: badge.isUnlocked
              ? color.withOpacity(0.12)
              : AppColors.darkCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: badge.isUnlocked
                ? color.withOpacity(0.4)
                : AppColors.darkBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              badge.emoji,
              style: TextStyle(
                fontSize: 24,
                color: badge.isUnlocked
                    ? null
                    : Colors.white.withOpacity(0.2),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              badge.name,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: badge.isUnlocked
                    ? color
                    : AppColors.textHint,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Color _rarityColor(BadgeRarity r) {
    switch (r) {
      case BadgeRarity.common:
        return AppColors.primary;
      case BadgeRarity.rare:
        return AppColors.secondary;
      case BadgeRarity.epic:
        return AppColors.warning;
      case BadgeRarity.legendary:
        return AppColors.accent;
    }
  }
}

// ─────────────────────────────────────────────────────────
// SPORT PROFILE SECTION
// ─────────────────────────────────────────────────────────
class _SportProfileSection extends StatelessWidget {
  final UserModel user;
  const _SportProfileSection({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '🏸 Sport Profile'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sports_tennis_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('Sports: ${user.sports.join(', ')}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 8),
              ...user.skillLevels.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 26),
                        Text('${e.key}: ',
                            style:
                                Theme.of(context).textTheme.bodySmall),
                        Text(e.value,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ],
                    ),
                  )),
              const Divider(color: AppColors.darkBorder, height: 20),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      color: AppColors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Available: ${user.availableDays.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppColors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.availableTimes.join(', '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Text(user.campusZone,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const Divider(color: AppColors.darkBorder, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatBit(
                    '${(user.reliabilityScore * 100).round()}%',
                    'Reliability',
                    AppColors.primary,
                  ),
                  _StatBit(
                    '${user.completedSessions}',
                    'Sessions',
                    AppColors.secondary,
                  ),
                  _StatBit(
                    '${user.preferredGroupSizeMin}–${user.preferredGroupSizeMax}',
                    'Group Size',
                    AppColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 500.ms);
  }
}

class _StatBit extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatBit(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
