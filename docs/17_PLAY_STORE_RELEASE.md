# 17 — Google Play release

This is the single source of truth for QuizBaaz Android releases.

## Already configured in the repository

- Permanent application ID: `com.keshabstudios.quizbaaz`
- Android `compileSdk` / `targetSdk`: API 36
- Release builds never fall back to the debug signing key
- Adaptive and legacy QuizBaaz launcher icons
- Play Console icon: `assets/branding/play_store_icon_512.png`
- Feature graphic: `assets/branding/play_store_feature_graphic.png`
- Test AdMob IDs remain the safe default; real IDs are injected at build time

## Owner setup (one time)

### 1. Create and protect the upload key

```bash
keytool -genkeypair -v \
  -keystore "$HOME/quizbaaz-upload.jks" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
cp android/key.properties.example android/key.properties
```

Put the real values and absolute keystore path in `android/key.properties`.
Both files are gitignored. Back up the keystore and passwords securely; never
send or commit them. Enable Play App Signing on the first Play Console upload.

### 2. Register release certificates

Print the upload certificate fingerprints:

```bash
keytool -list -v -keystore "$HOME/quizbaaz-upload.jks" -alias upload
```

Add its SHA-1 and SHA-256 in Firebase. After enrolling in Play App Signing, add
the Play Console **App signing key certificate** SHA-1 and SHA-256 as well, then
download the refreshed `google-services.json`. Test Google Sign-In from a Play
internal-test install, not only from a locally installed APK.

### 3. AdMob

Create the Android app in AdMob with the permanent package name, then create a
banner and an interstitial unit. Build with real IDs only for a Play release:

```bash
ADMOB_APP_ID='ca-app-pub-...~...' \
flutter build appbundle --release \
  --dart-define=ADMOB_APP_ID='ca-app-pub-...~...' \
  --dart-define=ADMOB_BANNER_ID='ca-app-pub-.../...' \
  --dart-define=ADMOB_INTERSTITIAL_ID='ca-app-pub-.../...'
```

Local builds deliberately use Google's test IDs. Configure `app-ads.txt` and
verify the UMP consent/privacy-options flow before enabling real traffic.

### 4. Legal and Play Console

Before closed testing:

- update the hosted privacy policy so it matches Firebase Storage, AdMob and
  OneSignal data handling;
- publish a dedicated external account-deletion request page and enter its URL
  in Data safety;
- complete Data safety, Ads, Target audience, Content rating and App access;
- use a monitored public support email;
- provide reviewer instructions/test credentials for any gated feature.

If targeting children, complete Families requirements and configure AdMob for
that audience. Do not describe virtual gifts as cash or real-world prizes.

## Store listing draft

**App name (30 max)**

`QuizBaaz: Play & Learn`

**Short description (80 max)**

`Master Class 10 subjects with daily quizzes, streaks, rewards and battles.`

**Suggested category**

Education

**Suggested tags**

Education, Quiz, Learning, Exam preparation, Offline

Screenshots must show the real submitted build. Capture at least four portrait
screens at 1080 × 1920: dashboard, chapter quiz, daily quiz, leaderboard/rewards
and profile/languages. Include Battle only when its production flow is complete.

## Every release

```bash
flutter clean
flutter pub get
python3 tool/gen_strings.py
python3 tool/verify_l10n.py
python3 tool/validate_questions.py
flutter analyze
flutter test
# Run the AdMob-injected build command above.
```

Then:

1. Verify `pubspec.yaml` has a unique, incremented build number (`+N`).
2. Install through Play Internal testing and test fresh install, upgrade,
   guest mode, Google Sign-In, offline quiz, account deletion, ads, consent,
   notifications, Bengali/Hindi, low-memory restart and network loss.
3. Upload `build/app/outputs/bundle/release/app-release.aab`.
4. Review the pre-launch report and Android vitals before promotion.
5. New personal accounts created after 13 November 2023 must complete the
   required closed test (currently 12 opted-in testers for 14 continuous days)
   before applying for production access.
