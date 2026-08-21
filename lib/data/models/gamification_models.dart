import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────
// BADGE
// ─────────────────────────────────────────────────────────
enum BadgeRarity { common, rare, epic, legendary }

class BadgeModel extends Equatable {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final BadgeRarity rarity;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const BadgeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.rarity,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  BadgeModel copyWith({bool? isUnlocked, DateTime? unlockedAt}) => BadgeModel(
        id: id,
        name: name,
        description: description,
        emoji: emoji,
        rarity: rarity,
        isUnlocked: isUnlocked ?? this.isUnlocked,
        unlockedAt: unlockedAt ?? this.unlockedAt,
      );

  @override
  List<Object?> get props => [id, isUnlocked];
}

// ─────────────────────────────────────────────────────────
// CHALLENGE
// ─────────────────────────────────────────────────────────
enum ChallengeType { daily, weekly, campus, hostel, friend }
enum ChallengeStatus { active, completed, expired, upcoming }

class ChallengeModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final ChallengeType type;
  final ChallengeStatus status;
  final int targetSteps;
  final int currentSteps;
  final int xpReward;
  final int coinReward;
  final String? badgeReward;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> participantIds;
  final bool isDemoData;

  const ChallengeModel({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.type,
    required this.status,
    required this.targetSteps,
    required this.currentSteps,
    required this.xpReward,
    required this.coinReward,
    this.badgeReward,
    required this.startDate,
    required this.endDate,
    this.participantIds = const [],
    this.isDemoData = false,
  });

  double get progressPercent =>
      targetSteps == 0 ? 0 : (currentSteps / targetSteps).clamp(0.0, 1.0);

  int get stepsRemaining => (targetSteps - currentSteps).clamp(0, targetSteps);

  ChallengeModel copyWith({int? currentSteps, ChallengeStatus? status}) =>
      ChallengeModel(
        id: id,
        title: title,
        description: description,
        emoji: emoji,
        type: type,
        status: status ?? this.status,
        targetSteps: targetSteps,
        currentSteps: currentSteps ?? this.currentSteps,
        xpReward: xpReward,
        coinReward: coinReward,
        badgeReward: badgeReward,
        startDate: startDate,
        endDate: endDate,
        participantIds: participantIds,
        isDemoData: isDemoData,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'emoji': emoji,
        'type': type.name,
        'status': status.name,
        'targetSteps': targetSteps,
        'currentSteps': currentSteps,
        'xpReward': xpReward,
        'coinReward': coinReward,
        'badgeReward': badgeReward,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'participantIds': participantIds,
        'isDemoData': isDemoData,
      };

  factory ChallengeModel.fromJson(Map<String, dynamic> j) => ChallengeModel(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        emoji: j['emoji'] as String,
        type: ChallengeType.values
            .firstWhere((e) => e.name == j['type'], orElse: () => ChallengeType.daily),
        status: ChallengeStatus.values
            .firstWhere((e) => e.name == j['status'], orElse: () => ChallengeStatus.active),
        targetSteps: j['targetSteps'] as int,
        currentSteps: j['currentSteps'] as int,
        xpReward: j['xpReward'] as int,
        coinReward: j['coinReward'] as int,
        badgeReward: j['badgeReward'] as String?,
        startDate: DateTime.parse(j['startDate'] as String),
        endDate: DateTime.parse(j['endDate'] as String),
        participantIds: List<String>.from(j['participantIds'] as List? ?? []),
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, currentSteps, status];
}

// ─────────────────────────────────────────────────────────
// WALLET & TRANSACTIONS
// ─────────────────────────────────────────────────────────
enum TransactionType { credit, debit }
enum TransactionReason {
  stepReward,
  challengeReward,
  sessionReward,
  streakBonus,
  betStake,
  betWin,
  betLoss,
  badgeBonus,
  levelUpBonus,
  manual,
}

class WalletTransaction extends Equatable {
  final String id;
  final TransactionType type;
  final int amount;
  final TransactionReason reason;
  final String description;
  final String? referenceId;
  final DateTime timestamp;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.reason,
    required this.description,
    this.referenceId,
    required this.timestamp,
  });

  bool get isCredit => type == TransactionType.credit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'reason': reason.name,
        'description': description,
        'referenceId': referenceId,
        'timestamp': timestamp.toIso8601String(),
      };

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id: j['id'] as String,
        type: TransactionType.values
            .firstWhere((e) => e.name == j['type'], orElse: () => TransactionType.credit),
        amount: j['amount'] as int,
        reason: TransactionReason.values
            .firstWhere((e) => e.name == j['reason'], orElse: () => TransactionReason.manual),
        description: j['description'] as String,
        referenceId: j['referenceId'] as String?,
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  @override
  List<Object?> get props => [id, amount, timestamp];
}

class WalletModel extends Equatable {
  final int balance;
  final List<WalletTransaction> transactions;

  const WalletModel({required this.balance, required this.transactions});

  WalletModel addTransaction(WalletTransaction tx) {
    final newBalance = tx.isCredit ? balance + tx.amount : balance - tx.amount;
    return WalletModel(
      balance: newBalance.clamp(0, 9999999),
      transactions: [tx, ...transactions],
    );
  }

