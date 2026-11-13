import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// A push message received while the app is in the foreground.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, String> data;
}

/// FCM boundary. `init` requests the notification permission, fetches the
/// token and starts forwarding foreground messages. Safe to call when Firebase
/// is not configured (the no-op implementation does nothing).
abstract class PushService {
  /// Emits foreground messages (shown as a snackbar by the app shell).
  Stream<PushMessage> get foregroundMessages;

  /// Requests permission and resolves the token; [onToken] is called with the
  /// current token and again whenever it refreshes.
  Future<void> init({required void Function(String token) onToken});

  Future<void> dispose();
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Stream<PushMessage> get foregroundMessages => const Stream.empty();

  @override
  Future<void> init({required void Function(String token) onToken}) async {}

  @override
  Future<void> dispose() async {}
}

class FirebasePushService implements PushService {
  FirebasePushService([FirebaseMessaging? messaging]) : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final StreamController<PushMessage> _controller = StreamController<PushMessage>.broadcast();
  StreamSubscription<RemoteMessage>? _msgSub;
  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  @override
  Stream<PushMessage> get foregroundMessages => _controller.stream;

  @override
  Future<void> init({required void Function(String token) onToken}) async {
    if (_started) return;
    _started = true;
    try {
      await _messaging.requestPermission();
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null) onToken(token);
      // ignore: deprecated_member_use
      _tokenSub = _messaging.onTokenRefresh.listen(onToken);
      _msgSub = FirebaseMessaging.onMessage.listen((m) {
        _controller.add(PushMessage(
          title: m.notification?.title,
          body: m.notification?.body,
          data: {for (final e in m.data.entries) e.key: '${e.value}'},
        ));
      });
    } catch (_) {
      // Push is optional: never break the app because FCM is unavailable
      // (e.g. emulator without Google Play services).
    }
  }

  @override
  Future<void> dispose() async {
    await _msgSub?.cancel();
    await _tokenSub?.cancel();
    await _controller.close();
  }
}
