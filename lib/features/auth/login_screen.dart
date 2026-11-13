import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/widgets/stepup_logo.dart';
import '../../data/auth/auth_repository.dart';
import '../../domain/thapar_email.dart';
import '../../domain/validators.dart';
import 'auth_widgets.dart';

/// Welcome / login. Signing in successfully hands over to the router guard:
/// unverified accounts land on the verification screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(_changed);
    _password.addListener(_changed);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _error = null);

  bool get _canSubmit =>
      !_busy && ThaparEmail.isValid(_email.text) && _password.text.isNotEmpty;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthRepository>();
    await _run(() => auth.signIn(email: _email.text, password: _password.text));
  }

  Future<void> _google() async {
    final auth = context.read<AuthRepository>();
    await _run(() async {
      await auth.signInWithGoogle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    final t = Theme.of(context).textTheme;
    return AuthScaffold(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: StepUpLogo()),
            const SizedBox(height: AppSpacing.lg),
            Text('Welcome to StepUp', style: t.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Sign in with your Thapar email',
              style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Thapar email',
                hintText: 'name@thapar.edu',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _canSubmit ? _login() : null,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Validators.loginPassword,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => context.push(AppRoutes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'Login',
              loading: _busy,
              onPressed: _canSubmit ? _login : null,
            ),
            if (config.googleSignInEnabled) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Continue with Google',
                icon: Icons.account_circle_outlined,
                onPressed: _busy ? null : _google,
              ),
              const SizedBox(height: 4),
              Text(
                'Only @thapar.edu Google accounts are accepted.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('New to StepUp?'),
                TextButton(
                  onPressed: _busy ? null : () => context.push(AppRoutes.register),
                  child: const Text('Register'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
