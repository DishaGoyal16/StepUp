import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'auth_widgets.dart';

/// "Check your inbox". The only screen an unverified account can see:
/// Resend, "I verified" and Sign out. Also polls the verification state.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.pollInterval = const Duration(seconds: 5),
    this.resendCooldown = const Duration(seconds: 30),
  });

  /// How often to re-check verification automatically (null disables).
  final Duration? pollInterval;
  final Duration resendCooldown;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  bool _busy = false;
  bool _checking = false;
  String? _error;
  String? _info;
  DateTime? _lastSent;

  @override
  void initState() {
    super.initState();
    final p = widget.pollInterval;
    if (p != null) _timer = Timer.periodic(p, (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    final deps = context.read<AppDependencies>();
    final last = _lastSent;
    if (last != null) {
      final wait = widget.resendCooldown - deps.clock.now().difference(last);
      if (wait > Duration.zero) {
        setState(() {
          _error = null;
          _info = 'Please wait ${wait.inSeconds + 1} seconds before asking for another email.';
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await deps.auth.sendVerificationEmail();
      _lastSent = deps.clock.now();
      if (mounted) setState(() => _info = 'Verification email sent. Check your inbox and spam folder.');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    final deps = context.read<AppDependencies>();
    if (!silent) {
      setState(() {
        _busy = true;
        _error = null;
        _info = null;
      });
    }
    try {
      final user = await deps.auth.reloadUser();
      if (!silent && mounted && !(user?.emailVerified ?? false)) {
        setState(() => _info = 'Not verified yet. Open the link in the email, then tap "I verified" again.');
      }
      // When verified, the session stream moves the router on automatically.
    } on AppException catch (e) {
      if (!silent && mounted) setState(() => _error = e.message);
    } finally {
      _checking = false;
      if (!silent && mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    final email = deps.auth.currentUser?.email ?? 'your Thapar email';
    final t = Theme.of(context).textTheme;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mark_email_unread_outlined, size: 64, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text('Check your inbox', style: t.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'We sent a verification link to $email. Open it, then come back and tap "I verified".',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This only confirms that you can read this @thapar.edu inbox.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          if (_info != null) ...[InfoBanner(_info!), const SizedBox(height: 12)],
          PrimaryButton(label: 'I verified', loading: _busy, onPressed: _check),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Resend verification email',
            icon: Icons.refresh,
            onPressed: _busy ? null : _resend,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : () => deps.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
