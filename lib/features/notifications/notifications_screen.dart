import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/notifications_center/app_notification.dart';
import '../../data/notifications_center/notifications_reader.dart';
import '../auth/session_controller.dart';
import 'notification_routing.dart';
import 'notifications_view_model.dart';

/// Full-screen notification centre (`/notifications`).
///
/// Notifications are created by the server and are NOT deletable or
/// swipe-dismissable; the only mutation is marking them read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationsViewModel? _vm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    if (_vm == null || _vm!.uid != uid) {
      _vm?.dispose();
      _vm = NotificationsViewModel(
        uid: uid,
        reader: context.read<NotificationsReader>(),
        callables: context.read<AppDependencies>().callables,
      )..start();
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  void _showActionError(NotificationsViewModel vm) {
    final msg = vm.takeActionError();
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _open(NotificationsViewModel vm, AppNotification n) async {
    final route = notificationRoute(n);
    // Mark read in the background; navigation never waits for it.
    final marked = vm.markRead(n.id);
    if (route != null) {
      context.push(route);
    }
    await marked;
    if (mounted) _showActionError(vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const LoadingState(),
      );
    }
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showActionError(vm);
        });
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              TextButton(
                onPressed: vm.unreadCount == 0 || vm.marking ? null : vm.markAllRead,
                child: const Text('Mark all read'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(child: _body(context, vm)),
        );
      },
    );
  }

  Widget _body(BuildContext context, NotificationsViewModel vm) {
    if (vm.loading) return const LoadingState();
    if (vm.failed) {
      return ErrorState(message: 'Could not load your notifications.', onRetry: vm.retry);
    }
    final items = vm.items;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none,
        title: 'No notifications yet',
        message: 'Buddy requests, challenge updates, bet results and badges will show up here.',
      );
    }
    final now = context.read<AppDependencies>().clock.now();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: items.length + (vm.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == items.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: vm.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : SecondaryButton(label: 'Load older', onPressed: vm.loadMore),
              );
            }
            final n = items[i];
            return NotificationTile(
              key: ValueKey(n.id),
              notification: n,
              now: now,
              onTap: () => _open(vm, n),
            );
          },
        ),
      ),
    );
  }
}

/// One notification row; unread ones are tinted, bold and carry a dot.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.now,
    required this.onTap,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = notification;
    final visual = notificationVisual(n.type);
    final unread = !n.read;
    return Semantics(
      label: '${unread ? 'Unread. ' : ''}${n.title}. ${n.body}',
      child: AppCard(
        onTap: onTap,
        color: unread ? AppColors.mint : AppColors.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: unread ? AppColors.surface : AppColors.mint,
              child: Icon(visual.icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title.isEmpty ? visual.label : n.title,
                          style: t.titleMedium?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          key: const ValueKey('unread-dot'),
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(n.body, style: t.bodyMedium),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${visual.label}  ·  ${formatNotificationTime(n.createdAt, now)}',
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
