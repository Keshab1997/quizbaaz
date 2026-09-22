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

#### Or let GitHub Actions build it

The same injection is wired into `.github/workflows/manual-build.yml` and
`.github/workflows/publish-release.yml` (both call the shared
[`Keshab1997/flutter-builder`](https://github.com/Keshab1997/flutter-builder)
workflow). Store the three IDs once as **repository variables** — they are
public identifiers that end up in the binary anyway, so they do not need to be
secrets:

```text
Settings → Secrets and variables → Actions → Variables → New repository variable
  ADMOB_APP_ID           ca-app-pub-…~…
  ADMOB_BANNER_ID        ca-app-pub-…/…
  ADMOB_INTERSTITIAL_ID  ca-app-pub-…/…
```

and the signing material as **secrets** (`ANDROID_KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; see the builder's
`docs/ANDROID_SIGNING.md`). Then:

- **Actions → Manual Android Build → Run workflow** — `apk` or `aab`, and
  `ads: test` (default, safe to click) or `ads: real`. The file is in the run's
  Artifacts.
- **Actions → Publish Android Release → Run workflow** — always real IDs;
  refuses to start if a variable is missing or still a Google test ID. Produces
  the `v<version>` tag, a GitHub Release with English notes, and the versioned
  `.apk`/`.aab` + `SHA256SUMS.txt` to upload to the Play Console.

### 4. Legal and Play Console

Before closed testing:

- verify the hosted privacy policy remains aligned with Firebase Storage,
  AdMob and OneSignal data handling;
- enter `https://keshab1997.github.io/privacy_policy/quizbaaz-delete-account.html`
  as the external account-deletion URL in Data safety;
- complete Data safety, Ads, Target audience, Content rating and App access;
- monitor the public support email `keshabsarkar2018@gmail.com`;
- provide reviewer instructions/test credentials for any gated feature.

If targeting children, complete Families requirements and configure AdMob for
that audience. Do not describe virtual gifts as cash or real-world prizes.

### 5. Or publish the listing + AAB via the API

The store listing and every later AAB upload can skip the Console forms
entirely: [docs/20](20_PLAY_STORE_API_PUBLISH.md) automates them through the
Play Developer API once a linked service account exists. The listing source of
truth is `store_listing/listing.yaml`, published by
`tool/publish_play.py` and by the **Play Store — Publish Listing & AAB**
workflow. The one-time Play-side setup is §2 there; the repeatable steps are
the rest.

## Store listing draft

The canonical, checked-in listing is `store_listing/listing.yaml` (app name,
short and full description per language, images) — `tool/publish_play.py
--listing` uploads exactly that, `--validate` enforces the limits below. The
draft that populated it at launch:

**App name (30 max)**

`QuizBaaz: Class 10 Exam Prep`

**Short description (80 max)**

`Daily Class 10 MCQ quizzes, streaks, rewards and battles for exam prep.`

**Suggested category**

Education

**Suggested tags**

Education, Quiz, Learning, Exam preparation, Offline

Screenshots must show the real submitted build. Capture at least four portrait
screens at 1080 × 1920 (dashboard, chapter quiz, daily quiz,
leaderboard/rewards, profile/languages) and drop them into
`store_listing/screenshots/`. Include Battle only when its production flow is
complete.

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
3. Upload `build/app/outputs/bundle/release/app-release.aab` — or the
   `QuizBaaz-v<version>.aab` attached to the GitHub Release when the build
   came from **Publish Android Release**.
4. Review the pre-launch report and Android vitals before promotion.
5. New personal accounts created after 13 November 2023 must complete the
   required closed test (currently 12 opted-in testers for 14 continuous days)
   before applying for production access.
