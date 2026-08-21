import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/gamification_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.read(localWalletRepositoryProvider).getWallet();

    return Scaffold(
      appBar: AppBar(title: const Text('StepCoins Wallet 🪙')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          _WalletHeroCard(balance: wallet.balance),
          const SizedBox(height: 24),
          _DisclaimerCard(),
          const SizedBox(height: 24),
          const SectionHeader(title: '📋 Transaction History'),
          const SizedBox(height: 12),
          if (wallet.transactions.isEmpty)
            const _EmptyTransactions()
          else
            ...wallet.transactions.asMap().entries.map((e) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TransactionTile(tx: e.value)
                      .animate(delay: Duration(milliseconds: 50 * e.key))
                      .fadeIn()
                      .slideX(begin: 0.05),
                )),
        ],
      ),
    );
  }
}

class _WalletHeroCard extends StatelessWidget {
  final int balance;
  const _WalletHeroCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.glow(AppColors.accent),
      ),
      child: Column(
        children: [
          const Text('🪙', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            '$balance',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ).animate().fadeIn(duration: 500.ms),
          const Text(
            'STEPCOINS',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 3,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: const Text(
              'Virtual currency — No real money value',
              style: TextStyle(
                  fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95));
  }
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ℹ️', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Text('About StepCoins',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• StepCoins are a virtual in-app reward — they have no real monetary value.\n'
            '• Earned by completing verified steps, challenges, and sessions.\n'
            '• Used to place Step Battle wagers with other students.\n'
            '• No real money changes hands at any point.\n'
            '• This is a prototype system for campus motivation only.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
    final color = isCredit ? AppColors.primary : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                isCredit ? '⬆️' : '⬇️',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.description,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  DateFormat('d MMM, h:mm a').format(tx.timestamp),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${tx.amount} 🪙',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Text('📭', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('No transactions yet',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
