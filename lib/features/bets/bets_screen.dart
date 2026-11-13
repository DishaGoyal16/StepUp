import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/widgets.dart';
import '../auth/session_controller.dart';
import 'bet_widgets.dart';
import 'bets_environment.dart';
import 'bets_view_models.dart';
import 'points_summary_card.dart';
import 'bet_rules.dart';

/// `/bets` - my step bets by segment, with my virtual points on top.
class BetsScreen extends StatefulWidget {
  const BetsScreen({super.key});

  @override
  State<BetsScreen> createState() => _BetsScreenState();
}

class _BetsScreenState extends State<BetsScreen> {
  BetsListViewModel? _vm;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    if (_vm == null || _uid != uid) {
      _vm?.dispose();
      _uid = uid;
      _vm = BetsListViewModel(
        uid: uid,
        repository: context.read<BetsEnvironment>().repository,
      )..start();
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    final clock = context.read<AppDependencies>().clock;
    return Scaffold(
      appBar: AppBar(
        leading: const BetsBackButton(),
        title: const Text('Step bets'),
        actions: [
          IconButton(
            tooltip: 'Points ledger',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push(BetsPaths.ledger),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.betsCreate),
        icon: const Icon(Icons.add),
        label: const Text('New bet'),
      ),
      body: SafeArea(
        child: vm == null
            ? const LoadingState()
            : ListenableBuilder(
                listenable: vm,
                builder: (context, _) => _body(context, vm, clock.now),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, BetsListViewModel vm, DateTime Function() now) {
    if (vm.hasError) {
      return ErrorState(message: 'Could not load your bets.', onRetry: vm.retry);
    }
    final points = vm.points;
    final visible = vm.visible;
    return RefreshIndicator(
      onRefresh: () async => vm.retry(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          PointsSummaryCard(
            balance: points?.available ?? 0,
            reserved: points?.reserved ?? 0,
            onTap: () => context.push(BetsPaths.ledger),
          ),
          const SizedBox(height: 12),
          const VirtualPointsNotice(compact: true),
          const SizedBox(height: 12),
          FilterChipsRow<BetSegment>(
            options: BetSegment.values,
            selected: vm.segment,
            onSelected: vm.selectSegment,
            labelOf: (s) {
              final n = vm.count(s);
              return n == 0 ? s.label : '${s.label} ($n)';
            },
          ),
          const SizedBox(height: 12),
          if (vm.loading)
            const Padding(padding: EdgeInsets.only(top: 48), child: LoadingState())
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.directions_walk,
                title: vm.segment.emptyTitle,
                message: 'Challenge a buddy to a friendly step bet with virtual points.',
                actionLabel: 'Create a bet',
                onAction: () => context.push(AppRoutes.betsCreate),
              ),
            )
          else
            Ticking(
              builder: (context) => Column(
                children: [
                  for (final b in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BetCard(
                        bet: b,
                        myUid: vm.uid,
                        now: now(),
                        onTap: () => context.push(AppRoutes.betDetail(b.id)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
