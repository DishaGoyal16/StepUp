import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import '../../data/admin/admin_settings_spec.dart';
import 'admin_support.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsViewModel>(
      create: (c) => SettingsViewModel(c.read<AdminRepository>())..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return AdminPage(
      title: 'Settings',
      child: AdminAsyncBody(
        loading: vm.loading,
        error: vm.error,
        denied: vm.denied,
        onRetry: vm.load,
        child: _SettingsForm(values: vm.values),
      ),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.values});

  final Map<String, int> values;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final Map<String, TextEditingController> _c;
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    _c = {
      for (final s in adminSettingSpecs)
        s.key: TextEditingController(text: '${widget.values[s.key] ?? s.defaultValue}'),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _raw => {for (final e in _c.entries) e.key: e.value.text};

  Future<void> _save(SettingsViewModel vm) async {
    final raw = _raw;
    final errs = validateSettingsForm(raw);
    setState(() => _errors = errs);
    if (errs.isNotEmpty) {
      showAdminResult(context, AdminResult.fail(errs.values.first));
      return;
    }
    final changes = vm.changesFrom(raw);
    if (changes.isEmpty) {
      showAdminResult(context, const AdminResult.fail('No changes to save.'));
      return;
    }
    final label = {for (final s in adminSettingSpecs) s.key: s.label};
    final lines = [
      for (final e in changes.entries) '${label[e.key]}: ${vm.values[e.key]} -> ${e.value}',
    ];
    final ok = await confirmAction(
      context,
      title: 'Save ${changes.length} change(s)?',
      message: '${lines.join('\n')}\n\nThese apply to every student immediately.',
      confirmLabel: 'Save settings',
    );
    if (!ok || !mounted) return;
    final r = await vm.save(raw);
    if (mounted) showAdminResult(context, r);
  }

  Future<void> _seed(SettingsViewModel vm) async {
    final ok = await confirmAction(
      context,
      title: 'Load default data?',
      message: 'Creates any missing default hostels, settings, badges and challenge templates. '
          'Existing documents are never overwritten.',
      confirmLabel: 'Load defaults',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final r = await vm.seed();
    showAdminResultOn(messenger, r);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final t = Theme.of(context).textTheme;
    final groups = <String>[];
    for (final s in adminSettingSpecs) {
      if (!groups.contains(s.group)) groups.add(s.group);
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Only whole numbers inside the allowed range are accepted. The server checks every value again.',
          style: t.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        for (final g in groups) ...[
          SectionHeader(g),
          for (final s in adminSettingSpecs.where((x) => x.group == g))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                key: ValueKey('setting-${s.key}'),
                controller: _c[s.key],
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_errors.containsKey(s.key)) setState(() => _errors = {..._errors}..remove(s.key));
                },
                decoration: InputDecoration(
                  labelText: s.label,
                  helperText: '${s.help} (${s.min}-${s.max}${s.unit == null ? '' : ' ${s.unit}'})',
                  helperMaxLines: 2,
                  errorText: _errors[s.key],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Save settings',
          icon: Icons.save_outlined,
          loading: vm.saving,
          onPressed: () => _save(vm),
        ),
        const SizedBox(height: 24),
        const SectionHeader('Badges and rewards'),
        SecondaryButton(
          label: 'Edit badges',
          icon: Icons.military_tech_outlined,
          onPressed: () => context.push(AdminPaths.badges),
        ),
        const SectionHeader('Default data'),
        Text(
          'Fills in anything missing (hostels, settings, badges, challenge templates). '
          'It never overwrites what you edited.',
          style: t.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          label: 'Load default data',
          icon: Icons.download_outlined,
          onPressed: vm.saving ? null : () => _seed(vm),
        ),
      ],
    );
  }
}

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BadgesViewModel>(
      create: (c) => BadgesViewModel(c.read<AdminRepository>())..load(),
      child: const _BadgesView(),
    );
  }
}

class _BadgesView extends StatelessWidget {
  const _BadgesView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BadgesViewModel>();
    final t = Theme.of(context).textTheme;
    return AdminPage(
      title: 'Badges',
      parent: '/admin',
      child: AdminAsyncBody(
        loading: vm.loading,
        error: vm.error,
        denied: vm.denied,
        hasData: vm.badges.isNotEmpty,
        onRetry: vm.load,
        child: vm.badges.isEmpty
            ? const EmptyState(
                icon: Icons.military_tech_outlined,
                title: 'No badges yet',
                message: 'Load the default data from Settings to create the badge catalogue.',
              )
            : RefreshIndicator(
                onRefresh: vm.load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: vm.badges.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final b = vm.badges[i];
                    return AppCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.title, style: t.titleMedium),
                                Text(b.description, style: t.bodyMedium),
                                const SizedBox(height: 4),
                                Text(
                                  '${b.id}  -  ${b.points} pts',
                                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit ${b.title}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, vm, b),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, BadgesViewModel vm, BadgeDefinition b) async {
    final edited = await showDialog<BadgeDefinition>(
      context: context,
      builder: (_) => _BadgeDialog(badge: b),
    );
    if (edited == null || !context.mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Save "${edited.title.trim()}"?',
      message: 'Title, description and points are updated for every student. '
          'Badges are still earned by the same rule.',
      confirmLabel: 'Save badge',
    );
    if (!ok || !context.mounted) return;
    final r = await vm.save(edited);
    if (context.mounted) showAdminResult(context, r);
  }
}

class _BadgeDialog extends StatefulWidget {
  const _BadgeDialog({required this.badge});

  final BadgeDefinition badge;

  @override
  State<_BadgeDialog> createState() => _BadgeDialogState();
}

class _BadgeDialogState extends State<_BadgeDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.badge.title);
  late final TextEditingController _desc = TextEditingController(text: widget.badge.description);
  late final TextEditingController _points = TextEditingController(text: '${widget.badge.points}');
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _points.dispose();
    super.dispose();
  }

  void _submit() {
    final points = int.tryParse(_points.text.trim());
    final edited = widget.badge.copyWith(
      title: _title.text,
      description: _desc.text,
      points: points ?? -1,
    );
    final errs = edited.validate();
    if (errs.isNotEmpty) {
      setState(() => _errors = errs);
      return;
    }
    Navigator.pop(context, edited);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.badge.id}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: 'Title', errorText: _errors['title']),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'Description', errorText: _errors['description']),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _points,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Reward points',
                  helperText: 'Virtual points, paid once per student',
                  errorText: _errors['points'] ?? _errors['icon'] ?? _errors['rule'],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
