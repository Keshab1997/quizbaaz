enum UserGender { male, female }

class UserModel {
  final String userId;
  String username;
  final String fullName;
  String avatarPath;
  String? avatarUrl; // Google profile photo URL (nullable)

  /// Active name effect id (`fire_name`, `rainbow_name`, `gold_name`), or null
  /// when no effect is equipped.
  String? nameEffect;
  UserGender gender;
  int coins;
  int gems;
  int dailyStreak;
  int xp;
  int level;
  bool isGuest;
  bool playedTodayDailyQuiz;

  /// True when this account may open the admin panel. Set from the Firestore
  /// user document (or the `admin_user_ids` list in `config/app`).
  bool isAdmin;

  /// `yyyy-MM-dd` of the last day the streak was credited. Used to grow or
  /// reset [dailyStreak] without any hardcoded value.
  String? lastStreakDate;

  /// Owned shop items: itemId (ShopItemIds) -> quantity owned.
  Map<String, int> inventory;

  UserModel({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarPath,
    this.avatarUrl,
    this.nameEffect,
    this.gender = UserGender.male,
    this.coins = 0,
    this.gems = 0,
    this.dailyStreak = 0,
    this.xp = 0,
    this.level = 1,
    this.isGuest = false,
    this.playedTodayDailyQuiz = false,
    this.isAdmin = false,
    this.lastStreakDate,
    Map<String, int>? inventory,
  }) : inventory = inventory ?? {};

  /// How many units of [itemId] this user owns.
  int inventoryCount(String itemId) => inventory[itemId] ?? 0;

  void toggleGender() {
    if (gender == UserGender.male) {
      gender = UserGender.female;
      avatarPath = 'assets/images/avatars/quizbaaz_avatar_girl.png';
    } else {
      gender = UserGender.male;
      avatarPath = 'assets/images/avatars/quizbaaz_avatar_boy.png';
    }
    // Clear Google photo when toggling gender (use local avatar instead)
    avatarUrl = null;
  }

  void updateUsername(String newUsername) {
    username = newUsername;
  }

  /// Set gender and update avatar accordingly.
  void setGender(UserGender newGender) {
    gender = newGender;
    avatarPath = newGender == UserGender.male
        ? 'assets/images/avatars/quizbaaz_avatar_boy.png'
        : 'assets/images/avatars/quizbaaz_avatar_girl.png';
    // Keep Google photo if user wants, but gender toggle clears it
    avatarUrl = null;
  }

  /// Returns the best available avatar: remote URL > local asset.
  String get effectiveAvatar => avatarUrl ?? avatarPath;
  bool get hasGoogleAvatar => avatarUrl != null && avatarUrl!.isNotEmpty;

  /// Grows or resets the daily streak based on the last play date.
  /// Returns true when the streak changed (so the caller can persist).
  bool registerPlayOn(DateTime now) {
    final today = _dateKey(now);
    if (lastStreakDate == today) return false;

    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    dailyStreak = lastStreakDate == yesterday ? dailyStreak + 1 : 1;
    lastStreakDate = today;
    playedTodayDailyQuiz = true;
    return true;
  }

  /// Clears [playedTodayDailyQuiz] when the stored streak date is not today.
  void refreshDailyFlags(DateTime now) {
    if (lastStreakDate != _dateKey(now)) {
      playedTodayDailyQuiz = false;
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ----------------------------------------------------------------- JSON --

  /// Fields the CLIENT is allowed to write to Firestore (see
  /// `firestore.rules`, PROFILE_KEYS). Wallet, competitive and admin state
  /// (`coins`, `gems`, `xp`, `level`, `daily_streak`, `last_streak_date`,
  /// `played_today_daily_quiz`, `inventory`, `is_admin`) is server-written
  /// only — the trusted backend in `/functions` owns those values.
  Map<String, dynamic> profileToJson() => {
        'user_id': userId,
        'username': username,
        'full_name': fullName,
        'avatar_path': avatarPath,
        'avatar_url': avatarUrl,
        'name_effect': nameEffect,
        'gender': gender.name,
        'is_guest': isGuest,
      };

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'full_name': fullName,
        'avatar_path': avatarPath,
        'avatar_url': avatarUrl,
        'name_effect': nameEffect,
        'gender': gender.name,
        'coins': coins,
        'gems': gems,
        'daily_streak': dailyStreak,
        'xp': xp,
        'level': level,
        'is_guest': isGuest,
        'played_today_daily_quiz': playedTodayDailyQuiz,
        'is_admin': isAdmin,
        'last_streak_date': lastStreakDate,
        'inventory': inventory,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      avatarPath: json['avatar_path'] as String? ??
          'assets/images/avatars/quizbaaz_avatar_boy.png',
      avatarUrl: json['avatar_url'] as String?,
      nameEffect: json['name_effect'] as String?,
      gender:
          (json['gender'] as String? ?? 'male') == 'male' ? UserGender.male : UserGender.female,
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      gems: (json['gems'] as num?)?.toInt() ?? 0,
      dailyStreak: (json['daily_streak'] as num?)?.toInt() ?? 0,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      isGuest: json['is_guest'] as bool? ?? false,
      playedTodayDailyQuiz: json['played_today_daily_quiz'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      lastStreakDate: json['last_streak_date'] as String?,
      inventory: (json['inventory'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
    );
  }

  // -------------------------------------------------------------- Defaults --

  // -------------------------------------------------------------- Factories --

  /// A brand-new local profile. Everything starts at zero — no fake coins,
  /// no fake streak. Real values come from gameplay (Hive) or Firestore.
  factory UserModel.newPlayer({bool isGuest = true}) {
    return UserModel(
      userId: 'local_${DateTime.now().millisecondsSinceEpoch}',
      username: isGuest ? 'guest' : 'player',
      fullName: isGuest ? 'Guest' : 'Player',
      avatarPath: 'assets/images/avatars/quizbaaz_avatar_boy.png',
      gender: UserGender.male,
      coins: 0,
      gems: 0,
      dailyStreak: 0,
      xp: 0,
      level: 1,
      isGuest: isGuest,
      inventory: const {},
    );
  }

  /// Kept for backwards compatibility with existing call sites.
  factory UserModel.defaultUser() => UserModel.newPlayer(isGuest: false);

  factory UserModel.guestUser() => UserModel.newPlayer(isGuest: true);

  /// Copy helper used when merging remote data into the local profile.
  UserModel copyWith({
    String? userId,
    String? username,
    String? fullName,
    String? avatarPath,
    String? avatarUrl,
    String? nameEffect,
    UserGender? gender,
    int? coins,
    int? gems,
    int? dailyStreak,
    int? xp,
    int? level,
    bool? isGuest,
    bool? playedTodayDailyQuiz,
    bool? isAdmin,
    String? lastStreakDate,
    Map<String, int>? inventory,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      nameEffect: nameEffect ?? this.nameEffect,
      gender: gender ?? this.gender,
      coins: coins ?? this.coins,
      gems: gems ?? this.gems,
      dailyStreak: dailyStreak ?? this.dailyStreak,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      isGuest: isGuest ?? this.isGuest,
      playedTodayDailyQuiz: playedTodayDailyQuiz ?? this.playedTodayDailyQuiz,
      isAdmin: isAdmin ?? this.isAdmin,
      lastStreakDate: lastStreakDate ?? this.lastStreakDate,
      inventory: inventory ?? Map<String, int>.from(this.inventory),
    );
  }
}
