import 'package:permission_handler/permission_handler.dart';

enum PermissionKind { activityRecognition, notifications }

enum StepPermissionState { granted, denied, permanentlyDenied }

/// Snapshot of the permissions step tracking needs.
class StepPermissionStatus {
  const StepPermissionStatus({
    this.activityRecognition = StepPermissionState.denied,
    this.notifications = StepPermissionState.denied,
  });

  final StepPermissionState activityRecognition;
  final StepPermissionState notifications;

  /// Step counting needs ACTIVITY_RECOGNITION; notifications are only needed
  /// so the foreground-service notification is visible on Android 13+.
  bool get canTrack => activityRecognition == StepPermissionState.granted;
  bool get activityPermanentlyDenied =>
      activityRecognition == StepPermissionState.permanentlyDenied;
}

/// Thin wrapper so permission logic can be tested without the plugin.
abstract class PermissionClient {
  Future<StepPermissionState> status(PermissionKind kind);
  Future<StepPermissionState> request(PermissionKind kind);
  Future<bool> openSettings();
}

class PermissionHandlerClient implements PermissionClient {
  const PermissionHandlerClient();

  Permission _p(PermissionKind k) => switch (k) {
        PermissionKind.activityRecognition => Permission.activityRecognition,
        PermissionKind.notifications => Permission.notification,
      };

  StepPermissionState _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return StepPermissionState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return StepPermissionState.permanentlyDenied;
    return StepPermissionState.denied;
  }

  @override
  Future<StepPermissionState> status(PermissionKind kind) async => _map(await _p(kind).status);

  @override
  Future<StepPermissionState> request(PermissionKind kind) async => _map(await _p(kind).request());

  @override
  Future<bool> openSettings() => openAppSettings();
}

/// Requests, in order, ACTIVITY_RECOGNITION then POST_NOTIFICATIONS.
class StepPermissions {
  StepPermissions(this._client);

  final PermissionClient _client;

  Future<StepPermissionStatus> check() async => StepPermissionStatus(
        activityRecognition: await _client.status(PermissionKind.activityRecognition),
        notifications: await _client.status(PermissionKind.notifications),
      );

  /// Asks for the permissions. [rationale] is invoked (once) before the first
  /// system prompt for activity recognition and returns `false` if the user
  /// declined to continue. A permanently denied permission is NOT re-requested
  /// (the system would ignore it): callers should offer [openSettings].
  Future<StepPermissionStatus> request({Future<bool> Function()? rationale}) async {
    var activity = await _client.status(PermissionKind.activityRecognition);
    if (activity == StepPermissionState.denied) {
      if (rationale != null && !await rationale()) return check();
      activity = await _client.request(PermissionKind.activityRecognition);
    }
    var notif = await _client.status(PermissionKind.notifications);
    if (activity == StepPermissionState.granted && notif == StepPermissionState.denied) {
      notif = await _client.request(PermissionKind.notifications);
    }
    return StepPermissionStatus(activityRecognition: activity, notifications: notif);
  }

  Future<bool> openSettings() => _client.openSettings();
}
