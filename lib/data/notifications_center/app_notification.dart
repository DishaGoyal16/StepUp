/// One document of the signed-in user's `notifications` collection
/// (server-created; the client can only read it and ask the server to mark it
/// read through `markNotificationsRead`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.read = false,
    this.createdAt,
  });

  /// Builds a notification from a Firestore document map. Timestamps must
  /// already be converted to [DateTime] / epoch millis.
  factory AppNotification.fromMap(String id, Map<String, dynamic> m) {
    final rawData = m['data'];
    final createdAt = m['createdAt'];
    return AppNotification(
      id: id,
      type: (m['type'] as String?) ?? 'SYSTEM',
      title: (m['title'] as String?) ?? '',
      body: (m['body'] as String?) ?? '',
      data: rawData is Map
          ? {
              for (final e in rawData.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            }
          : const {},
      read: m['read'] == true,
      createdAt: createdAt is DateTime
          ? createdAt.toUtc()
          : createdAt is num
              ? DateTime.fromMillisecondsSinceEpoch(createdAt.toInt(), isUtc: true)
              : null,
    );
  }

  final String id;

  /// `BUDDY_REQUEST | BUDDY_ACCEPTED | CHALLENGE_NEW | CHALLENGE_REMINDER |
  /// CHALLENGE_DONE | LEADERBOARD | BET_INVITE | BET_RESULT | HOSTEL_RESULT |
  /// SYSTEM` (kept as a string so unknown future types still render).
  final String type;
  final String title;
  final String body;
  final Map<String, String> data;
  final bool read;
  final DateTime? createdAt;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        read: read ?? this.read,
        createdAt: createdAt,
      );
}
