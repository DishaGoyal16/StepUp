import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/gamification_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

enum _LeaderboardTab { hostel, campus, friends }

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() =>
      _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();
    final entries = ref
        .read(localLeaderboardRepositoryProvider)
        .getHostelLeaderboard(user.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Hostel'),
            Tab(text: 'Campus'),
            Tab(text: 'Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LeaderboardList(entries: entries),
          _LeaderboardList(
              entries: entries
                  .map((e) =>
                      LeaderboardEntry(
                        rank: e.rank,
                        userId: e.userId,
                        userName: e.userName,
                        avatarEmoji: e.avatarEmoji,
                        department: e.department,
                        hostel: e.hostel,
                        verifiedSteps: e.verifiedSteps + 2000,
                        isCurrentUser: e.isCurrentUser,
                      ))
                  .toList()),
          _LeaderboardList(
              entries: entries
                  .where((e) => e.rank <= 3 || e.isCurrentUser)
                  .toList()),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _LeaderboardList({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        if (entries.length >= 3)
          _PodiumRow(
            first: entries.firstWhere((e) => e.rank == 1,
                orElse: () => entries.first),
            second: entries.firstWhere((e) => e.rank == 2,
                orElse: () => entries[1]),
            third: entries.firstWhere((e) => e.rank == 3,
                orElse: () => entries[2]),
          ),
        const SizedBox(height: 20),
        const SectionHeader(title: '📊 Full Rankings'),
        const SizedBox(height: 10),
        ...entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LeaderboardTile(entry: e),
            )),
        const SizedBox(height: 16),
        const _PrivacyNote(),
      ],
    );
  }
}

class _PodiumRow extends StatelessWidget {
  final LeaderboardEntry first;
  final LeaderboardEntry second;
  final LeaderboardEntry third;

  const _PodiumRow({
    required this.first,
    required this.second,
    required this.third,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumItem(entry: second, height: 90)),
        Expanded(child: _PodiumItem(entry: first, height: 120)),
        Expanded(child: _PodiumItem(entry: third, height: 70)),
      ],
    ).animate().fadeIn(duration: 600.ms);
  }
}

class _PodiumItem extends StatelessWidget {
  final LeaderboardEntry entry;
  final double height;
  const _PodiumItem({required this.entry, required this.height});

  @override
  Widget build(BuildContext context) {
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    final colors = {
      1: AppColors.accent,
      2: Colors.grey,
      3: const Color(0xFFCD7F32),
    };
    final color = colors[entry.rank] ?? AppColors.primary;

    return Column(
      children: [
        Text(entry.avatarEmoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 4),
        Text(
          entry.userName.split(' ').first,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _fmt(entry.verifiedSteps),
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8)),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(
              medals[entry.rank] ?? '🏅',
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _LeaderboardTile extends StatelessWidget {
  final LeaderboardEntry entry;
  const _LeaderboardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isTop3 = entry.rank <= 3;
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: entry.isCurrentUser
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: entry.isCurrentUser
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.darkBorder,
          width: entry.isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              isTop3 ? medals[entry.rank]! : '#${entry.rank}',
              style: TextStyle(
                fontSize: isTop3 ? 20 : 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Text(entry.avatarEmoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                        entry.isCurrentUser
                            ? '${entry.userName} (You)'
                            : entry.userName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: entry.isCurrentUser
                                  ? AppColors.primary
                                  : null,
                            )),
                  ],
                ),
                Text(entry.department,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(entry.verifiedSteps),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Text('verified steps',
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.05);
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_rounded, size: 14, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Leaderboards show verified steps and display names only. '
              'Email addresses are never shown publicly.',
              style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
