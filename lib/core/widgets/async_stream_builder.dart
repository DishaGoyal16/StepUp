import 'package:flutter/material.dart';

import 'state_widgets.dart';

/// `StreamBuilder` with the app's standard loading / error / empty states.
///
/// * waiting for the first event -> [LoadingState]
/// * error -> [ErrorState] with a retry button ([onRetry], usually re-creates
///   the stream in the parent)
/// * [isEmpty] true -> [empty] (defaults to a plain [EmptyState])
/// * otherwise -> [builder]
class AsyncStreamBuilder<T> extends StatelessWidget {
  const AsyncStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.onRetry,
    this.errorMessage = 'Could not load this right now.',
  });

  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final VoidCallback? onRetry;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState(message: errorMessage, onRetry: onRetry);
        }
        if (!snap.hasData) return const LoadingState();
        final data = snap.data as T;
        if (isEmpty != null && isEmpty!(data)) {
          return empty ?? const EmptyState(title: 'Nothing here yet');
        }
        return builder(context, data);
      },
    );
  }
}
