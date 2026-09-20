# QuizBaaz — Play Store Publish TODO

এই checklist-টি উপর থেকে নিচে অনুসরণ করুন। কোনো password, keystore, service-account
JSON বা private key GitHub-এ commit করবেন না। বিস্তারিত command ও explanation-এর
জন্য [`17_PLAY_STORE_RELEASE.md`](17_PLAY_STORE_RELEASE.md) দেখুন।

## Project information

- App name: **QuizBaaz**
- Package name: `com.keshabstudios.quizbaaz`
- Support email: `keshabsarkar2018@gmail.com`
- Privacy policy: <https://keshab1997.github.io/privacy_policy/quizbaaz.html>
- Terms: <https://keshab1997.github.io/privacy_policy/quizbaaz-terms.html>
- Account deletion: <https://keshab1997.github.io/privacy_policy/quizbaaz-delete-account.html>
- Play icon: `assets/branding/play_store_icon_512.png`
- Feature graphic: `assets/branding/play_store_feature_graphic.png`

---

## Phase 1 — Play Console account

- [ ] Google Play Developer account খুলুন এবং one-time fee পরিশোধ করুন।
- [ ] Personal/Organization account type সঠিকভাবে নির্বাচন করুন।
- [ ] Identity, email, phone এবং প্রয়োজন হলে Android device verification শেষ করুন।
- [ ] Public developer name এবং support email যাচাই করুন।
- [ ] Payments profile-এর legal name/address সঠিক আছে কিনা দেখুন।
- [ ] Account owner-এর Google account-এ 2-Step Verification চালু করুন।

## Phase 2 — Play Console-এ app তৈরি

- [ ] **Create app** থেকে default language নির্বাচন করুন।
- [ ] App name দিন: `QuizBaaz: Play & Learn`।
- [ ] App/Game: বাস্তব Play Console classification অনুযায়ী নির্বাচন করুন।
- [ ] Free নির্বাচন করুন; পরে free app-কে paid করা যায় না।
- [ ] Package name final হিসেবে নিশ্চিত করুন: `com.keshabstudios.quizbaaz`।
- [ ] Play App Signing enable করার পরিকল্পনা নিশ্চিত করুন।

## Phase 3 — Upload keystore ও release signing

- [ ] `keytool` দিয়ে `quizbaaz-upload.jks` তৈরি করুন।
- [ ] `android/key.properties.example` কপি করে `android/key.properties` বানান।
- [ ] আসল keystore path, alias ও passwords local file-এ দিন।
- [ ] Keystore ও passwords-এর অন্তত দুইটি encrypted backup রাখুন।
- [ ] নিশ্চিত করুন `.jks` এবং `android/key.properties` Git-এ নেই।
- [ ] Upload key-এর SHA-1 ও SHA-256 সংগ্রহ করুন।

## Phase 4 — Firebase ও Google Sign-In

- [ ] Firebase Android app-এর package name একই কিনা দেখুন।
- [ ] Upload key-এর SHA-1 এবং SHA-256 Firebase-এ যোগ করুন।
- [ ] Play App Signing চালু হলে Play **App signing certificate**-এর SHA-1/SHA-256-ও যোগ করুন।
- [ ] Updated `google-services.json` download করে app configuration যাচাই করুন।
- [ ] Google OAuth consent screen Production/Published অবস্থায় আছে কিনা দেখুন।
- [ ] Play Internal Testing থেকে install করে Google Sign-In পরীক্ষা করুন।
- [ ] Firestore, Storage এবং Cloud Functions production project-এ deploy আছে কিনা দেখুন।
- [ ] Firestore/Storage rules এবং admin permissions পরীক্ষা করুন।

## Phase 5 — AdMob এখন যা করবেন

- [ ] AdMob Console-এ Android app হিসেবে **QuizBaaz** তৈরি করুন।
- [ ] Package name দিন: `com.keshabstudios.quizbaaz`।
- [ ] Store listing না থাকলে **app is not listed on a supported app store** নির্বাচন করুন।
- [ ] AdMob App ID তৈরি/কপি করুন।
- [ ] Banner Ad Unit ID তৈরি/কপি করুন।
- [ ] Interstitial Ad Unit ID তৈরি/কপি করুন।
- [ ] নিচের release-values নিরাপদ password manager-এ রাখুন, GitHub-এ নয়:

