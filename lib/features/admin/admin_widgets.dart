import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'admin_support.dart';

/// Page frame of every admin screen: app bar with a working back button
/// (falls back to [parent] when opened by deep link), a centred content
/// column that stays readable on wide screens, and optional action buttons.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.child,
    this.parent = AppRoutes.admin,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final String parent;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            final router = GoRouter.maybeOf(context);
            if (router == null) {
              Navigator.maybePop(context);
            } else if (router.canPop()) {
              router.pop();
            } else {
              router.go(parent == AppRoutes.admin ? AppRoutes.home : parent);
            }
          },
        ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Loading / error / permission-denied states in one widget. Shows [child]
/// when there is neither.
class AdminAsyncBody extends StatelessWidget {
  const AdminAsyncBody({
    super.key,
    required this.loading,
    required this.error,
    required this.denied,
    required this.onRetry,
    required this.child,
    this.hasData = false,
  });

  final bool loading;
  final String? error;
  final bool denied;
  final VoidCallback onRetry;
  final Widget child;

  /// When true a refresh shows [child] (old data) instead of a spinner.
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    if (loading && !hasData) return const LoadingState();
    if (error != null && !hasData) {
      if (denied) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 8),
                Text('Admins only', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                SecondaryButton(label: 'Try again', onPressed: onRetry, expand: false),
              ],
            ),
          ),
        );
      }
      return ErrorState(message: error!, onRetry: onRetry);
    }
    return child;
  }
}

void showAdminResult(BuildContext context, AdminResult r) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) showAdminResultOn(messenger, r);
}

/// Like [showAdminResult] with a messenger captured BEFORE an `await`, so the
/// result still shows when the widget that started the action was rebuilt or
/// removed by the refresh that follows it (e.g. a resolved report leaving a
/// filtered list).
void showAdminResultOn(ScaffoldMessengerState messenger, AdminResult r) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(r.message),
      backgroundColor: r.ok ? AppColors.text : AppColors.error,
    ));
}

/// Plain yes / no confirmation. Returns true only on explicit confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  minimumSize: const Size(88, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a mandatory reason. Returns the trimmed text or null if the
/// dialog was cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  int maxLength = 300,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextPromptDialog(
      title: title,
      message: message,
      label: 'Reason',
      confirmLabel: confirmLabel,
      maxLength: maxLength,
      destructive: true,
      validator: (t) => t.trim().isEmpty ? 'A reason is required.' : null,
    ),
  );
}

/// Asks the admin to type [phrase] exactly. Returns true when they did.
Future<bool> confirmTyped(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
}) async {
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => _TextPromptDialog(
      title: title,
      message: '$message\n\nType $phrase to confirm.',
      label: 'Type $phrase',
      confirmLabel: confirmLabel,
      maxLength: 40,
      destructive: true,
      validator: (t) => t.trim() == phrase ? null : 'Type exactly "$phrase".',
    ),
  );
  return r != null;
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.maxLength,
    required this.validator,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String label;
  final String confirmLabel;
  final int maxLength;
  final bool destructive;
  final String? Function(String text) validator;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final err = widget.validator(_c.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              maxLength: widget.maxLength,
              autofocus: true,
              maxLines: 1,
              decoration: InputDecoration(labelText: widget.label, errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.destructive ? AppColors.error : null,
            minimumSize: const Size(88, 44),
          ),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Small coloured label ("Suspended", "Admin", "Open", ...).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color = AppColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Date like `13 Nov 2026 14:05` in IST for a UTC instant.
String formatIst(DateTime? t) {
  if (t == null) return '-';
  final ist = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ist.day} ${m[ist.month - 1]} ${ist.year} ${two(ist.hour)}:${two(ist.minute)} IST';
}

/// `1234567` -> `1,234,567`.
String groupDigits(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}
