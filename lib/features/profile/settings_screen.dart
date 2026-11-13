import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/user_profile.dart';
import '../auth/session_controller.dart';
import 'settings_view_model.dart';

/// The credits line shown in the About card (text only; no accounts or roles).
const String kCreditsLine = 'Built for a healthier campus — Project Lead: Disha';

/// `/profile/settings`: notification preferences, privacy, account and about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsViewModel? _vm;

  static const Map<String, ({String title, String subtitle})> _notificationLabels = {
    'buddy': (title: 'Buddy requests', subtitle: 'New requests and accepted buddies'),
    'challenges': (title: 'Challenges', subtitle: 'Invites, results and hostel results'),
    'bets': (title: 'Step bets', subtitle: 'Bet invites and results'),
    'leaderboard': (title: 'Leaderboard', subtitle: 'Rank changes and results'),
    'reminders': (title: 'Reminders', subtitle: 'Daily nudges for your active challenges'),
  };

  static const Map<String, ({String title, String subtitle})> _privacyLabels = {
    'discoverable': (title: 'Discoverable by other students', subtitle: 'Appear in buddy search'),
    'showHostel': (title: 'Show my hostel', subtitle: 'On your public profile'),
    'showWeeklySteps': (title: 'Show my weekly steps', subtitle: 'On your public profile'),
    'showOnLeaderboards': (title: 'Show me on leaderboards', subtitle: 'Hidden students are not listed'),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vm ??= SettingsViewModel(
      callables: context.read<AppDependencies>().callables,
      functions: context.read<AppDependencies>().functions,
      auth: context.read<AppDependencies>().auth,
      signOut: context.read<AppDependencies>().signOut,
    );
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  void _flushFeedback(SettingsViewModel vm) {
    final f = vm.takeFeedback();
    if (f == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(f.text),
          backgroundColor: f.isError ? AppColors.error : null,
        ),
      );
  }

  Future<void> _confirmLogout(SettingsViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Your unsent steps are synced first, then you are signed out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) await vm.logout();
  }

  Future<void> _confirmDelete(SettingsViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'This sends a deletion request to the StepUp admins. It is not instant: '
          'an admin reviews and processes it, and your account stays as it is until then. '
          'Your points and badges cannot be recovered once the account is deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok == true) await vm.requestDeletion();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm!;
    final profile = context.watch<SessionController>().profile;
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const LoadingState(),
      );
    }
    vm.reconcile(profile);
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _flushFeedback(vm);
        });
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    const SectionHeader(
                      'Notifications',
                      subtitle: 'Choose which push notifications you get. '
                          'Everything still appears in your notification list.',
                    ),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final k in kNotificationKeys)
                            _SwitchRow(
                              vm: vm,
                              profile: profile,
                              group: SettingsGroup.notificationPrefs,
                              keyName: k,
                              title: _notificationLabels[k]!.title,
                              subtitle: _notificationLabels[k]!.subtitle,
                            ),
                        ],
                      ),
                    ),
                    const SectionHeader('Privacy'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final k in kPrivacyKeys)
                            _SwitchRow(
                              vm: vm,
                              profile: profile,
                              group: SettingsGroup.privacy,
                              keyName: k,
                              title: _privacyLabels[k]!.title,
                              subtitle: _privacyLabels[k]!.subtitle,
                            ),
                        ],
                      ),
                    ),
                    const SectionHeader('Account'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email', style: t.labelLarge?.copyWith(color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          SelectableText(profile.email, key: const ValueKey('account-email')),
                          const SizedBox(height: 16),
                          SecondaryButton(
                            label: 'Send password reset email',
                            icon: Icons.mail_outline,
                            onPressed: vm.resettingPassword || profile.email.isEmpty
                                ? null
                                : () => vm.sendPasswordReset(profile.email),
                          ),
                          const SizedBox(height: 12),
                          SecondaryButton(
                            label: 'Log out',
                            icon: Icons.logout,
                            onPressed: vm.loggingOut ? null : () => _confirmLogout(vm),
                          ),
                          const SizedBox(height: 12),
                          _DeleteRow(vm: vm, profile: profile, onTap: () => _confirmDelete(vm)),
                        ],
                      ),
                    ),
                    if (profile.isAdmin) ...[
                      const SectionHeader('Admin'),
                      AppCard(
                        onTap: () => context.push(AppRoutes.admin),
                        child: const Row(
                          children: [
                            Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
                            SizedBox(width: 12),
                            Expanded(child: Text('Open admin tools')),
                            Icon(Icons.chevron_right, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ],
                    const SectionHeader('About'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('StepUp', style: t.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Version ${context.read<AppDependencies>().config.appVersion}',
                            style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 12),
                          Text(kCreditsLine, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.vm,
    required this.profile,
    required this.group,
    required this.keyName,
    required this.title,
    required this.subtitle,
  });

  final SettingsViewModel vm;
  final UserProfile profile;
  final SettingsGroup group;
  final String keyName;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: ValueKey('switch-${group.field}-$keyName'),
      title: Text(title),
      subtitle: Text(subtitle),
      value: vm.valueOf(profile, group, keyName),
      onChanged: (v) => vm.setSwitch(profile, group, keyName, v),
    );
  }
}

class _DeleteRow extends StatelessWidget {
  const _DeleteRow({required this.vm, required this.profile, required this.onTap});

  final SettingsViewModel vm;
  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pending = vm.deletionRequested || profile.status == 'DELETION_REQUESTED';
    final t = Theme.of(context).textTheme;
    if (pending) {
      return Row(
        children: [
          const Icon(Icons.hourglass_top, size: 20, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Account deletion requested. An admin will review it.',
              key: const ValueKey('deletion-pending'),
              style: t.bodyMedium,
            ),
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      key: const ValueKey('delete-account'),
      onPressed: vm.requestingDeletion ? null : onTap,
      icon: const Icon(Icons.delete_outline),
      label: const Text('Request account deletion'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
    );
  }
}
