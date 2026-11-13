import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StudentsViewModel>(
      create: (c) => StudentsViewModel(
        c.read<AdminRepository>(),
        currentUid: c.read<AppDependencies>().session.user?.uid,
      )..load(),
      child: const _StudentsView(),
    );
  }
}

class _StudentsView extends StatefulWidget {
  const _StudentsView();

  @override
  State<_StudentsView> createState() => _StudentsViewState();
}

class _StudentsViewState extends State<_StudentsView> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(StudentsViewModel vm) => vm.load(query: _search.text);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudentsViewModel>();
    return AdminPage(
      title: 'Students',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(vm),
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _submit(vm),
                ),
              ),
            ),
          ),
          Expanded(
            child: AdminAsyncBody(
              loading: vm.loading,
              error: vm.error,
              denied: vm.denied,
              hasData: vm.students.isNotEmpty,
              onRetry: () => vm.load(),
              child: vm.students.isEmpty
                  ? EmptyState(
                      icon: Icons.person_search_outlined,
                      title: vm.query.isEmpty ? 'No students yet' : 'No matches',
                      message: vm.query.isEmpty ? null : 'Nobody matches "${vm.query}".',
                    )
                  : RefreshIndicator(
                      onRefresh: () => vm.load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                        itemCount: vm.students.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          if (i == vm.students.length) {
                            if (vm.nextCursor == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SecondaryButton(
                                label: vm.loadingMore ? 'Loading...' : 'Load more',
                                onPressed: vm.loadingMore ? null : vm.loadMore,
                              ),
                            );
                          }
                          return _StudentTile(student: vm.students[i]);
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.student});

  final AdminStudent student;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudentsViewModel>();
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => _showActions(context, student),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarCircle(name: student.displayName, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.displayName, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                Text(
                  student.email,
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${vm.hostelLabel(student)}  -  ${groupDigits(student.pointsBalance)} pts',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(_statusLabel(student.status), color: _statusColor(student.status)),
                    StatusPill(student.isAdmin ? 'Admin' : 'Student',
                        color: student.isAdmin ? AppColors.warning : AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ),
          if (vm.busy.contains(student.uid))
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'ACTIVE' => 'Active',
        'SUSPENDED' => 'Suspended',
        'DELETION_REQUESTED' => 'Deletion requested',
        _ => s,
      };

  static Color _statusColor(String s) => switch (s) {
        'ACTIVE' => AppColors.primary,
        'SUSPENDED' => AppColors.error,
        _ => AppColors.warning,
      };
}

Future<void> _showActions(BuildContext context, AdminStudent s) {
  final vm = context.read<StudentsViewModel>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => ChangeNotifierProvider<StudentsViewModel>.value(
      value: vm,
      child: _StudentSheet(uid: s.uid, messenger: ScaffoldMessenger.of(context)),
    ),
  );
}

class _StudentSheet extends StatelessWidget {
  const _StudentSheet({required this.uid, required this.messenger});

  final String uid;
  final ScaffoldMessengerState messenger;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudentsViewModel>();
    final matches = vm.students.where((x) => x.uid == uid);
    if (matches.isEmpty) return const SizedBox.shrink();
    final s = matches.first;
    final t = Theme.of(context).textTheme;
    final self = !vm.canModify(s);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.displayName, style: t.titleLarge),
            Text(s.email, style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            _kv(context, 'Hostel', vm.hostelLabel(s)),
            _kv(context, 'Status', s.status),
            _kv(context, 'Role', s.role),
            _kv(context, 'Points', '${groupDigits(s.pointsBalance)} available, ${groupDigits(s.pointsReserved)} reserved'),
            _kv(context, 'Lifetime verified steps', groupDigits(s.lifetimeVerifiedSteps)),
            _kv(context, 'Joined', formatIst(s.createdAt)),
            const SizedBox(height: 16),
            if (self)
              Text(
                'This is your own account. You cannot suspend it or remove your own admin role.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            if (!self) ...[
              if (s.isSuspended)
                PrimaryButton(
                  label: 'Reactivate student',
                  icon: Icons.lock_open_outlined,
                  onPressed: () => _unsuspend(context, vm, s),
                )
              else
                PrimaryButton(
                  label: 'Suspend student',
                  icon: Icons.block,
                  onPressed: () => _suspend(context, vm, s),
                ),
              const SizedBox(height: 10),
            ],
            if (s.isAdmin && !self)
              SecondaryButton(
                label: 'Remove admin role',
                icon: Icons.admin_panel_settings_outlined,
                onPressed: () => _setAdmin(context, vm, s, false),
              ),
            if (!s.isAdmin)
              SecondaryButton(
                label: 'Make admin',
                icon: Icons.admin_panel_settings_outlined,
                onPressed: () => _setAdmin(context, vm, s, true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Future<void> _suspend(BuildContext context, StudentsViewModel vm, AdminStudent s) async {
    final reason = await askReason(
      context,
      title: 'Suspend ${s.displayName}?',
      message: 'They will lose access to the app until reactivated. Their steps and points are kept.',
      confirmLabel: 'Suspend',
    );
    if (reason == null) return;
    final r = await vm.suspend(s, reason);
    showAdminResultOn(messenger, r);
  }

  Future<void> _unsuspend(BuildContext context, StudentsViewModel vm, AdminStudent s) async {
    final ok = await confirmAction(
      context,
      title: 'Reactivate ${s.displayName}?',
      message: 'They will be able to use the app again.',
      confirmLabel: 'Reactivate',
    );
    if (!ok) return;
    final r = await vm.unsuspend(s);
    showAdminResultOn(messenger, r);
  }

  /// Role changes are double-confirmed: an explanation, then a typed phrase.
  Future<void> _setAdmin(BuildContext context, StudentsViewModel vm, AdminStudent s, bool admin) async {
    final first = await confirmAction(
      context,
      title: admin ? 'Make ${s.displayName} an admin?' : 'Remove admin role from ${s.displayName}?',
      message: admin
          ? 'Admins can see every student, suspend accounts, change settings and create challenges. '
              'The change is logged.'
          : 'They will lose all admin powers the next time their session refreshes. The change is logged.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final typed = await confirmTyped(
      context,
      title: 'Are you sure?',
      message: admin
          ? 'You are giving admin power to ${s.email}.'
          : 'You are removing admin power from ${s.email}.',
      phrase: admin ? 'GRANT ADMIN' : 'REVOKE ADMIN',
      confirmLabel: admin ? 'Grant admin' : 'Revoke admin',
    );
    if (!typed) return;
    final r = await vm.setAdmin(s, admin);
    showAdminResultOn(messenger, r);
  }
}
