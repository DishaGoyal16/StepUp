/// Base class for all application-level errors in Thapar StepUp.
/// These are user-facing errors that are shown with friendly messages.
abstract class AppError implements Exception {
  final String message;
  final String? technicalDetail;

  const AppError(this.message, {this.technicalDetail});

  @override
  String toString() => 'AppError: $message';
}

// ─────────────────────────────────────────────────────────
// HEALTH DATA ERRORS
// ─────────────────────────────────────────────────────────
class HealthPermissionDeniedError extends AppError {
  const HealthPermissionDeniedError()
      : super(
          'Health access was denied. Please grant permission in Settings to sync your activity.',
        );
}

class HealthConnectUnavailableError extends AppError {
  const HealthConnectUnavailableError()
      : super(
          'Health Connect is not available on this device. Please install Health Connect from the Play Store.',
        );
}

class HealthKitUnavailableError extends AppError {
  const HealthKitUnavailableError()
      : super(
          'Apple Health is not available on this device.',
        );
}

class HealthSyncError extends AppError {
  const HealthSyncError({String? detail})
      : super(
          'Failed to sync health data. Please try again.',
          technicalDetail: detail,
        );
}

// ─────────────────────────────────────────────────────────
// SENSOR ERRORS
// ─────────────────────────────────────────────────────────
class SensorUnavailableError extends AppError {
  final String sensorName;

  const SensorUnavailableError(this.sensorName)
      : super(
          'Motion sensor ($sensorName) is not available on this device. '
          'Activity verification will use imported data only.',
        );
}

class SensorPermissionDeniedError extends AppError {
  const SensorPermissionDeniedError()
      : super(
          'Motion sensor access was denied. '
          'Verified session analysis will be limited.',
        );
}

// ─────────────────────────────────────────────────────────
// SESSION ERRORS
// ─────────────────────────────────────────────────────────
class SessionAlreadyActiveError extends AppError {
  const SessionAlreadyActiveError()
      : super('A verified session is already active. End it first.');
}

class SessionNotFoundError extends AppError {
  const SessionNotFoundError()
      : super('Session not found. It may have expired or been deleted.');
}

class SessionVerificationError extends AppError {
  const SessionVerificationError()
      : super(
          'Session verification failed. '
          'Both participants must confirm within the time window.',
        );
}

// ─────────────────────────────────────────────────────────
// BET / STEP BATTLE ERRORS
// ─────────────────────────────────────────────────────────
class InsufficientCoinsError extends AppError {
  final int required;
  final int available;

  InsufficientCoinsError({required this.required, required this.available})
      : super(
          'You need $required StepCoins to enter this battle, '
          'but only have $available.',
        );
}

class BetNotFoundError extends AppError {
  const BetNotFoundError()
      : super('Step Battle not found.');
}

class BetAlreadyCompletedError extends AppError {
  const BetAlreadyCompletedError()
      : super('This Step Battle has already ended.');
}

class InvalidBetParametersError extends AppError {
  const InvalidBetParametersError(String detail) : super(detail);
}

// ─────────────────────────────────────────────────────────
// STORAGE ERRORS
// ─────────────────────────────────────────────────────────
class LocalStorageError extends AppError {
  const LocalStorageError({String? detail})
      : super(
          'Failed to save data locally. Please try again.',
          technicalDetail: detail,
        );
}

// ─────────────────────────────────────────────────────────
// USER ERRORS
// ─────────────────────────────────────────────────────────
class UserNotFoundError extends AppError {
  const UserNotFoundError()
      : super(
          'User profile not found. Please complete onboarding.',
        );
}

class ProfileIncompleteError extends AppError {
  const ProfileIncompleteError()
      : super(
          'Please complete your profile before using this feature.',
        );
}

// ─────────────────────────────────────────────────────────
// NETWORK ERRORS (future backend)
// ─────────────────────────────────────────────────────────
class NetworkError extends AppError {
  const NetworkError({String? detail})
      : super(
          'Network error. Please check your connection and try again.',
          technicalDetail: detail,
        );
}

class ServerError extends AppError {
  const ServerError({String? detail})
      : super(
          'Server error. Please try again later.',
          technicalDetail: detail,
        );
}
