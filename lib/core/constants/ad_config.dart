/// AdMob configuration for QuizBaaz.
///
/// ⚠️ Ad IDs are injected at build time with `--dart-define`; none are
/// hardcoded under `lib/` on purpose. The shared release builder refuses to
/// build a release while Google's *test* ad unit IDs appear anywhere in
/// `lib/`, so they must never be written back into this file.
///
/// How the values arrive:
///  * Play releases — `Publish Android Release` injects the real IDs from
///    the repository's Actions variables (docs/17_PLAY_STORE_RELEASE.md).
///  * Manual builds — `manual-build.yml` with `ads: test` passes Google's
///    published test unit IDs; `ads: real` passes the real ones.
///  * Local `flutter run` — with no defines the IDs stay empty and
///    [AdService] simply never loads an ad. To see ads locally, pass your
///    own: `flutter run --dart-define=ADMOB_APP_ID=…`
///    `--dart-define=ADMOB_BANNER_ID=…`
///    `--dart-define=ADMOB_INTERSTITIAL_ID=…`.
class AdConfig {
  AdConfig._();

  /// Informational app ID used by Dart; Android reads the matching manifest
  /// placeholder from `ADMOB_APP_ID` (see android/app/build.gradle.kts).
  static const String appId = String.fromEnvironment('ADMOB_APP_ID');

  /// Banner ad unit; empty (ads off) unless injected at build time.
  static const String bannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
  );

  /// Interstitial ad unit; empty (ads off) unless injected at build time.
  static const String interstitialAdUnitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
  );

  /// Show the interstitial after every N quiz completions (2 = every 2nd
  /// quiz). Keeps ads frequent enough to earn, but never spammy.
  static const int interstitialFrequency = 2;

  /// Hive meta key holding the quiz-completion counter for
  /// [interstitialFrequency].
  static const String quizCounterKey = 'ad_quiz_counter';
}