```text
ADMOB_APP_ID=
ADMOB_BANNER_ID=
ADMOB_INTERSTITIAL_ID=
```

- [ ] একই তিনটি মান GitHub repo-র **Settings → Secrets and variables → Actions → Variables**-এ
  `ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID` নামে রাখুন — Actions-এর
  release build এখান থেকেই ID নেয় (`docs/17` → "Or let GitHub Actions build it")।
- [ ] Local development-এ Google test ad IDs ব্যবহার করুন।
- [ ] নিজের physical test device AdMob test device হিসেবে register করুন।
- [ ] UMP consent এবং **Privacy choices** entry point পরীক্ষা করুন।
- [ ] Real ad-এ নিজে click করবেন না।

> Production-এ যে AAB যাবে, সেই build-এ real AdMob IDs থাকতে হবে। Play Store-এ
> live হওয়ার পরে ID পাল্টালে নতুন app update প্রকাশ করতে হবে।

## Phase 6 — Store listing

- [ ] App title সর্বোচ্চ 30 characters রাখুন।
- [ ] Short description সর্বোচ্চ 80 characters রাখুন।
- [ ] Full description সর্বোচ্চ 4,000 characters লিখুন।
- [ ] Category হিসেবে উপযুক্ত `Education`/`Educational` classification দিন।
- [ ] Contact email হিসেবে `keshabsarkar2018@gmail.com` দিন।
- [ ] 512×512 Play icon upload করুন।
- [ ] 1024×500 feature graphic upload করুন।
- [ ] Submitted build থেকে কমপক্ষে 4টি 1080×1920 phone screenshot নিন:
  - [ ] Dashboard
  - [ ] Chapter quiz
  - [ ] Daily quiz
  - [ ] Leaderboard/rewards
  - [ ] Profile/language (recommended)
- [ ] অসম্পূর্ণ feature screenshot বা description-এ দেখাবেন না।
- [ ] Bengali/Hindi listing দরকার হলে আলাদা localized listing তৈরি করুন।

## Phase 7 — Policy ও App content forms

- [ ] Privacy Policy URL দিন।
- [ ] Account deletion URL দিন।
- [ ] Data Safety form SDK-সহ সঠিকভাবে পূরণ করুন:
  - [ ] Name, email এবং Google profile-photo URL
  - [ ] Gameplay, score, quiz history এবং leaderboard data
  - [ ] Device/advertising identifiers ও ad interaction data
  - [ ] Push subscription/device data (OneSignal/FCM)
  - [ ] Firebase Auth, Firestore, Storage, AdMob, UMP এবং OneSignal
  - [ ] Encryption in transit এবং account deletion
- [ ] **Contains ads** declaration-এ Yes দিন, যদি real ads enabled থাকে।
- [ ] Content rating questionnaire সঠিকভাবে পূরণ করুন।
- [ ] Target audience age groups বাস্তব audience অনুযায়ী নির্বাচন করুন।
- [ ] Under-13 audience থাকলে Families Policy ও child-safe ads requirements শেষ করুন।
- [ ] App access-এ reviewer instructions/test account দিন, যদি কোনো অংশ gated হয়।
- [ ] Health apps declaration পূরণ করুন, feature না থাকলে No নির্বাচন করুন।
- [ ] Financial features declaration পূরণ করুন, feature না থাকলে No নির্বাচন করুন।
- [ ] Virtual rewards-এর কোনো real-world/cash value নেই—listing-এ বিভ্রান্তিকর দাবি করবেন না।

## Phase 8 — Code quality ও production build

- [ ] অসম্পূর্ণ Battle/online feature production-এ hide করুন অথবা সম্পূর্ণ test করুন।
- [ ] `pubspec.yaml`-এ version name/build number final করুন; প্রতিটি upload-এ `+N` বাড়ান।
- [ ] নিচের checks চালান:

```bash
flutter clean
flutter pub get
python3 tool/gen_strings.py
python3 tool/verify_l10n.py
python3 tool/validate_questions.py
flutter analyze
flutter test
```

- [ ] Real AdMob IDs দিয়ে signed AAB build করুন:

```bash
ADMOB_APP_ID='ca-app-pub-...~...' \
flutter build appbundle --release \
  --dart-define=ADMOB_APP_ID='ca-app-pub-...~...' \
  --dart-define=ADMOB_BANNER_ID='ca-app-pub-.../...' \
  --dart-define=ADMOB_INTERSTITIAL_ID='ca-app-pub-.../...'
```

