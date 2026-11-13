import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/stepup_logo.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_widgets.dart';
import 'onboarding_view_model.dart';
import 'profile_form_fields.dart';

/// Shown to a verified user who has no profile yet. Pre-filled with the
/// answers given during registration.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingViewModel? _vm;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vm != null) return;
    final deps = context.read<AppDependencies>();
    final user = deps.auth.currentUser;
    if (user == null) return;
    _vm = OnboardingViewModel(
      user: user,
      profiles: deps.profiles,
      draftStore: deps.draftStore,
      hostels: deps.hostels,
      photoUploader: deps.photoUploader,
      photoPicker: deps.photoPicker,
    )..addListener(_syncName);
    _vm!.load();
  }

  void _syncName() {
    final n = _vm!.form.draft.displayName;
    if (_name.text != n) _name.text = n;
  }

  @override
  void dispose() {
    _vm?.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final deps = context.read<AppDependencies>();
    final ok = await _vm!.submit();
    if (ok) deps.session.retryProfile(); // pick up the new profile right away
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) return const Scaffold(body: LoadingState());
    final t = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        return AuthScaffold(
          child: vm.loading
              ? const Padding(padding: EdgeInsets.all(48), child: LoadingState())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: StepUpLogo(size: 56, showName: false)),
                    const SizedBox(height: AppSpacing.md),
                    Text('Finish setting up', style: t.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'Your email is verified. Tell us a bit about you so we can find buddies and challenges.',
                      style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    if (vm.restoredDraft) ...[
                      const SizedBox(height: 12),
                      const InfoBanner('We kept the answers you gave while registering. Check them and continue.'),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ProfileFormFields(
                      controller: vm.form,
                      includeName: true,
                      nameController: _name,
                      onPickPhoto: vm.pickPhoto,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (vm.error != null) ...[ErrorBanner(vm.error!), const SizedBox(height: 12)],
                    if (vm.notice != null) ...[InfoBanner(vm.notice!), const SizedBox(height: 12)],
                    PrimaryButton(label: 'Finish', loading: vm.busy, onPressed: _submit),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: vm.busy ? null : () => context.read<AppDependencies>().signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
