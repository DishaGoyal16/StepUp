import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddies_repository.dart';
import '../../data/buddies/buddy_models.dart';
import '../auth/session_controller.dart';
import 'buddy_action_result.dart';
import 'buddy_labels.dart';
import 'buddy_requests_view_model.dart';
import 'buddy_ui_actions.dart';

/// `/buddies/requests`: Incoming / Outgoing pending requests, live.
class BuddyRequestsScreen extends StatefulWidget {
  const BuddyRequestsScreen({super.key});

  @override
  State<BuddyRequestsScreen> createState() => _BuddyRequestsScreenState();
}

class _BuddyRequestsScreenState extends State<BuddyRequestsScreen> {
  BuddyRequestsViewModel? _vm;
  String? _vmUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final uid = session.profile?.uid ?? session.user?.uid;
    if (uid == null) return;
    if (_vm == null || _vmUid != uid) {
      _vm?.dispose();
      _vmUid = uid;
      _vm = BuddyRequestsViewModel(repository: context.read<BuddiesRepository>(), uid: uid)
        ..start();
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buddy requests')),
        body: const LoadingState(),
      );
    }
    return ChangeNotifierProvider<BuddyRequestsViewModel>.value(
      value: vm,
      child: const _RequestsBody(),
    );
  }
}

class _RequestsBody extends StatelessWidget {
  const _RequestsBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BuddyRequestsViewModel>();
    final inCount = vm.incoming?.length;
    final outCount = vm.outgoing?.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buddy requests'),
          bottom: TabBar(
            tabs: [
              Tab(text: inCount == null || inCount == 0 ? 'Incoming' : 'Incoming ($inCount)'),
              Tab(text: outCount == null || outCount == 0 ? 'Outgoing' : 'Outgoing ($outCount)'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _RequestList(
                requests: vm.incoming,
                error: vm.incomingError,
                incoming: true,
              ),
              _RequestList(
                requests: vm.outgoing,
                error: vm.outgoingError,
                incoming: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.requests, required this.error, required this.incoming});

  final List<BuddyRequest>? requests;
  final AppException? error;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<BuddyRequestsViewModel>();
    if (error != null) {
      return ErrorState(message: error!.message, onRetry: vm.retry);
    }
    final list = requests;
    if (list == null) return const LoadingState();
    if (list.isEmpty) {
      return EmptyState(
        icon: incoming ? Icons.mark_email_unread_outlined : Icons.outbox_outlined,
        title: incoming ? 'No incoming requests' : 'No outgoing requests',
        message: incoming
            ? 'When a student wants to be your buddy, you will see it here.'
            : 'Requests you send stay here until they are answered.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md - 4),
      itemBuilder: (context, i) => _RequestTile(key: ValueKey('req_${list[i].id}'), request: list[i]),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({super.key, required this.request});

  final BuddyRequest request;

  Future<void> _run(
    BuildContext context,
    Future<BuddyActionResult> Function(BuddyRequestsViewModel vm) action,
  ) async {
    final vm = context.read<BuddyRequestsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    showBuddyResult(messenger, await action(vm));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BuddyRequestsViewModel>();
    final now = context.read<AppDependencies>().clock.now();
    final t = Theme.of(context).textTheme;
    final r = request;
    final busy = vm.isBusy(r.id);
    final ago = timeAgo(r.createdAt, now);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarCircle(name: r.otherName, photoUrl: r.otherPhotoUrl, radius: 24),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.otherName,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        r.incoming ? 'Wants to be your buddy' : 'Waiting for a reply',
                        if (ago.isNotEmpty) ago,
                      ].join(' · '),
                      style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Text('"${r.message}"', style: t.bodyMedium),
            ),
          ],
          const SizedBox(height: AppSpacing.md - 4),
          if (r.incoming)
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Reject',
                    onPressed: busy ? null : () => _run(context, (v) => v.reject(r)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Accept',
                    loading: busy,
                    onPressed: () => _run(context, (v) => v.accept(r)),
                  ),
                ),
              ],
            )
          else
            SecondaryButton(
              label: 'Cancel request',
              icon: Icons.close,
              onPressed: busy ? null : () => _run(context, (v) => v.cancel(r)),
            ),
        ],
      ),
    );
  }
}
