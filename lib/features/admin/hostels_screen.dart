import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import '../../domain/hostel.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

class HostelsScreen extends StatelessWidget {
  const HostelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HostelsViewModel>(
      create: (c) => HostelsViewModel(c.read<AdminRepository>())..load(),
      child: const _HostelsView(),
    );
  }
}

class _HostelsView extends StatelessWidget {
  const _HostelsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HostelsViewModel>();
    return AdminPage(
      title: 'Hostels',
      floatingActionButton: (vm.error == null && !vm.loading)
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context, vm, null),
              icon: const Icon(Icons.add),
              label: const Text('Add hostel'),
            )
          : null,
      child: AdminAsyncBody(
        loading: vm.loading,
        error: vm.error,
        denied: vm.denied,
        hasData: vm.hostels.isNotEmpty,
        onRetry: vm.load,
        child: vm.hostels.isEmpty
            ? EmptyState(
                icon: Icons.apartment_outlined,
                title: 'No hostels yet',
                message: 'Students cannot register without hostels. Load the 18 default hostels '
                    'or add one yourself.',
                actionLabel: 'Load default data',
                onAction: vm.saving ? null : () => _seed(context, vm),
              )
            : RefreshIndicator(
                onRefresh: vm.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
                  children: [
                    Text(
                      'Hostels are never merged: Vasudha Block E and Block G stay two hostels. '
                      'Deactivating a hostel hides it from new registrations and new challenges.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                    _Group(title: 'General hostels', hostels: vm.general),
                    _Group(title: "Girls' hostels", hostels: vm.girls),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _seed(BuildContext context, HostelsViewModel vm) async {
    final ok = await confirmAction(
      context,
      title: 'Load default data?',
      message: 'Creates the 18 default hostels, settings, badges and challenge templates. '
          'Anything that already exists is left untouched.',
      confirmLabel: 'Load defaults',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final r = await vm.seed();
    showAdminResultOn(messenger, r);
  }
}

Future<void> _openForm(BuildContext context, HostelsViewModel vm, Hostel? existing) async {
  final draft = await showDialog<HostelDraft>(
    context: context,
    builder: (_) => _HostelFormDialog(existing: existing, vm: vm),
  );
  if (draft == null || !context.mounted) return;
  final creating = existing == null;
  final ok = await confirmAction(
    context,
    title: creating ? 'Add ${draft.displayName}?' : 'Save changes to ${draft.displayName}?',
    message: creating
        ? 'A new ${draft.category == HostelCategory.girls ? "girls'" : 'general'} hostel '
            'with id "${draft.id}" will be created.'
        : 'The hostel "${draft.id}" will be updated, including its category '
            '(${draft.category == HostelCategory.girls ? "girls'" : 'general'}).',
    confirmLabel: creating ? 'Add hostel' : 'Save',
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final r = await vm.save(draft, creating: creating);
  showAdminResultOn(messenger, r);
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.hostels});

  final String title;
  final List<Hostel> hostels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, subtitle: '${hostels.length} hostel(s)'),
        if (hostels.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('None in this group.'),
          ),
        for (final h in hostels)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HostelTile(hostel: h),
          ),
      ],
    );
  }
}

class _HostelTile extends StatelessWidget {
  const _HostelTile({required this.hostel});

  final Hostel hostel;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<HostelsViewModel>();
    final t = Theme.of(context).textTheme;
    final h = hostel;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.displayName, style: t.titleMedium),
                Text(
                  [
                    h.id,
                    if (h.legacyName != null) 'previously ${h.legacyName}',
                    if (h.block != null) 'block ${h.block}',
                  ].join('  -  '),
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                StatusPill(h.active ? 'Active' : 'Inactive',
                    color: h.active ? AppColors.primary : AppColors.textMuted),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit ${h.displayName}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openForm(context, vm, h),
          ),
          Switch(
            value: h.active,
            onChanged: (v) async {
              final ok = await confirmAction(
                context,
                title: v ? 'Activate ${h.displayName}?' : 'Deactivate ${h.displayName}?',
                message: v
                    ? 'Students will be able to pick this hostel again.'
                    : 'New registrations and new challenges will no longer offer this hostel. '
                        'Existing students keep their hostel.',
                confirmLabel: v ? 'Activate' : 'Deactivate',
                destructive: !v,
              );
              if (!ok || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              final r = await vm.setActive(h, v);
              showAdminResultOn(messenger, r);
            },
          ),
        ],
      ),
    );
  }
}

class _HostelFormDialog extends StatefulWidget {
  const _HostelFormDialog({required this.existing, required this.vm});

  final Hostel? existing;
  final HostelsViewModel vm;

  @override
  State<_HostelFormDialog> createState() => _HostelFormDialogState();
}

class _HostelFormDialogState extends State<_HostelFormDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _legacy;
  late final TextEditingController _block;
  late final TextEditingController _sort;
  late HostelCategory _category;
  late bool _active;
  Map<String, String> _errors = const {};

  bool get _creating => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _id = TextEditingController(text: h?.id ?? '');
    _name = TextEditingController(text: h?.displayName ?? '');
    _legacy = TextEditingController(text: h?.legacyName ?? '');
    _block = TextEditingController(text: h?.block ?? '');
    _sort = TextEditingController(text: '${h?.sortOrder ?? widget.vm.nextSortOrder}');
    _category = h?.category ?? HostelCategory.general;
    _active = h?.active ?? true;
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _legacy.dispose();
    _block.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _submit() {
    final sort = int.tryParse(_sort.text.trim());
    final draft = HostelDraft(
      id: _id.text.trim(),
      displayName: _name.text,
      legacyName: _legacy.text,
      block: _block.text,
      category: _category,
      sortOrder: sort ?? -1,
      active: _active,
    );
    final errors = draft.validate(existingIds: widget.vm.ids, creating: _creating);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? 'Add hostel' : 'Edit hostel'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _id,
                enabled: _creating,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Hostel id (slug)',
                  helperText: _creating ? 'Permanent, e.g. vasudha-e' : 'The id cannot be changed',
                  errorText: _errors['id'],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Display name', errorText: _errors['displayName']),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _legacy,
                decoration: InputDecoration(
                  labelText: 'Previous name (optional)',
                  errorText: _errors['legacyName'],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _block,
                decoration: InputDecoration(labelText: 'Block (optional)', errorText: _errors['block']),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Sort order', errorText: _errors['sortOrder']),
              ),
              const SizedBox(height: 16),
              Text('Category', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<HostelCategory>(
                segments: const [
                  ButtonSegment(value: HostelCategory.general, label: Text('General')),
                  ButtonSegment(value: HostelCategory.girls, label: Text('Girls')),
                ],
                selected: {_category},
                onSelectionChanged: (s) => setState(() => _category = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
