import 'dart:async';

import 'push_service.dart';

/// Test double that lets tests push messages.
class FakePushService implements PushService {
  final StreamController<PushMessage> _controller = StreamController<PushMessage>.broadcast();
  void Function(String token)? _onToken;
  int initCalls = 0;

  @override
  Stream<PushMessage> get foregroundMessages => _controller.stream;

  @override
  Future<void> init({required void Function(String token) onToken}) async {
    initCalls++;
    _onToken = onToken;
  }

  void deliverToken(String token) => _onToken?.call(token);
  void deliver(PushMessage m) => _controller.add(m);

  @override
  Future<void> dispose() => _controller.close();
}
