/// Identity rule for **reward matching**: a row belongs to a user when the
/// uids match, and only then.
///
/// Usernames are player-editable and not unique — two accounts can both be
/// "riyad" — so matching on the username could credit a prize to the wrong
/// player, or double-credit one (R12).
bool leaderboardRowBelongsToUser(LeaderboardItem item, {required String userId}) =>
    userId.isNotEmpty && item.userId == userId;

class LeaderboardItem {
  final int rank;
  final String userId;
  final String name;
  final String username;
  final String avatarPath;
  final int score;
  final double timeSeconds;
  final int streak;
  final String nameEffect;

  LeaderboardItem({
    required this.rank,
    this.userId = '',
    required this.name,
    required this.username,
    required this.avatarPath,
    required this.score,
    required this.timeSeconds,
    required this.streak,
    this.nameEffect = '',
  });

  factory LeaderboardItem.fromJson(Map<String, dynamic> json) {
    return LeaderboardItem(
      rank: json['rank'] ?? 1,
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      avatarPath: json['avatar_path'] ?? '',
      score: json['score'] ?? 0,
      timeSeconds: (json['time_seconds'] as num?)?.toDouble() ?? 0.0,
      streak: json['streak'] ?? 1,
      nameEffect: json['name_effect'] ?? '',
    );
  }
}
