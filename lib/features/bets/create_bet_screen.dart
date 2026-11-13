import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_directory.dart';
import '../auth/session_controller.dart';
import 'bet_rules.dart';
import 'bet_widgets.dart';
import 'bets_environment.dart';
import 'bets_view_models.dart';

/// `/bets/new[?buddy=<uid>]` - challenge an accepted buddy to a step bet.
class CreateBetScreen extends StatefulWidget {
  const CreateBetScreen({super.key, this.presetBuddyUid});

  final String? presetBuddyUid;

  @override
  State<CreateBetScreen> createState() => _CreateBetScreenState();
}

class _CreateBetScreenState extends State<CreateBetScreen> {
  CreateBetViewModel? _vm;
  late final TextEditingController _target;
  late final TextEditingController _stake;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(text: formatInt(BetLimits.defaultTarget));
    _stake = TextEditingController(text: '${BetLimits.defaultStake}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vm != null) return;
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    final env = context.read<BetsEnvironment>();
    _vm = CreateBetViewModel(
      myUid: uid,
      repository: env.repository,
      buddies: env.buddies,
      clock: context.read<AppDependencies>().clock,
      presetBuddyUid: widget.presetBuddyUid,
    )..start();
  }

  @override
  void dispose() {
    _vm?.dispose();
    _target.dispose();
    _stake.dispose();
    super.dispose();
  }

  Future<void> _submit(CreateBetViewModel vm) async {
    FocusScope.of(context).unfocus();
    final id = await vm.submit();
    if (id == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Challenge sent. Waiting for your buddy to answer.')));
    context.pushReplacement(AppRoutes.betDetail(id));
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    return Scaffold(
      appBar: AppBar(leading: const BetsBackButton(), title: const Text('Create step bet')),
      body: SafeArea(
        child: vm == null
            ? const LoadingState()
            : ListenableBuilder(
                listenable: vm,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    const VirtualPointsNotice(),
                    const SizedBox(height: 16),
                    const SectionHeader('1. Choose a buddy'),
                    _buddies(context, vm),
                    const SizedBox(height: 8),
                    const SectionHeader('2. Set the terms'),
                    _terms(context, vm),
                    const SizedBox(height: 16),
                    _summary(context, vm),
                    const SizedBox(height: 16),
                    if (vm.error != null) ...[
                      _ErrorBanner(message: vm.error!),
                      const SizedBox(height: 12),
                    ],
                    PrimaryButton(
                      label: 'Send challenge',
                      icon: Icons.send_outlined,
                      loading: vm.submitting,
                      onPressed: vm.canSubmit ? () => _submit(vm) : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your buddy can accept or decline. Nothing is reserved from them until they accept.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buddies(BuildContext context, CreateBetViewModel vm) {
    if (vm.buddiesLoading) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingState());
    }
    if (vm.buddiesFailed) {
      return const ErrorState(message: 'Could not load your buddies.', compact: true);
    }
    if (vm.buddies.isEmpty) {
      return AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.group_outlined,
          title: 'You need an accepted buddy first',
          message: 'Step bets are played with buddies. Find a buddy, then come back.',
          actionLabel: 'Find buddies',
          onAction: () => context.go(AppRoutes.buddies),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vm.presetMissing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _ErrorBanner(
              message: 'That student is not one of your accepted buddies. Pick a buddy below.',
            ),
          ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final b in vm.buddies)
                _BuddyTile(
                  buddy: b,
                  selected: vm.selected?.uid == b.uid,
                  onTap: () => vm.selectBuddy(b),
                ),
            ],
          ),
        ),
        if (vm.buddyError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(vm.buddyError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.error)),
          ),
      ],
    );
  }

  Widget _terms(BuildContext context, CreateBetViewModel vm) {
    final t = Theme.of(context).textTheme;
    final digits = FilteringTextInputFormatter.allow(RegExp(r'[0-9, ]'));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('target-field'),
            controller: _target,
            keyboardType: TextInputType.number,
            inputFormatters: [digits],
            decoration: InputDecoration(
              labelText: 'Target steps',
              helperText: 'Verified steps each of you must reach '
                  '(${formatInt(BetLimits.minTarget)}+)',
              errorText: vm.targetError,
              suffixText: 'steps',
            ),
            onChanged: vm.setTargetText,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Duration', style: t.titleSmall),
              const Spacer(),
              Text(
                BetText.durationDays(vm.days),
                key: const Key('duration-label'),
                style: t.titleSmall?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          Slider(
            key: const Key('duration-slider'),
            value: vm.days.toDouble(),
            min: BetLimits.minDays.toDouble(),
            max: BetLimits.maxDays.toDouble(),
            divisions: BetLimits.maxDays - BetLimits.minDays,
            label: '${vm.days}',
            semanticFormatterCallback: (v) => '${v.round()} days',
            onChanged: (v) => vm.setDays(v.round()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('stake-field'),
            controller: _stake,
            keyboardType: TextInputType.number,
            inputFormatters: [digits],
            decoration: InputDecoration(
              labelText: 'Stake (virtual points, each)',
              helperText: vm.available == null
                  ? '${BetLimits.minStake} to ${formatInt(BetLimits.maxStake)} points'
                  : '${BetLimits.minStake} to ${formatInt(BetLimits.maxStake)} points - '
                      'you have ${pointsLabel(vm.available!)} available',
              errorText: vm.stakeError,
              suffixText: 'points',
            ),
            onChanged: vm.setStakeText,
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, CreateBetViewModel vm) {
    final t = Theme.of(context).textTheme;
    final reserved = vm.reservedNow;
    final after = vm.availableAfter;
    return AppCard(
      key: const Key('bet-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happens next', style: t.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Reserved now',
                  value: reserved == null ? '-' : formatInt(reserved),
                  caption: 'points',
                  icon: Icons.lock_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Available after',
                  value: after == null ? '-' : formatInt(after),
                  caption: 'points',
                  icon: Icons.stars_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Bullet(Icons.schedule, BetText.startRule),
          _Bullet(
            Icons.event_available_outlined,
            vm.days == 1
                ? 'If accepted today, it would be played on ${vm.examplePeriodLabel} (IST).'
                : 'If accepted today, it would run ${vm.examplePeriodLabel} (IST).',
          ),
          _Bullet(Icons.hourglass_bottom, BetText.expiry),
          const SizedBox(height: 8),
          Text('How the winner is decided', style: t.titleSmall),
          const SizedBox(height: 4),
          for (final line in BetText.winnerRule) _Bullet(Icons.check_circle_outline, line),
        ],
      ),
    );
  }
}

class _BuddyTile extends StatelessWidget {
  const _BuddyTile({required this.buddy, required this.selected, required this.onTap});

  final BuddySummary buddy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: 'Challenge ${buddy.displayName}',
        child: ListTile(
          key: Key('buddy-${buddy.uid}'),
          onTap: onTap,
          selected: selected,
          selectedTileColor: AppColors.mint,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          leading: AvatarCircle(name: buddy.displayName, photoUrl: buddy.photoUrl, radius: 20),
          title: Text(buddy.displayName, overflow: TextOverflow.ellipsis),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('error-banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEA),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 20, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      );
}
