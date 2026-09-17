/// AdMob configuration for QuizBaaz.
///
/// ⚠️ HOW TO GO LIVE (before publishing to Play Store):
///
/// 1. Create the "QuizBaaz" app in the AdMob console
///    (https://apps.admob.com) using the package name
///    `com.keshabstudios.quizbaaz`.
/// 2. Create one **Banner** ad unit and one **Interstitial** ad unit.
/// 3. Pass the IDs at build time instead of committing them:
///    `ADMOB_APP_ID=... flutter build appbundle --release`
///    plus `--dart-define=ADMOB_BANNER_ID=...` and
///    `--dart-define=ADMOB_INTERSTITIAL_ID=...`.
///
/// Until then the **official Google test IDs** below are used, which show
/// harmless test ads. See `docs/17_PLAY_STORE_RELEASE.md`.
class AdConfig {
  AdConfig._();

  /// Informational app ID used by Dart; Android reads the matching manifest
  /// placeholder from `ADMOB_APP_ID`.
  static const String appId = String.fromEnvironment(
    'ADMOB_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );

  /// Real IDs are injected for release builds; local builds stay on Google's
  /// safe test units and can never generate invalid traffic.
  static const String bannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );

  static const String interstitialAdUnitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  /// Show the interstitial after every N quiz completions (2 = every 2nd
  /// quiz). Keeps ads frequent enough to earn, but never spammy.
  static const int interstitialFrequency = 2;

  /// Hive meta key holding the quiz-completion counter for [interstitialFrequency].
  static const String quizCounterKey = 'ad_quiz_counter';
}
