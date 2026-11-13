import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/validators.dart';
import '../onboarding/profile_form_fields.dart';
import 'auth_widgets.dart';
import 'register_view_model.dart';

/// Two-step registration (account, then profile answers).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final RegisterViewModel _vm;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final deps = context.read<AppDependencies>();
    _vm = RegisterViewModel(
      auth: deps.auth,
      draftStore: deps.draftStore,
      hostels: deps.hostels,
      photoPicker: deps.photoPicker,
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _next() {
    if (_formKey.currentState?.validate() ?? false) _vm.goToProfileStep();
  }

  Future<void> _create() => _vm.submit(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _vm,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        return AuthScaffold(
          title: 'Create your account',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Step ${_vm.step + 1} of 2 - ${_vm.step == 0 ? 'Account' : 'Your profile'}',
                style: t.labelLarge?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_vm.step + 1) / 2,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: AppColors.mint,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_vm.error != null) ...[ErrorBanner(_vm.error!), const SizedBox(height: 12)],
              if (_vm.step == 0) _accountStep(t) else _profileStep(),
            ],
          ),
        );
      },
    );
  }

  Widget _accountStep(TextTheme t) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
            validator: Validators.fullName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
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
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'At least 8 characters, with a letter and a number',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: Validators.password,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) => Validators.confirmPassword(_password.text, v),
          ),
          const SizedBox(height: 12),
          Text(
            'Only @thapar.edu addresses can register. We will email a link to that inbox; '
            'you will confirm it before you can use the app.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Next', onPressed: _next),
        ],
      ),
    );
  }

  Widget _profileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileFormFields(controller: _vm.form, onPickPhoto: _vm.pickPhoto),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Create account', loading: _vm.busy, onPressed: _create),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _vm.busy ? null : _vm.backToAccountStep,
          child: const Text('Back'),
        ),
      ],
    );
  }
}
