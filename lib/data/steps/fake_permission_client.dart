import 'step_permissions.dart';

/// Scriptable [PermissionClient]. `onRequest` decides the outcome of a system
/// prompt for each kind (default: grant).
class FakePermissionClient implements PermissionClient {
  FakePermissionClient({
    StepPermissionState activity = StepPermissionState.denied,
    StepPermissionState notifications = StepPermissionState.denied,
  }) : _state = {
          PermissionKind.activityRecognition: activity,
          PermissionKind.notifications: notifications,
        };

  final Map<PermissionKind, StepPermissionState> _state;

  /// What a prompt resolves to; absent = granted.
  final Map<PermissionKind, StepPermissionState> promptResult = {};

  final List<PermissionKind> prompts = [];
  int openSettingsCalls = 0;

  @override
  Future<StepPermissionState> status(PermissionKind kind) async => _state[kind]!;

  @override
  Future<StepPermissionState> request(PermissionKind kind) async {
    prompts.add(kind);
    final r = promptResult[kind] ?? StepPermissionState.granted;
    _state[kind] = r;
    return r;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}
