class AppAssets {
  // Premium 3D characters (generated for the QuizBaaz visual system).
  static const String heroBoy =
      'assets/images/characters/quizbaaz_mascot_boy.png';
  static const String heroGirl =
      'assets/images/characters/quizbaaz_mascot_girl.png';
  static const String championBoy =
      'assets/images/characters/quizbaaz_champion.png';
  static const String quizChampion =
      'assets/images/characters/quizbaaz_quiz_guide.png';
  static const String dailyStar =
      'assets/images/characters/quizbaaz_daily_star.png';
  static const String battleDuo =
      'assets/images/characters/quizbaaz_battle_duo.png';
  static const String battleFighterBlue =
      'assets/images/characters/battle_fighter_blue.png';
  static const String battleFighterPink =
      'assets/images/characters/battle_fighter_pink.png';
  static const String rewardGirl =
      'assets/images/characters/quizbaaz_reward_girl.png';

  // Default profile avatars.
  static const String maleAvatar =
      'assets/images/avatars/quizbaaz_avatar_boy.png';
  static const String femaleAvatar =
      'assets/images/avatars/quizbaaz_avatar_girl.png';
  static const String userAvatarBoy = maleAvatar; // Backwards compatibility.

  // ═══════════════════════════════════════════════════════════════════════
  // 🎨 3D AVATARS - Male
  // ═══════════════════════════════════════════════════════════════════════
  static const String maleAvatar1 = 'assets/images/avatars/male_avatar_1.png';
  static const String maleAvatar2 = 'assets/images/avatars/male_avatar_2.png';
  static const String maleAvatar3 = 'assets/images/avatars/male_avatar_3.png';
  static const String maleAvatar4 = 'assets/images/avatars/male_avatar_4.png';

  // ═══════════════════════════════════════════════════════════════════════
  // 🎨 3D AVATARS - Female
  // ═══════════════════════════════════════════════════════════════════════
  static const String femaleAvatar1 =
      'assets/images/avatars/female_avatar_1.png';
  static const String femaleAvatar2 =
      'assets/images/avatars/female_avatar_2.png';
  static const String femaleAvatar3 =
      'assets/images/avatars/female_avatar_3.png';
  static const String femaleAvatar4 =
      'assets/images/avatars/female_avatar_4.png';
  static const String dailyStarAvatar =
      'assets/images/avatars/daily_star_avatar.png';

  // ═══════════════════════════════════════════════════════════════════════
  // 👑 PREMIUM SHOP AVATARS
  // ═══════════════════════════════════════════════════════════════════════
  static const String vipAvatar = 'assets/images/avatars/vip_avatar.png';
  static const String goldenKnightAvatar =
      'assets/images/avatars/golden_knight_avatar.png';
  static const String neonCyberAvatar =
      'assets/images/avatars/neon_cyber_avatar.png';
  static const String royalCrownAvatar =
      'assets/images/avatars/royal_crown_avatar.png';

  // ═══════════════════════════════════════════════════════════════════════
  // 📋 AVATAR LISTS (for selection screens)
  // ═══════════════════════════════════════════════════════════════════════
  static const List<String> maleAvatars = [
    maleAvatar,
    maleAvatar1,
    maleAvatar2,
    maleAvatar3,
    maleAvatar4,
  ];

  static const List<String> femaleAvatars = [
    femaleAvatar,
    femaleAvatar1,
    femaleAvatar2,
    femaleAvatar3,
    femaleAvatar4,
    dailyStarAvatar,
  ];

  static const List<String> premiumAvatars = [
    vipAvatar,
    goldenKnightAvatar,
    neonCyberAvatar,
    royalCrownAvatar,
  ];

  // All avatars combined
  static const List<String> allAvatars = [
    ...maleAvatars,
    ...femaleAvatars,
    ...premiumAvatars,
  ];

  // Existing glossy action icons are still used by secondary screens.
  static const String streakFire = 'assets/icons/streak_fire_3d.png';
  static const String streakFire3d = 'assets/icons/streak_fire_3d.png';
  static const String streakShield3d = 'assets/icons/streak_shield_3d.png';
  static const String streakCrown3d = 'assets/icons/streak_crown_3d.png';
  static const String streakBroken3d = 'assets/icons/streak_broken_3d.png';
  static const String coinGem = 'assets/icons/coin_and_gem_3d.png';
  static const String chapterQuiz = 'assets/icons/chapter_quiz_3d.png';
  static const String practiceTarget = 'assets/icons/practice_target_3d.png';
  static const String battleSwords = 'assets/icons/battle_swords_3d.png';
  static const String giftBox = 'assets/icons/gift_box_3d.png';
  static const String shopStall = 'assets/icons/shop_stall_3d.png';

  // JSON question banks (authored content, cached in Hive after first read).
  // Ranking data is NEVER bundled — it comes from Firestore via Hive.
  static const String jsonChapters = 'assets/data/chapters_list.json';
  static const String jsonDailyQuiz = 'assets/data/daily_quiz.json';
}
