import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/gamification_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────
// BETS SCREEN
// ─────────────────────────────────────────────────────────
class BetsScreen extends ConsumerWidget {
  const BetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();
    final bets =
        ref.read(localBetRepositoryProvider).getActiveBets(user.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step Battles ⚔️'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CoinDisplay(amount: user.stepCoins, fontSize: 14),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/challenges/bets/create'),
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Battle',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: bets.isEmpty
          ? _EmptyBets()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: bets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _BetCard(bet: bets[i], userId: user.id),
            ),
    );
  }
}

class _EmptyBets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚔️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('No active battles',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Challenge a friend to a step battle\nand wager your StepCoins!',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BetCard extends StatelessWidget {
  final BetModel bet;
  final String userId;
  const _BetCard({required this.bet, required this.userId});

  @override
  Widget build(BuildContext context) {
    final isChallenger = bet.challenger.userId == userId;
    final myParticipant =
        isChallenger ? bet.challenger : bet.opponent;
    final theirParticipant =
        isChallenger ? bet.opponent : bet.challenger;
    final mySteps = myParticipant.currentVerifiedSteps;
    final theirSteps = theirParticipant.currentVerifiedSteps;
    final total = (mySteps + theirSteps).clamp(1, 99999);
    final myProgress = mySteps / total;
    final isWinning = mySteps >= theirSteps;

    return GestureDetector(
      onTap: () => context.go('/challenges/bets/${bet.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: isWinning
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.danger.withOpacity(0.3),
          ),
          boxShadow: AppShadows.glow(
              isWinning ? AppColors.primary : AppColors.danger),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _ParticipantAvatar(
                    emoji: myParticipant.avatarEmoji, isYou: true),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        const Text('⚔️ VS',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.danger)),
                        Text(
                          '${_fmt(bet.targetSteps)} step target',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                _ParticipantAvatar(
                    emoji: theirParticipant.avatarEmoji, isYou: false),
              ],
            ),
            const SizedBox(height: 12),
            // Names & steps
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    Text(_fmt(mySteps),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isWinning
                                ? AppColors.primary
                                : AppColors.textPrimary)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(theirParticipant.userName,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    Text(_fmt(theirSteps),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Flexible(
                      flex: (myProgress * 100).round().clamp(1, 99),
                      child: Container(color: AppColors.primary),
                    ),
                    Flexible(
                      flex: (100 - myProgress * 100).round().clamp(1, 99),
                      child: Container(
                          color: AppColors.danger.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('🪙',
                        style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      'Stake: ${bet.stakeCoins}  •  Prize: ${bet.prizeCoins}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(bet.status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    bet.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(bet.status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.1),
    );
  }

  Color _statusColor(BetStatus s) {
    switch (s) {
      case BetStatus.active:
        return AppColors.primary;
      case BetStatus.pending:
        return AppColors.warning;
      case BetStatus.completed:
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _ParticipantAvatar extends StatelessWidget {
  final String emoji;
  final bool isYou;
  const _ParticipantAvatar({required this.emoji, required this.isYou});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isYou
            ? AppColors.primary.withOpacity(0.15)
            : AppColors.danger.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(
            color: isYou ? AppColors.primary : AppColors.danger,
            width: 2),
      ),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// CREATE BET SCREEN
// ─────────────────────────────────────────────────────────
class CreateBetScreen extends ConsumerStatefulWidget {
  const CreateBetScreen({super.key});

  @override
  ConsumerState<CreateBetScreen> createState() => _CreateBetScreenState();
}

class _CreateBetScreenState extends ConsumerState<CreateBetScreen> {
  int _selectedTargetIdx = 1;
  int _selectedStakeIdx = 1;
  int _selectedDurationIdx = 0;
  final _opponentNameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _opponentNameController.dispose();
    super.dispose();
  }

  Future<void> _createBet() async {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();
    final stake = AppConstants.battleStakes[_selectedStakeIdx];
    if (user.stepCoins < stake) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Not enough StepCoins. You have ${user.stepCoins}'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final opponentName = _opponentNameController.text.trim().isEmpty
        ? 'Arjun Mehta'
        : _opponentNameController.text.trim();

    final bet = BetModel(
      id: _uuid.v4(),
      challenger: BetParticipant(
        userId: user.id,
        userName: user.name,
        avatarEmoji: user.avatarEmoji,
        currentVerifiedSteps: 0,
      ),
      opponent: BetParticipant(
        userId: 'opponent_${_uuid.v4().substring(0, 8)}',
        userName: opponentName,
        avatarEmoji: '🏃‍♂️',
        currentVerifiedSteps: 0,
      ),
      targetSteps: AppConstants.battleTargets[_selectedTargetIdx],
      stakeCoins: stake,
      prizeCoins: stake * 2,
      duration: AppConstants.battleDurations[_selectedDurationIdx],
      status: BetStatus.pending,
      createdAt: DateTime.now(),
    );

    await ref.read(localBetRepositoryProvider).saveBet(bet);

    if (mounted) {
      context.go('/challenges/bets');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();

    return Scaffold(
      appBar: AppBar(title: const Text('New Step Battle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('⚔️ Opponent'),
            const SizedBox(height: 10),
            TextField(
              controller: _opponentNameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Enter friend\'s name (demo: any name)',
                prefixIcon: Icon(Icons.person_outline_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle('🎯 Step Target'),
            const SizedBox(height: 10),
            _OptionRow(
              options: AppConstants.battleTargets
                  .map((t) => _fmt(t))
                  .toList(),
              selected: _selectedTargetIdx,
              onSelected: (i) => setState(() => _selectedTargetIdx = i),
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            _SectionTitle('🪙 Stake (StepCoins)'),
            const SizedBox(height: 4),
            Text(
              'Your balance: ${user.stepCoins} coins',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _OptionRow(
              options:
                  AppConstants.battleStakes.map((s) => '$s').toList(),
              selected: _selectedStakeIdx,
              onSelected: (i) => setState(() => _selectedStakeIdx = i),
              color: AppColors.accent,
            ),
            const SizedBox(height: 24),
            _SectionTitle('⏱ Duration'),
            const SizedBox(height: 10),
            _OptionRow(
              options: AppConstants.battleDurations,
              selected: _selectedDurationIdx,
              onSelected: (i) => setState(() => _selectedDurationIdx = i),
              color: AppColors.secondary,
            ),
            const SizedBox(height: 32),
            _PrizePreview(
              stake: AppConstants.battleStakes[_selectedStakeIdx],
              target: AppConstants.battleTargets[_selectedTargetIdx],
              duration: AppConstants.battleDurations[_selectedDurationIdx],
            ),
            const SizedBox(height: 24),
            GradientButton(
              text: 'Create Battle ⚔️',
              onPressed: _createBet,
              gradient: AppColors.battleGradient,
              isLoading: _isCreating,
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Demo mode: No real money or third-party payments involved. '
              'StepCoins are in-app virtual currency only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _OptionRow extends StatelessWidget {
  final List<String> options;
  final int selected;
  final void Function(int) onSelected;
  final Color color;

  const _OptionRow({
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.asMap().entries.map((e) {
          final isSelected = e.key == selected;
          return GestureDetector(
            onTap: () => onSelected(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : AppColors.darkCard,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: isSelected ? color : AppColors.darkBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? color : AppColors.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PrizePreview extends StatelessWidget {
  final int stake;
  final int target;
  final String duration;
  const _PrizePreview(
      {required this.stake, required this.target, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🪙 Winner takes:',
                  style: TextStyle(color: AppColors.textSecondary)),
              Text('${stake * 2} StepCoins',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent)),
            ],
          ),
          const Divider(color: AppColors.darkBorder, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PrizeStat('Target', '${_fmt(target)} steps'),
              _PrizeStat('Duration', duration),
              _PrizeStat('Your stake', '$stake 🪙'),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _PrizeStat extends StatelessWidget {
  final String label;
  final String value;
  const _PrizeStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// BET DETAIL SCREEN
// ─────────────────────────────────────────────────────────
class BetDetailScreen extends ConsumerWidget {
  final String betId;
  const BetDetailScreen({super.key, required this.betId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();
    final bets = ref.read(localBetRepositoryProvider).getAllBets(user.id);
    final bet =
        bets.firstWhere((b) => b.id == betId, orElse: () => bets.first);

    final myParticipant = bet.challenger.userId == user.id
        ? bet.challenger
        : bet.opponent;
    final theirParticipant = bet.challenger.userId == user.id
        ? bet.opponent
        : bet.challenger;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battle Details'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CoinDisplay(amount: user.stepCoins),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // vs card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.battleGradient,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BigParticipant(
                  participant: myParticipant,
                  label: 'You',
                  target: bet.targetSteps,
                  isWinning: myParticipant.currentVerifiedSteps >=
                      theirParticipant.currentVerifiedSteps,
                ),
                const Column(
                  children: [
                    Text('⚔️', style: TextStyle(fontSize: 36)),
                    Text('VS',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                  ],
                ),
                _BigParticipant(
                  participant: theirParticipant,
                  label: theirParticipant.userName,
                  target: bet.targetSteps,
                  isWinning: theirParticipant.currentVerifiedSteps >=
                      myParticipant.currentVerifiedSteps,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow('⏱ Duration', bet.duration),
          _DetailRow('🎯 Target Steps', _fmt(bet.targetSteps)),
          _DetailRow('🪙 Stake', '${bet.stakeCoins} StepCoins each'),
          _DetailRow('🏆 Prize Pool', '${bet.prizeCoins} StepCoins'),
          _DetailRow('📅 Created',
              DateFormat('d MMM, h:mm a').format(bet.createdAt)),
          if (bet.expiresAt != null)
            _DetailRow('⏰ Expires',
                DateFormat('d MMM, h:mm a').format(bet.expiresAt!)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Text(
              '⚠️ Step Battle uses verified steps only. '
              'StepCoins are virtual currency — no real money involved. '
              'Disputed results can be reviewed by the integrity engine.',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _BigParticipant extends StatelessWidget {
  final BetParticipant participant;
  final String label;
  final int target;
  final bool isWinning;
  const _BigParticipant(
      {required this.participant,
      required this.label,
      required this.target,
      required this.isWinning});

  @override
  Widget build(BuildContext context) {
    final progress = target > 0
        ? participant.currentVerifiedSteps / target
        : 0.0;
    return Column(
      children: [
        Text(participant.avatarEmoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
        Text(
          _fmt(participant.currentVerifiedSteps),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isWinning ? Colors.white : Colors.white60,
          ),
        ),
        Text(
          '${(progress * 100).clamp(0, 100).round()}%',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