  Map<String, dynamic> toJson() => {
        'balance': balance,
        'transactions': transactions.map((t) => t.toJson()).toList(),
      };

  factory WalletModel.fromJson(Map<String, dynamic> j) => WalletModel(
        balance: j['balance'] as int,
        transactions: (j['transactions'] as List)
            .map((t) => WalletTransaction.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [balance, transactions.length];
}

// ─────────────────────────────────────────────────────────
// STEP BATTLE (BET)
// ─────────────────────────────────────────────────────────
enum BetStatus { pending, active, completed, cancelled, disputed }

class BetParticipant extends Equatable {
  final String userId;
  final String userName;
  final String avatarEmoji;
  final int currentVerifiedSteps;
  final bool isWinner;

  const BetParticipant({
    required this.userId,
    required this.userName,
    required this.avatarEmoji,
    required this.currentVerifiedSteps,
    this.isWinner = false,
  });

  BetParticipant copyWith({int? currentVerifiedSteps, bool? isWinner}) =>
      BetParticipant(
        userId: userId,
        userName: userName,
        avatarEmoji: avatarEmoji,
        currentVerifiedSteps: currentVerifiedSteps ?? this.currentVerifiedSteps,
        isWinner: isWinner ?? this.isWinner,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'avatarEmoji': avatarEmoji,
        'currentVerifiedSteps': currentVerifiedSteps,
        'isWinner': isWinner,
      };

  factory BetParticipant.fromJson(Map<String, dynamic> j) => BetParticipant(
        userId: j['userId'] as String,
        userName: j['userName'] as String,
        avatarEmoji: j['avatarEmoji'] as String,
        currentVerifiedSteps: j['currentVerifiedSteps'] as int,
        isWinner: j['isWinner'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [userId, currentVerifiedSteps, isWinner];
}

class BetModel extends Equatable {
  final String id;
  final BetParticipant challenger;
  final BetParticipant opponent;
  final int targetSteps;
  final int stakeCoins;
  final int prizeCoins;
  final String duration;
  final BetStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? completedAt;
  final bool isDemoData;

  const BetModel({
    required this.id,
    required this.challenger,
    required this.opponent,
    required this.targetSteps,
    required this.stakeCoins,
    required this.prizeCoins,
    required this.duration,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.completedAt,
    this.isDemoData = false,
  });

  BetParticipant? get winner =>
      status == BetStatus.completed
          ? (challenger.isWinner ? challenger : opponent.isWinner ? opponent : null)
          : null;

  BetModel copyWith({
    BetParticipant? challenger,
    BetParticipant? opponent,
    BetStatus? status,
    DateTime? completedAt,
  }) =>
      BetModel(
        id: id,
        challenger: challenger ?? this.challenger,
        opponent: opponent ?? this.opponent,
        targetSteps: targetSteps,
        stakeCoins: stakeCoins,
        prizeCoins: prizeCoins,
        duration: duration,
        status: status ?? this.status,
        createdAt: createdAt,
        expiresAt: expiresAt,
        completedAt: completedAt ?? this.completedAt,
        isDemoData: isDemoData,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'challenger': challenger.toJson(),
        'opponent': opponent.toJson(),
        'targetSteps': targetSteps,
        'stakeCoins': stakeCoins,
        'prizeCoins': prizeCoins,
        'duration': duration,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'isDemoData': isDemoData,
      };

  factory BetModel.fromJson(Map<String, dynamic> j) => BetModel(
        id: j['id'] as String,
        challenger:
            BetParticipant.fromJson(j['challenger'] as Map<String, dynamic>),
        opponent:
            BetParticipant.fromJson(j['opponent'] as Map<String, dynamic>),
        targetSteps: j['targetSteps'] as int,
        stakeCoins: j['stakeCoins'] as int,
        prizeCoins: j['prizeCoins'] as int,
        duration: j['duration'] as String,
        status: BetStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => BetStatus.pending,
        ),
        createdAt: DateTime.parse(j['createdAt'] as String),
        expiresAt: j['expiresAt'] != null
            ? DateTime.parse(j['expiresAt'] as String)
            : null,
        completedAt: j['completedAt'] != null
            ? DateTime.parse(j['completedAt'] as String)
            : null,
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props =>
      [id, status, challenger.currentVerifiedSteps, opponent.currentVerifiedSteps];
}

// ─────────────────────────────────────────────────────────
// LEADERBOARD
// ─────────────────────────────────────────────────────────
enum LeaderboardType { friends, hostel, classGroup, allCampus }

class LeaderboardEntry extends Equatable {
  final int rank;
  final String userId;
  final String userName;
  final String avatarEmoji;
  final String department;
  final String hostel;
  final int verifiedSteps;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.userName,
    required this.avatarEmoji,
    required this.department,
    required this.hostel,
    required this.verifiedSteps,
    this.isCurrentUser = false,
  });

  @override
  List<Object?> get props => [userId, verifiedSteps];
}
