import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/auth/auth_repository.dart';
import '../../domain/thapar_email.dart';
import '../../domain/validators.dart';
import 'auth_widgets.dart';

/// Sends a password-reset e-mail. The confirmation is deliberately generic so
/// the screen never reveals whether an account exists.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AppException catch (e) {
      // "user-not-found" style failures are not surfaced (no account probing).
      if (e.code == 'invalid-credential' || e.code == 'user-not-found') {
        if (mounted) setState(() => _sent = true);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AuthScaffold(
      title: 'Reset password',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your Thapar email and we will send you a link to choose a new password.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            if (_sent) ...[
              const InfoBanner(
                'If an account exists for that address, a reset link is on its way.',
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Thapar email',
                hintText: 'name@thapar.edu',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Send reset link',
              loading: _busy,
              onPressed: ThaparEmail.isValid(_email.text) ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}
