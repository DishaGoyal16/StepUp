import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/profile_enums.dart';
import '../auth/session_controller.dart';
import 'edit_profile_view_model.dart';

/// `/profile/edit`: edit the permitted profile fields. The hostel is shown
/// read-only (changing it is not allowed here).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  EditProfileViewModel? _vm;
  String? _hostelName;
  bool _hostelRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Created once: the form must not be reset by live profile updates.
    if (_vm != null) return;
    final deps = context.read<AppDependencies>();
    final profile = context.read<SessionController>().profile;
    if (profile == null) return;
    _vm = EditProfileViewModel(
      profile: profile,
      callables: deps.callables,
      picker: deps.photoPicker,
      uploader: deps.photoUploader,
    );
    if (!_hostelRequested && profile.hostelId.isNotEmpty) {
      _hostelRequested = true;
      deps.hostels.load().then((dir) {
        if (!mounted) return;
        setState(() => _hostelName = dir.byId(profile.hostelId)?.displayName ?? profile.hostelId);
      });
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  Future<void> _save(EditProfileViewModel vm) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final outcome = await vm.save();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case SaveOutcome.success:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Profile updated')));
        _leave();
      case SaveOutcome.noChanges:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('No changes to save')));
      case SaveOutcome.invalid || SaveOutcome.failed:
        break; // the error banner in the form shows the message
    }
  }

  /// `go` (not `pop`) so the unsaved-changes guard does not intercept it.
  void _leave() => context.go(AppRoutes.profile);

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const LoadingState(),
      );
    }
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        return PopScope(
          canPop: !vm.hasChanges || vm.saving,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && mounted) _leave();
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Edit profile')),
            body: SafeArea(
              child: Form(
                key: _form,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _PhotoRow(vm: vm, name: vm.displayName, photoUrl: context.read<SessionController>().profile?.photoUrl),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('field-name'),
                          initialValue: vm.displayName,
                          decoration: const InputDecoration(labelText: 'Display name'),
                          textCapitalization: TextCapitalization.words,
                          maxLength: 50,
                          validator: EditProfileViewModel.validateName,
                          onChanged: vm.setDisplayName,
                        ),
                        const SizedBox(height: 8),
                        InputDecorator(
                          decoration: const InputDecoration(labelText: 'Hostel'),
                          child: Row(
                            children: [
                              Expanded(child: Text(_hostelName ?? '...')),
                              const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Text(
                            'Hostel changes are not available in the app.',
                            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('field-bio'),
                          initialValue: vm.bio,
                          decoration: const InputDecoration(
                            labelText: 'Bio',
                            hintText: 'A line about you and how you like to move',
                          ),
                          maxLines: 3,
                          maxLength: kBioMaxLength,
                          validator: EditProfileViewModel.validateBio,
                          onChanged: vm.setBio,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const ValueKey('field-daily-goal'),
                          initialValue: vm.dailyGoalText,
                          decoration: const InputDecoration(
                            labelText: 'Daily step goal',
                            helperText: '$kMinDailyGoal to $kMaxDailyGoal steps',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: EditProfileViewModel.validateDailyGoal,
                          onChanged: vm.setDailyGoalText,
                        ),
                        const SectionHeader('Fitness level'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final l in FitnessLevel.values)
                              ChoiceChip(
                                label: Text(l.label),
                                selected: vm.fitnessLevel == l,
                                onSelected: (_) => vm.setFitnessLevel(l),
                              ),
                          ],
                        ),
                        const SectionHeader('Sports interests'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in {...kSportsOptions, ...vm.sports})
                              FilterChip(
                                label: Text(s),
                                selected: vm.sports.contains(s),
                                onSelected: (_) => vm.toggleSport(s),
                              ),
                          ],
                        ),
                        const SectionHeader('Preferred activity'),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('field-activity'),
                          initialValue: vm.preferredActivity,
                          isExpanded: true,
                          decoration: const InputDecoration(hintText: 'Choose one'),
                          items: [
                            for (final s in {
                              ...kSportsOptions,
                              if ((vm.preferredActivity ?? '').isNotEmpty) vm.preferredActivity!,
                            })
                              DropdownMenuItem(value: s, child: Text(s)),
                          ],
                          onChanged: vm.setPreferredActivity,
                        ),
                        const SectionHeader('Preferred time'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in PreferredTime.values)
                              ChoiceChip(
                                label: Text(p.label),
                                selected: vm.preferredTime == p,
                                onSelected: (_) => vm.setPreferredTime(p),
                              ),
                          ],
                        ),
                        const SectionHeader('Goals'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in {...kGoalOptions, ...vm.goals})
                              FilterChip(
                                label: Text(g),
                                selected: vm.goals.contains(g),
                                onSelected: (_) => vm.toggleGoal(g),
                              ),
                          ],
                        ),
                        const SectionHeader('Availability'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in kWeekdays)
                              FilterChip(
                                label: Text(d[0] + d.substring(1).toLowerCase()),
                                selected: vm.availability.contains(d),
                                onSelected: (_) => vm.toggleDay(d),
                              ),
                          ],
                        ),
                        const SectionHeader('Looking for'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final b in BuddyType.values)
                              ChoiceChip(
                                label: Text(b.label),
                                selected: vm.buddyType == b,
                                onSelected: (_) => vm.setBuddyType(b),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (vm.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    vm.error!,
                                    key: const ValueKey('edit-error'),
                                    style: t.bodyMedium?.copyWith(color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        PrimaryButton(
                          label: 'Save changes',
                          loading: vm.saving,
                          onPressed: () => _save(vm),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.vm, required this.name, required this.photoUrl});

  final EditProfileViewModel vm;
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final showUrl = vm.pickedPhotoPath == null && !vm.removePhoto ? photoUrl : null;
    return Row(
      children: [
        AvatarCircle(name: name, photoUrl: showUrl, radius: 36),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vm.pickedPhotoPath != null)
                Text('New photo selected', style: t.bodyMedium?.copyWith(color: AppColors.primary)),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: vm.saving ? null : vm.pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(vm.hasPhoto ? 'Change photo' : 'Add photo'),
                  ),
                  if (vm.hasPhoto)
                    TextButton(
                      onPressed: vm.saving ? null : vm.clearPhoto,
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
