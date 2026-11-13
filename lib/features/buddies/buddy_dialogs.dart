import 'package:flutter/material.dart';

import '../../data/buddies/buddy_models.dart';

/// Max length of the optional message of a buddy request (backend limit).
const int kRequestMessageMax = 120;

/// Max length of the optional report details (backend limit).
const int kReportDetailsMax = 500;

/// Asks for an optional short message. Returns the text (possibly empty) when
/// the student taps "Send request", or null when the dialog is dismissed.
Future<String?> showSendRequestDialog(BuildContext context, String name) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SendRequestDialog(name: name),
  );
}

class _SendRequestDialog extends StatefulWidget {
  const _SendRequestDialog({required this.name});

  final String name;

  @override
  State<_SendRequestDialog> createState() => _SendRequestDialogState();
}

class _SendRequestDialogState extends State<_SendRequestDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send request to ${widget.name}'),
      content: TextField(
        key: const Key('requestMessageField'),
        controller: _controller,
        maxLength: kRequestMessageMax,
        maxLines: 3,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Add a short message (optional)',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

/// Confirmation before removing a buddy. True when confirmed.
Future<bool> confirmRemoveBuddy(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove buddy?'),
      content: Text('$name will no longer be your buddy. You can send a new request later.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep buddy')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The reason + optional details chosen in the report dialog.
typedef ReportChoice = ({ReportReason reason, String details});

/// Reason picker for `reportProfile`. Null when dismissed.
Future<ReportChoice?> showReportDialog(BuildContext context, String name) {
  return showDialog<ReportChoice>(
    context: context,
    builder: (_) => _ReportDialog(name: name),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.name});

  final String name;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _details = TextEditingController();
  ReportReason? _reason;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why are you reporting this profile?'),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: Key('reason_${r.wire}'),
                      value: r,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label),
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('reportDetailsField'),
              controller: _details,
              maxLength: kReportDetailsMax,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Details (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop((reason: _reason!, details: _details.text.trim())),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
