/// Same identity rule as [leaderboardRowBelongsToUser] — uid only, never the
/// username (R12).
bool championRowBelongsToUser(
  ChampionModel champion, {
  required String userId,
}) =>
    userId.isNotEmpty && champion.userId == userId;

class ChampionModel {
  final int rank;
  final String userId;
  final String name;
  final String username;
  final String avatarPath;
  final int score;
  final double timeSeconds;
  final String giftName;
  final String giftIcon;
  final int bonusCoins;
  final String badgeTitle;
  final String nameEffect;

  /// The day this champion won on, as a `yyyy-MM-dd` key (e.g. '2026-08-27').
  final String dateKey;

  ChampionModel({
    required this.rank,
    required this.userId,
    required this.name,
    required this.username,
    required this.avatarPath,
    required this.score,
    required this.timeSeconds,
    required this.giftName,
    required this.giftIcon,
    required this.bonusCoins,
    required this.badgeTitle,
    this.nameEffect = '',
    this.dateKey = '',
  });

  /// Parsed date of this win, or null when [dateKey] is missing/invalid.
  DateTime? get date {
    final parts = dateKey.split('-');
    if (parts.length != 3) return null;
    try {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  factory ChampionModel.fromJson(Map<String, dynamic> json) {
    return ChampionModel(
      rank: json['rank'] ?? 1,
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      avatarPath: json['avatar_path'] ?? '',
      score: json['score'] ?? 0,
      timeSeconds: (json['time_seconds'] as num?)?.toDouble() ?? 0.0,
      giftName: json['gift_name'] ?? '',
      giftIcon: json['gift_icon'] ?? '',
      bonusCoins: json['bonus_coins'] ?? 0,
      badgeTitle: json['badge_title'] ?? '',
      nameEffect: json['name_effect'] ?? '',
      dateKey: json['date_key'] ?? json['date'] ?? '',
    );
  }
}
