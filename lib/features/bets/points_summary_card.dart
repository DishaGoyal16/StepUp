import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'bet_rules.dart';

/// Compact summary of the student's VIRTUAL points: available (spendable on
/// bets) and reserved (locked in open bets). Reusable on other screens (e.g.
/// profile): `PointsSummaryCard(balance: p.pointsBalance, reserved:
/// p.pointsReserved, onTap: () => context.push('/bets/ledger'))`.
///
/// [balance] is the AVAILABLE balance (`users.pointsBalance`).
class PointsSummaryCard extends StatelessWidget {
  const PointsSummaryCard({
    super.key,
    required this.balance,
    required this.reserved,
    this.onTap,
  });

  final int balance;
  final int reserved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
            child: const Icon(Icons.stars_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Virtual points', style: t.labelLarge?.copyWith(color: AppColors.textMuted)),
                Text(
                  formatInt(balance),
                  key: const Key('points-available'),
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text('available', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Reserved in bets', style: t.labelMedium?.copyWith(color: AppColors.textMuted)),
              Text(
                formatInt(reserved),
                key: const Key('points-reserved'),
                style: t.titleMedium,
              ),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ],
      ),
    );
  }
}
