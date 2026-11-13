import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/bets/bet_models.dart';
import '../../domain/day_key.dart';
import '../auth/session_controller.dart';
import 'bet_rules.dart';
import 'bet_widgets.dart';
import 'bets_environment.dart';
import 'bets_view_models.dart';
import 'points_summary_card.dart';

/// `/bets/ledger` - virtual points balance and own ledger entries.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  LedgerViewModel? _vm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vm != null) return;
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    _vm = LedgerViewModel(
      uid: uid,
      repository: context.read<BetsEnvironment>().repository,
    )..start();
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    return Scaffold(
      appBar: AppBar(leading: const BetsBackButton(), title: const Text('Points ledger')),
      body: SafeArea(
        child: vm == null
            ? const LoadingState()
            : ListenableBuilder(
                listenable: vm,
                builder: (context, _) => RefreshIndicator(
                  onRefresh: vm.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      PointsSummaryCard(
                        balance: vm.points?.available ?? 0,
                        reserved: vm.points?.reserved ?? 0,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total ${formatInt(vm.points?.total ?? 0)} virtual points '
                        '(available + reserved in open bets).',
                        key: const Key('points-total'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      const VirtualPointsNotice(compact: true),
                      const SectionHeader('History'),
                      ..._entries(context, vm),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _entries(BuildContext context, LedgerViewModel vm) {
    if (vm.loadingFirst) {
      return const [Padding(padding: EdgeInsets.only(top: 32), child: LoadingState())];
    }
    if (vm.error != null) {
      return [ErrorState(message: vm.error!, onRetry: vm.refresh)];
    }
    if (vm.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No points activity yet',
          message: 'Rewards, bet stakes and results will show up here.',
        ),
      ];
    }
    return [
      for (final e in vm.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LedgerRow(
            entry: e,
            onTap: e.isBetEntry ? () => context.push(AppRoutes.betDetail(e.refId)) : null,
          ),
        ),
      if (vm.moreError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(vm.moreError!, style: const TextStyle(color: AppColors.error)),
        ),
      if (vm.hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SecondaryButton(
            label: vm.loadingMore ? 'Loading...' : 'Load more',
            onPressed: vm.loadingMore ? null : vm.loadMore,
          ),
        ),
    ];
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, this.onTap});

  final LedgerEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final positive = entry.delta > 0;
    final caption = LedgerText.caption(entry);
    final date = entry.createdAt == null ? null : DayKey.label(DayKey.of(entry.createdAt!));
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(LedgerText.title(entry), style: t.titleSmall),
                if (entry.note.isNotEmpty)
                  Text(entry.note, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
                Text(
                  [
                    ?date,
                    'Balance after: ${formatInt(entry.balanceAfter)} available, '
                        '${formatInt(entry.reservedAfter)} reserved',
                  ].join(' - '),
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                LedgerText.amount(entry),
                style: t.titleMedium?.copyWith(
                  color: positive ? AppColors.primary : AppColors.text,
                ),
              ),
              if (caption != null)
                Text(caption, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