- [ ] Output যাচাই করুন:

```text
build/app/outputs/bundle/release/app-release.aab
```

- [ ] **অথবা GitHub Actions দিয়ে:** signing secrets (`ANDROID_KEYSTORE_BASE64`,
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) যোগ করে **Actions → Publish
  Android Release → Run workflow** চালান; GitHub Release-এর
  `QuizBaaz-v<version>.aab` Play Console-এ upload করুন। শুধু test build দরকার হলে
  **Manual Android Build** (`ads: test`) ব্যবহার করুন।

- [ ] App Bundle Explorer-এ target API 36 ও signing status যাচাই করুন।
- [ ] 64-bit/native library ও 16 KB page-size warnings আছে কিনা দেখুন।

## Phase 9 — Internal Testing

- [ ] AAB Internal Testing track-এ upload করুন।
- [ ] Play Store opt-in link থেকে fresh install করুন।
- [ ] Test করুন:
  - [ ] Guest onboarding
  - [ ] Google Sign-In/sign-out/re-authentication
  - [ ] Chapter ও daily quiz
  - [ ] Offline mode এবং network reconnect
  - [ ] Coins, rewards, leaderboard ও sync
  - [ ] Account deletion এবং local-data cleanup
  - [ ] Banner/interstitial placement
  - [ ] UMP consent/privacy choices
  - [ ] Local এবং OneSignal notification
  - [ ] Bengali, Hindi ও English
  - [ ] App restart, background এবং low-memory recovery
  - [ ] বিভিন্ন screen size ও Android version
- [ ] Play pre-launch report-এর crash, ANR, accessibility ও security warning ঠিক করুন।

## Phase 10 — Closed Testing ও production access

- [ ] Play Console account testing requirement দেখুন।
- [ ] নতুন Personal account হলে অন্তত 12 জন real tester যোগ করুন।
- [ ] Tester-দের Closed Testing opt-in link দিন।
- [ ] অন্তত 14 continuous days opt-in বজায় রাখুন।
- [ ] Feedback সংগ্রহ করে bug fixes লিখে রাখুন।
- [ ] Requirement পূর্ণ হলে Production access-এর জন্য apply করুন।
- [ ] Google-এর production-access questionnaire সঠিকভাবে পূরণ করুন।

## Phase 11 — Production release

- [ ] Countries/regions নির্বাচন করুন।
- [ ] Final AAB ও release notes যোগ করুন।
- [ ] Play Console-এর সব error resolve করুন; warning-গুলো review করুন।
- [ ] Data Safety, privacy policy এবং binary behavior আবার মিলিয়ে দেখুন।
- [ ] Review-এর জন্য changes submit করুন।
- [ ] Managed publishing ব্যবহার করলে approval-এর পরে Publish করুন।

## Phase 12 — Play Store live হওয়ার পরে AdMob

- [ ] AdMob Console-এ QuizBaaz খুলুন।
- [ ] Live Google Play listing-এর সঙ্গে app link করুন।
- [ ] Developer website/domain-এ `app-ads.txt` publish করুন।
- [ ] AdMob থেকে `app-ads.txt` verification status দেখুন।
- [ ] AdMob app readiness review complete হওয়া পর্যন্ত status monitor করুন।
- [ ] Ads limited/disabled হলে Policy Center-এর কারণ ঠিক করুন।
- [ ] নিজের ad click না করে test-device configuration দিয়ে ads পরীক্ষা করুন।
- [ ] Revenue, match rate, consent এবং invalid-traffic alerts monitor করুন।

## Phase 13 — Launch monitoring

- [ ] Android Vitals-এ crash rate ও ANR দেখুন।
- [ ] Firebase/Cloud Functions errors এবং Firestore usage monitor করুন।
- [ ] Support inbox `keshabsarkar2018@gmail.com` নিয়মিত দেখুন।
- [ ] Account-deletion requests verify করে সময়মতো process করুন।
- [ ] Reviews-এর reply দিন; user data public reply-তে লিখবেন না।
- [ ] জরুরি bug fix-এর জন্য build number বাড়িয়ে update প্রকাশ করুন।
- [ ] পরবর্তী release-এর আগে policy ও target API changes review করুন।
