import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/challenges/challenge_repository.dart';
import '../auth/session_controller.dart';
import 'challenge_logic.dart';
import 'challenge_widgets.dart';
import 'create_buddy_view_model.dart';

/// "Challenge a buddy" form (`/challenges/new-buddy`, optional `?buddy=<uid>`).
class CreateBuddyChallengeScreen extends StatelessWidget {
  const CreateBuddyChallengeScreen({super.key, this.initialBuddyUid});

  final String? initialBuddyUid;

  @override
  Widget build(BuildContext context) {
    final user = context.read<SessionController>().user;
    if (user == null) return const Scaffold(body: LoadingState());
    return ChangeNotifierProvider<CreateBuddyChallengeViewModel>(
      key: ValueKey('${user.uid}/$initialBuddyUid'),
      create: (c) => CreateBuddyChallengeViewModel(
        repository: c.read<ChallengeRepository>(),
        uid: user.uid,
        initialBuddyUid: initialBuddyUid,
      )..start(),
      child: const _CreateForm(),
    );
  }
}

class _CreateForm extends StatefulWidget {
  const _CreateForm();

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  final _title = TextEditingController();
  late final TextEditingController _target;

  @override
  void initState() {
    super.initState();
    final initial = context.read<CreateBuddyChallengeViewModel>().targetSteps;
    _target = TextEditingController(text: initial?.toString() ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _submit(CreateBuddyChallengeViewModel vm) async {
    final out = await vm.submit();
    if (!mounted) return;
    showResult(context, out.result);
    final id = out.challengeId;
    if (id != null) {
      // Replace the form with the new challenge so Back returns to the list.
      context.pushReplacement(AppRoutes.challengeDetail(id));
    }
  }

  void _setTarget(CreateBuddyChallengeViewModel vm, int steps) {
    _target.text = '$steps';
    vm.setTargetText('$steps');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateBuddyChallengeViewModel>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Challenge a buddy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const NoteBanner(
              icon: Icons.schedule_outlined,
              text: 'Your buddy gets an invitation. The challenge starts at the next midnight (IST) after '
                  'they accept, and runs for the number of days you choose. Only verified steps count.',
            ),
            if (vm.initialNotice != null) ...[
              const SizedBox(height: 12),
              NoteBanner(icon: Icons.info_outline, text: vm.initialNotice!),
            ],
            const SizedBox(height: 16),
            Text('Choose a buddy', style: t.titleMedium),
            const SizedBox(height: 8),
            _BuddyChooser(vm: vm),
            if (vm.buddyError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(vm.buddyError!, style: t.bodySmall?.copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('title-field'),
              controller: _title,
              maxLength: CreateBuddyChallengeViewModel.maxTitle,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                hintText: 'e.g. Weekend walk-off',
              ),
              onChanged: vm.setTitle,
            ),
            const SizedBox(height: 8),
            Text('Duration', style: t.titleMedium),
            Row(
              children: [
                IconButton(
                  tooltip: 'One day less',
                  onPressed: vm.durationDays > CreateBuddyChallengeViewModel.minDays
                      ? () => vm.setDuration(vm.durationDays - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: Text(
                    vm.durationDays == 1 ? '1 day' : '${vm.durationDays} days',
                    key: const ValueKey('duration-label'),
                    textAlign: TextAlign.center,
                    style: t.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'One day more',
                  onPressed: vm.durationDays < CreateBuddyChallengeViewModel.maxDays
                      ? () => vm.setDuration(vm.durationDays + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Slider(
              value: vm.durationDays.toDouble(),
              min: CreateBuddyChallengeViewModel.minDays.toDouble(),
              max: CreateBuddyChallengeViewModel.maxDays.toDouble(),
              divisions: CreateBuddyChallengeViewModel.maxDays - CreateBuddyChallengeViewModel.minDays,
              label: '${vm.durationDays}',
              onChanged: (v) => vm.setDuration(v.round()),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('target-field'),
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: InputDecoration(
                labelText: 'Target verified steps',
                helperText: 'Between 1,000 and 1,000,000',
                errorText: vm.targetError,
              ),
              onChanged: vm.setTargetText,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final steps in const [10000, 25000, 50000, 100000])
                  ActionChip(
                    label: Text(formatCount(steps)),
                    onPressed: () => _setTarget(vm, steps),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (vm.targetSteps != null && vm.isValid)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'First to ${formatCount(vm.targetSteps!)} verified steps within '
                  '${vm.durationDays == 1 ? '1 day' : '${vm.durationDays} days'} wins.',
                  style: t.bodyMedium,
                ),
              ),
            PrimaryButton(
              label: 'Send challenge',
              icon: Icons.send_outlined,
              loading: vm.submitting,
              onPressed: () => _submit(vm),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuddyChooser extends StatelessWidget {
  const _BuddyChooser({required this.vm});

  final CreateBuddyChallengeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final state = vm.buddies;
    if (state.loading) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingState());
    }
    if (state.error != null) {
      return ErrorState(message: state.error!, onRetry: vm.retry, compact: true);
    }
    final buddies = state.data ?? const <BuddySummary>[];
    if (buddies.isEmpty) {
      return AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.group_outlined,
          title: 'No buddies yet',
          message: 'Buddy challenges are between accepted buddies. Find a buddy first.',
          actionLabel: 'Find buddies',
          onAction: () => context.go(AppRoutes.buddies),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final b in buddies)
            ListTile(
              key: ValueKey('buddy-${b.uid}'),
              selected: vm.selectedBuddyUid == b.uid,
              selectedTileColor: AppColors.mint,
              leading: AvatarCircle(name: b.displayName, photoUrl: b.photoUrl, radius: 20),
              title: Text(b.displayName),
              trailing: Icon(
                vm.selectedBuddyUid == b.uid ? Icons.check_circle : Icons.radio_button_unchecked,
                color: vm.selectedBuddyUid == b.uid ? AppColors.primary : AppColors.textMuted,
              ),
              onTap: () => vm.selectBuddy(b.uid),
            ),
        ],
      ),
    );
  }
}
