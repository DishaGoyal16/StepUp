import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ReportsViewModel>(
      create: (c) => ReportsViewModel(c.read<AdminRepository>())..load(),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportsViewModel>();
    return AdminPage(
      title: 'Reports',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: vm.loading ? null : () => vm.load(),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: FilterChipsRow<ReportStatus>(
              options: ReportStatus.values,
              selected: vm.filter,
              onSelected: (s) => vm.load(filter: s),
              labelOf: (s) => s.label,
            ),
          ),
          Expanded(
            child: AdminAsyncBody(
              loading: vm.loading,
              error: vm.error,
              denied: vm.denied,
              onRetry: () => vm.load(),
              child: vm.reports.isEmpty
                  ? EmptyState(
                      icon: Icons.flag_outlined,
                      title: 'No ${vm.filter.label.toLowerCase()} reports',
                    )
                  : RefreshIndicator(
                      onRefresh: () => vm.load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                        itemCount: vm.reports.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _ReportTile(report: vm.reports[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String shortUid(String uid) => uid.length <= 12 ? uid : '${uid.substring(0, 6)}...${uid.substring(uid.length - 4)}';

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final AdminReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = report;
    return AppCard(
      onTap: () => _openReport(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.reasonLabel, style: t.titleMedium)),
              StatusPill(r.status.label,
                  color: r.status == ReportStatus.open ? AppColors.warning : AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text('Reported student: ${shortUid(r.targetUid)}', style: t.bodySmall),
          if (r.details.isNotEmpty)
            Text(r.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          const SizedBox(height: 2),
          Text(formatIst(r.createdAt), style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

Future<void> _openReport(BuildContext context, AdminReport r) {
  final vm = context.read<ReportsViewModel>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<ReportsViewModel>.value(
      value: vm,
      child: _ReportSheet(report: r, messenger: ScaffoldMessenger.of(context)),
    ),
  );
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.report, required this.messenger});

  final AdminReport report;
  final ScaffoldMessengerState messenger;

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportsViewModel>();
    final r = report;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.reasonLabel, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _kv(context, 'Status', r.status.label),
            _kv(context, 'Reported student', r.targetUid),
            _kv(context, 'Reported by', r.reporterUid),
            _kv(context, 'Received', formatIst(r.createdAt)),
            if (r.resolvedAt != null) _kv(context, 'Resolved', formatIst(r.resolvedAt)),
            _kv(context, 'Details', r.details.isEmpty ? 'No details given.' : r.details),
            const SizedBox(height: 16),
            if (r.status == ReportStatus.open) ...[
              PrimaryButton(
                label: 'Take action',
                icon: Icons.gavel_outlined,
                loading: vm.busy,
                onPressed: () => _action(context, vm),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Dismiss report',
                icon: Icons.close,
                onPressed: vm.busy ? null : () => _dismiss(context, vm),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _dismiss(BuildContext context, ReportsViewModel vm) async {
    final ok = await confirmAction(
      context,
      title: 'Dismiss this report?',
      message: 'No action is taken against the reported student.',
      confirmLabel: 'Dismiss',
    );
    if (!ok) return;
    final res = await vm.dismiss(report);
    showAdminResultOn(messenger, res);
    if (res.ok && context.mounted) Navigator.pop(context);
  }

  Future<void> _action(BuildContext context, ReportsViewModel vm) async {
    final choice = await showDialog<({bool suspend, String reason})>(
      context: context,
      builder: (_) => const _ActionDialog(),
    );
    if (choice == null || !context.mounted) return;
    final res = await vm.takeAction(report, suspendUser: choice.suspend, reason: choice.reason);
    showAdminResultOn(messenger, res);
    if (res.ok && context.mounted) Navigator.pop(context);
  }
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog();

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _suspend = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_suspend && _reason.text.trim().isEmpty) {
      setState(() => _error = 'A reason is required to suspend.');
      return;
    }
    Navigator.pop(context, (suspend: _suspend, reason: _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Take action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The report will be closed as "action taken".'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Also suspend the reported student'),
              value: _suspend,
              onChanged: (v) => setState(() => _suspend = v ?? false),
            ),
            if (_suspend)
              TextField(
                controller: _reason,
                maxLength: 300,
                decoration: InputDecoration(labelText: 'Reason for suspension', errorText: _error),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _suspend ? AppColors.error : null,
            minimumSize: const Size(88, 44),
          ),
          onPressed: _submit,
          child: Text(_suspend ? 'Suspend and close' : 'Close report'),
        ),
      ],
    );
  }
}
