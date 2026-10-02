# Project Review — QuizBaaz Flutter

> [!NOTE]
> **Historical snapshot (7 Sep 2026).** Kept for the reasoning behind each finding, but the numbers and
> status below are out of date: the bundled banks are no longer empty (510 questions / 56 chapter banks),
> the sound assets are real files, GitHub Actions CI exists, and the three P0 items (R01–R03) were fixed —
> see [`docs/SECURITY_P0_FIXES.md`](docs/SECURITY_P0_FIXES.md). The status of R04–R24 was not re-audited
> when this note was added; check the code before acting on one.

> **Review date:** 7 September 2026 · Asia/Kolkata<br>
> **Repository:** [Keshab1997/quizbaaz-flutter](https://github.com/Keshab1997/quizbaaz-flutter)<br>
> **Reviewed snapshot:** [`5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2`](https://github.com/Keshab1997/quizbaaz-flutter/commit/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2) · branch `main`<br>
> **Change scope:** এই commit-এ শুধু review document; কোনো application code, rules, dependencies বা production configuration ঠিক করা হয়নি।

## Executive summary

**ভালো feature foundation আছে, কিন্তু এই source snapshot-কে production-ready বলা যাচ্ছে না।** নতুন screen বা animation যোগ করার আগে security, account identity, offline content এবং quiz/battle correctness ঠিক করা প্রয়োজন।

সবচেয়ে জরুরি কাজ:

1. **Committed ImgBB upload credential বদলানো ও client থেকে সরানো।**
2. **Admin role, wallet, score, reward ও battle outcome-এর authority trusted backend-এ নেওয়া।**
3. **Firestore rules-এর সঙ্গে বাস্তবে ব্যবহৃত collections/operations মিলিয়ে নেওয়া।** বর্তমান rules একদিকে কিছু sensitive write অনুমতি দিচ্ছে, অন্যদিকে প্রয়োজনীয় feature operations আটকাচ্ছে।
4. **Profile sign-in-এর UID এবং sign-out/account-switch flow ঠিক করা।**
5. **খালি question bank, practice reward, quiz timer এবং live battle-এর data/navigation bugs ঠিক করা।**

### Snapshot at a glance

| বিষয় | যাচাই করা অবস্থা |
|---|---|
| Tracked files | 389, review document যোগ করার আগের snapshot |
| Dart application code | `lib/`-এ 100টি Dart file; 37,878 lines |
| Existing test files | 7 |
| Bundled chapter banks | 56; **সবগুলোর `questions` array খালি** |
| Bundled daily questions | **0**; JSON-এ `total_questions: 10` লেখা আছে |
| Sound assets | 31টি WAV; **সবগুলো 0 bytes** |
| Static analysis | **Pass — no issues** |
| Flutter test suite | **92 passed, 2 failed** |
| Web release compilation | **Pass**, `--no-wasm-dry-run` দিয়ে |
| Versioned GitHub Actions workflows | **0** |

### What is already useful

- Provider, models, repositories, services এবং Hive storage-এর আলাদা structure আছে; পুরো app নতুন করে লেখার প্রয়োজন নেই।
- Trilingual `LocalizedText`, fallback, option shuffling, question validation/fingerprinting এবং chapter-set models-এর ভালো unit-test ভিত্তি আছে।
- AI generation-এ validation, bounded retries এবং review-before-append flow রয়েছে; এগুলো বজায় রেখে storage/concurrency ঠিক করা উচিত।
- Optional SDK-এর timeout/fail-soft handling, notification planner এবং consent gating-এর কাজ আছে।
- Lockfile মেনে dependency resolution ও web compilation সফল হয়েছে। Non-owner profile write এবং ordinary-user config write deny হওয়ার security controls-ও local emulator-এ কাজ করেছে।

## Scope and confidence

এই review-তে repository-wide structure/configuration scan এবং authentication, persistence/sync, quiz/rewards, battle, admin/content, notifications, platform setup ও tests-এর গুরুত্বপূর্ণ execution path গভীরভাবে দেখা হয়েছে। এটি প্রতিটি source line-এর formal security audit নয়।

**Evidence labels:**

- **Executed:** command/test/probe চালিয়ে দেখা হয়েছে।
- **Source-confirmed:** উল্লেখিত code path থেকে সমস্যা স্পষ্ট; সংশ্লিষ্ট full UI/device journey চালানো হয়নি।
- **Needs device/staging verification:** platform, deployment বা concurrency আচরণ আরও পরীক্ষা করতে হবে।

> [!IMPORTANT]
> Firestore probes শুধু local emulator-এর `demo-quizbaaz-review` project-এ synthetic data দিয়ে চলেছে। **Live Firebase data, production rules, user accounts, API-key validity, OneSignal delivery বা AdMob configuration পরীক্ষা/পরিবর্তন করা হয়নি।** নিচের rules findings repository-তে committed rules-এর জন্য; production-এ একই rules deployed আছে—এমন দাবি নয়। কোনো secret-এর মান এই report-এ রাখা হয়নি।

Android APK/AAB, iOS archive, real-device Google sign-in, native notification delivery, accessibility/performance profiling এবং deployed composite indexes যাচাই করা হয়নি। Web **compile pass** মানেই browser-এর সব feature কাজ করছে—এমন নয়। Git history বা external `admin_api_key_manager` repository-র পূর্ণ audit এই review-এর অংশ নয়।

## Verification results

Toolchain: **Flutter 3.38.4 / Dart 3.10.3**, Linux workspace। এই version committed lockfile-এর minimum toolchain-এর সঙ্গে মেলে।

| Check | ফলাফল | কী বোঝায় / সীমা |
|---|---|---|
| `flutter pub get --enforce-lockfile` | Exit 0 | Existing lockfile মেনে dependencies resolve হয়েছে; dependency upgrade করা হয়নি |
| `flutter analyze --no-pub` | Exit 0; no issues | Analyzer পরিষ্কার; business logic/security correctness প্রমাণ করে না |
| `flutter test --no-pub --reporter expanded` | Exit 1; **+92 / -2** | `test/widget_test.dart`-এর দুটো widget test failed |
| Startup widget test আলাদাভাবে | Exit 1 | Notification/consent bootstrap-এর pending 5-second timers পাওয়া গেছে |
| `python3 tool/validate_questions.py --strict` | Exit 0 | **0 chapter questions + 0 daily questions** নিয়েও validator pass করেছে |
| `python3 tool/verify_l10n.py` | Exit 0 | Known string accessors/const/bracket checks pass; raw English literals বা সব UI text-এর translation যাচাই নয় |
| `flutter build web --no-pub --no-wasm-dry-run` | Exit 0 | Release JS web output তৈরি হয়েছে; WASM compatibility dry-run বাদ দেওয়া হয়েছে |
| Local Firestore emulator probes | Completed | 13 authorization observations: 3 over-permissive writes, 5 feature-operation denials, 5 expected denials; আরও 1 data-shape probe |
| Fresh `UserModel` inventory mutation | `UnsupportedError` reproduced | নতুন player-এর inventory map immutable |
| Asset inventory | Completed | 56 empty banks; 31 empty WAVs; assets প্রায় 18.5 MiB |
| Privacy/terms public URLs | HTTP 200 | শুধু link reachability; policy-content/compliance audit নয় |

**প্রথম web-build attempt:** default WASM dry-run ও compilation একসঙ্গে চলার সময় 2 GiB workspace-এ memory pressure হয়; সেই attempt বন্ধ করা হয়। পরে শুধু JS release build উপরের flag দিয়ে সফল হয়। প্রথম interrupted attempt-কে source compilation defect হিসেবে ধরা হয়নি।

### The two failing widget tests

1. **`daily quiz loading card shows the 3D intro`** — `[core/no-app]`। Stack: `QuizProvider → QuizRepository → QuestionBankService → FirebaseFirestore.instance`। Firebase ছাড়া optional/offline path-ই constructor-এ ভেঙে যাচ্ছে।
2. **`QuizBaazApp builds without crashing`** — full-suite run-এ আগের failed provider-এর disposal থেকে `Null`/`QuizProvider` type error দেখা যায়। Test-টি আলাদা করেও fails: `NotificationService.bootstrap` ও `ConsentService._requestConsentInfoUpdate`-এর pending timers। এটিকে শুধু প্রথম test-এর cascading error বলে বাদ দেওয়া যাবে না।

প্রাসঙ্গিক code: [`test/widget_test.dart:L24-L63`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/test/widget_test.dart#L24-L63), [`lib/data/services/question_bank_service.dart:L39-L43`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/question_bank_service.dart#L39-L43), [`lib/presentation/screens/dashboard/dashboard_screen.dart:L54-L76`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/dashboard/dashboard_screen.dart#L54-L76)।

## Priority register

**P0:** দ্রুত নিরাপত্তা/launch blocker হিসেবে সমাধান। **P1:** সংশ্লিষ্ট feature release করার আগে correctness/reliability ঠিক করা। **P2:** hardening, maintainability ও polish। এগুলো project priorities, CVSS scores নয়।

| ID | Priority | কাজের জায়গা | প্রধান কাজ |
|---|---|---|---|
| [R01](#r01) | P0 | Upload security | Committed ImgBB key rotate; authenticated upload boundary |
| [R02](#r02) | P0 | Roles, wallet, competitive integrity | Server authority ও field/state-level rules |
| [R03](#r03) | P0 | Firestore contract | Missing collection/admin permissions নিরাপদভাবে ঠিক করা |
| [R04](#r04) | P1 | Profile sign-in | Firebase UID বাধ্যতামূলক; link operation await করা |
| [R05](#r05) | P1 | Logout/account switching | Auth, Hive, providers ও account metadata একসঙ্গে isolate করা |
| [R06](#r06) | P1 | Offline/bootstrap | Firebase-free constructors এবং testable optional services |
| [R07](#r07) | P1 | Learning content | বাস্তব offline bank ও empty-content release gate |
| [R08](#r08) | P1 | Chapter practice | Retry/practice-এ reward/stat/consumption বন্ধ করা |
| [R09](#r09) | P1 | Quiz lifecycle/lifelines | Correct elapsed time, single transition, timer cancellation |
| [R10](#r10) | P1 | Online challenge screen | Accepted opponent-কে battle-এ পাঠানো; missing route ঠিক করা |
| [R11](#r11) | P1 | Live battle persistence | Answer map shape, unique match IDs, room startup/claim protocol |
| [R12](#r12) | P1 | Daily competition | Published daily question packet ও নির্দিষ্ট timezone |
| [R13](#r13) | P1 | Economy sync | Consumable balance-এর `max()` merge বাদ দেওয়া |
| [R14](#r14) | P1 | Offline outbox | Guest/old-account/denied operation যেন queue আটকে না রাখে |
| [R15](#r15) | P1 | Account deletion | Re-auth আগে; reliable backend cleanup ও truthful result |
| [R16](#r16) | P1 | Shop/new player | Mutable inventory; atomic purchase state |
| [R17](#r17) | P1 | Battle queries/indexes | Scoped queries ও versioned composite indexes |
| [R18](#r18) | P1, target-dependent | Web/iOS | Platform-specific Firebase/auth/image upload setup |
| [R19](#r19) | P1, release gate | Android/store release | Release signing, platform ad config ও release checklist |
| [R20](#r20) | P2 | QA/CI | Required automated checks ও integration coverage |
| [R21](#r21) | P2 | Admin/content lifecycle | Concurrent append, cache invalidation ও stable set identity |
| [R22](#r22) | P2 | Localisation/accessibility | Learner-facing strings, semantics, large-text/device checks |
| [R23](#r23) | P2 | Assets/performance | Empty sounds replace; image/font budgets ও profiling |
| [R24](#r24) | P2 | Documentation/toolchain | Implemented বনাম planned features; accurate setup/licensing |

## Detailed findings

<a id="r01"></a>
### R01 · P0 — Upload credential client source-এ committed

**Evidence — Source-confirmed:** [`lib/data/services/imgbb_service.dart:L11-L13`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/imgbb_service.dart#L11-L13), [`lib/data/services/imgbb_service.dart:L49-L58`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/imgbb_service.dart#L49-L58)। Upload API key একটি literal constant; request URL-এ ব্যবহৃত হচ্ছে।

**Impact:** Public source বা distributed app থেকে credential পাওয়া সম্ভব। Key সক্রিয় কি না পরীক্ষা করা হয়নি; exposed ধরে owner-এর provider console থেকে rotate/revoke করা উচিত। শুধু `.env`, `--dart-define` বা obfuscation দিয়ে mobile/web client-এর credential গোপন রাখা যায় না।

**করণীয়:** Authenticated backend/proxy বা appropriately secured storage upload flow; server-held secret, rate/size/type limits এবং প্রয়োজনমতো App Check। Current source ও release artifacts থেকে key সরানোর পরে history cleanup প্রয়োজন কি না owner-এর সঙ্গে সিদ্ধান্ত নিতে হবে—এই review-তে history rewrite/credential revoke করা হয়নি।

**Done when:** Fresh builds-এ usable upload secret নেই; revoked old key ব্যবহারযোগ্য নয়; unauthenticated upload rejected। Firebase client API key/OneSignal App ID-কে এই private upload credential-এর সঙ্গে একভাবে classify করা যাবে না।

<a id="r02"></a>
### R02 · P0 — Sensitive state-এর authority এখনো client-এর হাতে

**Evidence — Executed + source:** [`firestore.rules:L18-L30`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/firestore.rules#L18-L30), [`firestore.rules:L46-L94`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/firestore.rules#L46-L94), [`lib/data/models/user_model.dart:L111-L149`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/models/user_model.dart#L111-L149), [`lib/data/providers/user_provider.dart:L98-L99`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L98-L99)।

Local emulator-এ owner নিজের `is_admin`, `coins` ও `inventory` বদলাতে পেরেছে; room participant opponent-এর score/winner বদলাতে পেরেছে; challenge sender নিজের challenge `accepted` করতে পেরেছে। Leaderboard rules-ও owner document-এর fields/score bounds/attempt transition সীমাবদ্ধ করে না।

**গুরুত্বপূর্ণ সীমা:** `is_admin` বদলালে client-side admin visibility বিশ্বাসযোগ্য থাকে না; তবে current unmatched admin collections deny হওয়ার কারণে এটি দিয়ে backend-এর সব admin operation পাওয়া যায়—এমন দাবি নয়। R03 ঠিক করতে গিয়ে editable profile flag-কে security authority বানালে ঝুঁকি বাড়বে।

**করণীয়:** Trusted custom claims বা server-controlled role documents; profile editable-field allowlist; server-calculated score/reward/wallet ledger; participant identity immutability, legal challenge transitions এবং opponent-field write prohibition। Competitive answers/results/reward claims-এ idempotency ও trusted deadlines লাগবে।

**Done when:** Emulator negative tests sensitive writes deny করে; valid profile edits/answer submissions কাজ করে; modified client arbitrary rank/reward/admin state প্রকাশ করতে পারে না।

<a id="r03"></a>
### R03 · P0 — Versioned Firestore rules shipped features-এর সঙ্গে মেলে না

**Evidence — Executed + source:** [`firestore.rules:L1-L117`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/firestore.rules#L1-L117), [`lib/data/services/question_bank_service.dart:L33-L68`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/question_bank_service.dart#L33-L68), [`lib/data/services/chapter_catalog_service.dart:L20-L37`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/chapter_catalog_service.dart#L20-L37), [`lib/data/services/firestore_service.dart:L308-L370`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/firestore_service.dart#L308-L370)।

Rules-এ `question_banks`, `question_categories`, `shop_items`, `avatars`, `admin_audit_logs`, `users/{uid}/quiz_history` এবং `users/{uid}/purchase_history`-এর প্রয়োজনীয় matches নেই। Parent user-document rule subcollection-এ automatically প্রযোজ্য হয় না। `config`/`champions` write-ও সব client-এর জন্য false; আলাদা deployed trusted backend এই repo থেকে নিশ্চিত করা যায়নি।

Local emulator-এ signed-in catalogue/shop reads, own quiz/purchase history writes এবং synthetic admin-claim question write deny হয়েছে। অর্থাৎ graceful empty-state/queued writes-এর আড়ালে feature failure লুকাতে পারে।

**করণীয়:** Collection × actor × operation contract লিখে rules তৈরি; admin custom claims/privileged backend, guest read policy ও owner history policy স্পষ্ট করা। **Blanket `allow read, write: if true` দিয়ে “fix” নয়।**

**Done when:** Guest/student/admin-এর positive ও negative emulator test matrix pass; rules version এবং staging deployment একই; audit logging ও legitimate admin CRUD কাজ করে।

<a id="r04"></a>
### R04 · P1 — Profile Google sign-in email-কে user ID বানাচ্ছে

**Evidence — Source-confirmed, rule behavior executed:** [`lib/presentation/screens/profile/profile_screen.dart:L1465-L1485`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/profile/profile_screen.dart#L1465-L1485), [`lib/data/providers/user_provider.dart:L960-L993`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L960-L993), [`lib/presentation/screens/quiz_result/quiz_result_screen.dart:L304-L309`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/quiz_result/quiz_result_screen.dart#L304-L309)।

Profile screen `linkGoogleAccount()`-এ `uid` পাঠায় না এবং Future-টি await-ও করে না। Provider তখন `userId: uid ?? email` নেয়। Result screen-এর অন্য sign-in path-এ কিন্তু `uid: user.uid` আছে। `/users/{uid}` ownership rule Firebase Auth UID আশা করে, email নয়; synthetic UID/email mismatch write emulator-এ deny হয়েছে।

**করণীয়:** একটি shared sign-in/link use case; non-null Firebase UID required; migration strategy দিয়ে পুরোনো email-keyed local/remote references সামলানো; link/sync result await করে success/error দেখানো।

**Done when:** Profile ও result—দুই entry point একই UID/profile ব্যবহার করে; sign-in success মানে অন্তত identity linking সফল; denied sync চুপচাপ success নয়।

<a id="r05"></a>
### R05 · P1 — Sign-out এবং account switching-এ local identity বিচ্ছিন্ন হচ্ছে না

**Evidence — Source-confirmed:** [`lib/presentation/screens/profile/profile_screen.dart:L410-L416`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/profile/profile_screen.dart#L410-L416), [`lib/presentation/screens/profile/profile_screen.dart:L640-L665`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/profile/profile_screen.dart#L640-L665), [`lib/data/providers/auth_provider.dart:L112-L126`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/auth_provider.dart#L112-L126), [`lib/data/providers/user_provider.dart:L960-L1025`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L960-L1025), [`lib/data/services/hive_service.dart:L563-L575`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/hive_service.dart#L563-L575)।

Normal sign-out শুধু `AuthProvider.signOut()` করে; `UserProvider.signOutLocal()` ডাকে না। ফলে পুরোনো profile, wallet, admin flag এবং cached provider state থাকে। পরের account link-এ আগের local progress/role অনিচ্ছায় carry হতে পারে। উপরন্তু `clearAll()` account-related meta keys রাখে; `daily_best_score_*`, `claimed_daily_rank_*`, `winning_streak`, `last_daily_reward_date` UID-scoped নয়।

**করণীয়:** Coordinated session/logout service; authenticated UID-এর পরিবর্তন observe; provider/notification identity reset; device preferences/schema keys ও per-account gameplay metadata আলাদা namespace। Unsent writes discard করার আগে explicit policy/confirmation লাগবে।

**Done when:** Account A → logout → account B-তে A-এর rewards, rank, role বা notification identity দেখা/ব্যবহার যায় না; A-তে ফিরে expected data restore হয়।

<a id="r06"></a>
### R06 · P1 — Firebase “optional” হলেও constructors Firebase ছাড়া তৈরি হয় না

**Evidence — Executed:** [`lib/main.dart:L47-L54`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/main.dart#L47-L54), [`lib/data/providers/quiz_provider.dart:L19-L23`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L19-L23), [`lib/data/repositories/quiz_repository.dart:L35-L43`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/repositories/quiz_repository.dart#L35-L43), [`lib/data/services/question_bank_service.dart:L39-L43`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/question_bank_service.dart#L39-L43), [`lib/data/services/chapter_catalog_service.dart:L23-L27`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/chapter_catalog_service.dart#L23-L27)।

Firebase initialization failure catch করার পরে app চালানোর চেষ্টা হয়, কিন্তু `QuizProvider` তৈরির সময় eager `FirebaseFirestore.instance` access `[core/no-app]` throw করে। Loading-card widget test-এ এটি সরাসরি reproduced হয়েছে।

**করণীয়:** Injected repository interfaces; lazy/nullable remote service; Firebase-unavailable path-এ asset/Hive-only implementation। Optional notification/consent services-কে test doubles দিয়ে replace করা এবং timers/async lifecycle সঠিকভাবে settle/dispose করা।

**Done when:** Firebase deliberately disabled/failed থাকলেও app, chapter list ও bundled quiz চলে; existing দুই widget test pass; unresolved bootstrap timers থাকে না।

<a id="r07"></a>
### R07 · P1 — Offline-first promise-এর জন্য বাস্তব bundled content নেই

**Evidence — Executed:** 56টি chapter JSON এবং daily JSON scan-এ প্রশ্ন সংখ্যা 0। উদাহরণ: [`assets/data/questions/class10_math_ch1.json:L1-L10`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/assets/data/questions/class10_math_ch1.json#L1-L10), [`assets/data/daily_quiz.json:L1-L9`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/assets/data/daily_quiz.json#L1-L9), [`tool/validate_questions.py:L178-L244`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/tool/validate_questions.py#L178-L244)।

Strict validator এই empty dataset-কে valid বলেছে। Daily JSON-এর advertised `total_questions: 10`-ও actual empty array-এর সঙ্গে মেলে না। Remote database-এ প্রশ্ন আছে কি না পরীক্ষা করা হয়নি; fresh offline install-এ অবশ্য remote data দিয়ে এই gap পূরণ হবে না।

**করণীয়:** Reviewed EN/BN/HI starter bank ship করা; minimum question count, declared count এবং required release chapters-এর completeness CI-তে gate করা। Firestore → reviewed JSON export pipeline তৈরি করা; draft/scaffold banks আলাদা চিহ্নিত করা।

**Done when:** Fresh install + airplane mode-এ advertised playable chapters/daily fallback কাজ করে; all-empty production bank validation fail করে।

<a id="r08"></a>
### R08 · P1 — Practice/retry mode documented no-reward contract মানছে না

**Evidence — Source-confirmed:** [`lib/presentation/screens/chapter_quiz/chapter_sets_screen.dart:L338-L350`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/chapter_quiz/chapter_sets_screen.dart#L338-L350), [`lib/presentation/screens/chapter_quiz/chapter_sets_screen.dart:L502-L510`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/chapter_quiz/chapter_sets_screen.dart#L502-L510), [`lib/data/providers/quiz_provider.dart:L200-L222`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L200-L222), [`lib/data/providers/quiz_provider.dart:L498-L598`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L498-L598)।

Retry actions-এও `practice: false` পাঠানো হচ্ছে। Provider-এ `_isPractice` থাকলেও finish/reward path সেটি দিয়ে coins, gems, XP, stats, history বা booster consumption আটকায় না। ফলে completed set replay reward দিতে এবং consumables খরচ করতে পারে—documented practice behavior-এর বিপরীত।

**করণীয়:** Completed-set replay-এ practice mode; reward/stat/history/consumption-এর shared guard; allowed practice progress update আলাদা রাখা। Reward eligibility UI boolean-এর উপরেই নির্ভর না করে trusted progress/attempt identity দিয়ে যাচাই করা।

**Done when:** Same completed set 3 বার replay-এ wallet/XP/stats/history/consumables অপরিবর্তিত; first legitimate completion একবারই credit হয়।

<a id="r09"></a>
### R09 · P1 — Lifeline ও delayed transition-এ timing/state bugs

**Evidence — Source-confirmed:** [`lib/data/providers/quiz_provider.dart:L363-L475`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L363-L475), [`lib/data/providers/quiz_provider.dart:L478-L515`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L478-L515), [`lib/data/providers/quiz_provider.dart:L644-L687`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L644-L687), [`lib/data/providers/quiz_provider.dart:L776-L781`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L776-L781)।

- **Freeze:** remaining time-এ 10 যোগ হলেও elapsed time হিসাব `questionTimeSec - remaining`; freeze-এর পর দ্রুত answer/skip করলে negative duration হতে পারে, যা tie-break/history বিকৃত করে।
- **Wrong-answer extra life:** timer cancel হওয়ার পরে early return; timer restart নেই। **Timeout extra life:** remaining `5` সেট করেও `_startTimer()` full configured duration বসায়।
- **Skip race:** `_isAnswerSubmitted` lock হয় না; 500 ms-এর মধ্যে answer দিলে skip ও answer দুই delayed `nextQuestion()` জমতে পারে। `nextQuestion()` completed-state guard-ও রাখে না।
- **Stale callbacks:** `Future.delayed(..., nextQuestion)` cancellable নয়; reset/dispose শুধু periodic timer cancel করে। Old quiz callback নতুন run-এ ঢোকার ঝুঁকি থাকে।

**করণীয়:** Explicit quiz state machine, monotonic elapsed clock, separate deadline/extension, run-generation token/cancellable timers, single completion/reward transition; background/resume policy নির্ধারণ।

**Done when:** Freeze time কখনো negative নয়; extra life ঠিক নির্ধারিত সময় দেয়; rapid skip+tap, exit/restart এবং duplicate callbacks কোনো question/reward double-advance করে না। Fake-clock tests যোগ করতে হবে।

<a id="r10"></a>
### R10 · P1 — Online challenge accept থেকে intended battle শুরু হচ্ছে না

**Evidence — Source-confirmed:** [`lib/presentation/screens/battle/online_battle_screen.dart:L238-L266`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/battle/online_battle_screen.dart#L238-L266), [`lib/main.dart:L124-L143`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/main.dart#L124-L143)।

`_startBattleWithOpponent()`-এ provider integration এখনো TODO; opponent তথ্য গ্রহণ করেও ব্যবহার করা হচ্ছে না। শেষে `pushNamed('/battle')`, অথচ `MaterialApp`-এ ওই named route বা `onGenerateRoute` নেই। Challenge accepted হওয়া আর সেই player-এর সঙ্গে battle শুরু হওয়া বর্তমানে আলাদা, অসম্পূর্ণ ধাপ।

**করণীয়:** Accepted challenge ID + opponent UID দিয়ে একটি shared battle-start use case; route registration বা typed `MaterialPageRoute`; failed start-এ presence/availability rollback।

**Done when:** দুই authenticated test user-এর challenge → accept → একই unique room-এ একই opponent; unknown-route error বা bot/random opponent fallback নয়।

<a id="r11"></a>
### R11 · P1 — Live battle answer storage ও match lifecycle অসঙ্গত

**Evidence — Executed data-shape probe + source:** [`lib/data/providers/battle_provider.dart:L1291-L1318`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/battle_provider.dart#L1291-L1318), [`lib/data/services/battle_room_service.dart:L189-L196`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/battle_room_service.dart#L189-L196), [`lib/data/models/battle_room.dart:L110-L125`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/models/battle_room.dart#L110-L125), [`lib/data/services/battle_room_service.dart:L109-L155`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/battle_room_service.dart#L109-L155), [`lib/data/providers/battle_provider.dart:L680-L725`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/battle_provider.dart#L680-L725), [`lib/data/providers/battle_provider.dart:L1247-L1255`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/battle_provider.dart#L1247-L1255)।

1. Answer writer `'answers.$index'`-কে nested `set(..., merge: true)` map-এ দেয়। Emulator probe-এ literal **`answers.0`** field হয়েছে, expected `answers['0']` নয়। Reader nested `answers` map দেখে—opponent answer/both-answered synchronization তাই ভাঙতে পারে।
2. Room ID শুধু sorted user pair থেকে তৈরি; rematch-এ একই ID। অথচ reward guard processed room ID মনে রাখে—same-pair নতুন match ভুল করে already-processed হতে পারে।
3. Listener room create-এর আগেই attach হয়; initial missing snapshot-কে `_onRoomUpdate(null)` forfeit হিসেবে ধরে। এটি room-start race, intentional departure নয়।
4. Queue selection + room creation atomic opponent reservation নয়; multi-player arrival/rematch-এর জন্য explicit claim/handshake দরকার।

**করণীয়:** Proper nested answer map অথবা supported field-path update; unique match/session ID; waiting/created/ready/active/finished states; missing-before-created বনাম deleted-after-active আলাদা; atomic matching/claim এবং backend award receipt।

**Done when:** Emulator serialization test round-trip pass; 2-player delayed creation, 3+ player queue, consecutive rematches ও reconnect tests-এ premature forfeit/duplicate room/reward suppression নেই। Full multi-device journey এখনো staging-এ যাচাই করতে হবে।

<a id="r12"></a>
### R12 · P1 — Date-seeded shuffle সব player-কে একই daily quiz নিশ্চিত করে না

**Evidence — Source-confirmed:** [`lib/data/services/daily_quiz_generator.dart:L30-L104`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/daily_quiz_generator.dart#L30-L104), [`lib/data/services/daily_quiz_generator.dart:L110-L117`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/daily_quiz_generator.dart#L110-L117), [`lib/data/providers/user_provider.dart:L546-L577`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L546-L577), [`lib/data/services/sync_service.dart:L313-L351`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/sync_service.dart#L313-L351)।

Daily set স্থানীয় `DateTime.now()` এবং সেই device-এর available asset/remote pool থেকে তৈরি। একই random seed থাকলেও pool/order/cache version/network availability বা timezone আলাদা হলে set আলাদা হয়; `min(10, pool.length)` কম প্রশ্নের competitive run-ও দিতে পারে। Generation প্রতিটি chapter-এর remote bank sequentially পড়ে—content বাড়লে read/latency cost বাড়বে।

Leaderboard cache `leaderboard_today` date-scoped নয়; নতুন দিনের empty/failing response-এ পুরোনো cache ফিরে আসতে পারে। Winner matching-এ UID-এর পাশাপাশি mutable/non-unique username ব্যবহার করাও reward identity-এর জন্য অনিরাপদ।

**করণীয়:** নির্দিষ্ট competition timezone-এ backend-published immutable daily packet: date, version, question IDs, count, deadline এবং scoring contract। Practice fallback ranked submission থেকে পৃথক; date-scoped ranking cache; reward matching UID-only।

**Done when:** Same date/version-এর online/offline-cached দুই device একই approved questions পায়; incomplete packet ranked নয়; midnight/timezone rollover এবং duplicate usernames-এর test pass।

<a id="r13"></a>
### R13 · P1 — `max()` merge খরচ হয়ে যাওয়া wallet/items ফিরিয়ে দিতে পারে

**Evidence — Source-confirmed:** [`lib/data/services/sync_service.dart:L273-L289`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/sync_service.dart#L273-L289), [`lib/data/providers/user_provider.dart:L346-L377`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L346-L377)।

Coins, gems এবং inventory count local/remote-এর বড় মান ধরে merge হয়। এগুলো cumulative counters নয়: device A-তে balance 100 → 60 খরচ হলে stale device B-এর 100 আবার জিততে পারে। Admin role-ও OR-merge হওয়ায় revoked local role সহজে সরে না। Remote XP/level/profile restoration-ও আলাদা পরীক্ষা প্রয়োজন; বর্তমান merge এগুলো explicitly reconcile করে না।

**করণীয়:** Server-authoritative wallet/entitlement ledger; transaction/version + idempotent operation IDs; local pending projections। XP/high-water statistics ও spendable balances-এর merge policy আলাদা; role কখনো local OR-merge নয়।

**Done when:** Two-device earn/spend/consume/offline/reconnect scenario-তে spent funds/items ফিরে আসে না; failed spend rollback হয়; revoked role কার্যকর হয়।

<a id="r14"></a>
### R14 · P1 — একটি invalid pending operation পুরো outbox আটকে রাখতে পারে

**Evidence — Source-confirmed:** [`lib/data/services/sync_service.dart:L24-L51`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/sync_service.dart#L24-L51), [`lib/data/services/sync_service.dart:L156-L228`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/sync_service.dart#L156-L228), [`lib/data/providers/user_provider.dart:L827-L839`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L827-L839)।

`isOnline` শুধু Firebase initialized কি না দেখে। `pushStats()` guest/local ID বাদ দেয় না; failed writes queued হয়। Replay প্রথম failure-এ `break` করে—permission-denied, stale account UID বা missing-rule operation-ও “still offline” হিসেবে ধরা হয়। ফলে একটি unretryable operation-এর পেছনে অন্য valid operation আটকে থাকতে পারে; concurrent drains-এর guard-ও দরকার।

**করণীয়:** UID-scoped authenticated outbox; guest operation policy; retryable বনাম permanent error classification; bounded backoff/dead-letter queue; single-flight drain ও operation idempotency; user-visible sync status।

**Done when:** Guest → sign-in এবং denied-op → valid-op পরীক্ষায় legitimate sync এগোয়; পুরোনো account-এর operation অন্য account-এ replay হয় না; offline writes restart/reconnect-এ হারায় না।

<a id="r15"></a>
### R15 · P1 — Account deletion cancel/failure হলেও data loss বা residual data হতে পারে

**Evidence — Source-confirmed:** [`lib/data/services/account_deletion_service.dart:L42-L78`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/account_deletion_service.dart#L42-L78), [`lib/data/services/account_deletion_service.dart:L84-L146`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/account_deletion_service.dart#L84-L146), [`lib/presentation/screens/profile/profile_screen.dart:L817-L829`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/profile/profile_screen.dart#L817-L829)।

Remote data removal recent-login check/re-auth-এর **আগে** চলে। Re-auth cancel হলেও কিছু data ইতিমধ্যে চলে যেতে পারে। অন্যদিকে collection failures swallowed হওয়ার পর Auth delete সফল হলে overall success ফেরে—সব remote data মুছেছে এমন নিশ্চয়তা নেই। Caller status canceled/failed হলেও local profile মুছে sign-out করে। Leaderboard `collectionGroup('scores')` query-তে bare UID `documentId` filter-ও full-path semantics/authorization অনুযায়ী যাচাই ও সংশোধন দরকার।

**করণীয়:** Re-auth/confirmation আগে; sync pause/tombstone; idempotent trusted cleanup job, retryable progress/status, explicit retention policy এবং external avatar cleanup; local wipe/status truthful করা।

**Done when:** Re-auth cancel-এ account/local data অক্ষত; successful completion-এ documented cleanup সম্পূর্ণ বা clearly tracked; background sync deleted profile ফিরিয়ে আনে না।

<a id="r16"></a>
### R16 · P1 — Fresh player-এর inventory immutable

**Evidence — Executed:** [`lib/data/models/user_model.dart:L33-L51`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/models/user_model.dart#L33-L51), [`lib/data/models/user_model.dart:L161-L176`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/models/user_model.dart#L161-L176), [`lib/data/providers/user_provider.dart:L354-L376`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/user_provider.dart#L354-L376)।

`UserModel.newPlayer()` `inventory: const {}` দেয়; constructor mutable copy করে না। Original model import করে inventory item যোগ করার local Dart probe-এ **`Unsupported operation: Cannot modify unmodifiable map`** reproduced হয়েছে। Shop purchase balance কাটার পরে inventory mutate করে—fresh-session purchase আংশিক in-memory state change রেখে fail করতে পারে।

**করণীয়:** Constructor boundary-তে owned mutable copy অথবা immutable model/update API; debit + inventory + receipt একটি atomic state transition।

**Done when:** Fresh install → earned balance → first purchase/claim/revive test pass; কোনো partial debit বা unmodifiable-map exception নয়।

<a id="r17"></a>
### R17 · P1 — Battle query/index contract অসম্পূর্ণ

**Evidence — Source + emulator query denial:** [`lib/data/services/battle_room_service.dart:L78-L103`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/battle_room_service.dart#L78-L103), [`lib/data/services/challenge_service.dart:L142-L180`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/challenge_service.dart#L142-L180), [`lib/data/services/challenge_service.dart:L194-L260`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/challenge_service.dart#L194-L260), [`firestore.indexes.json:L1-L32`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/firestore.indexes.json#L1-L32)।

Versioned indexes-এ queue-এর difficulty + created-at এবং incoming/outgoing challenge-এর participant/status + created-at query shapes নেই। এগুলো deployed আছে কি না পরীক্ষা করা হয়নি; emulator result দিয়েও production composite-index availability প্রমাণ হয় না।

`_hasPendingChallenge`, cleanup ও expire helpers broader collection query করে পরে client-side UID filter করে। Participant-only rules-এর সঙ্গে এভাবে query চলে না; unscoped pending query local emulator-এ denied হয়েছে। Security rules filters নয়।

**করণীয়:** Participant-constrained queries, exact query-index definitions version করা; global expiry/cleanup trusted backend বা TTL policy-তে নেওয়া; permission/index failure-কে “opponent নেই” বলে লুকিয়ে না রাখা।

**Done when:** Staging query matrix index errors ছাড়া চলে; unrelated users-এর challenges readable নয়; duplicate prevention ও expiry কাজ করে।

<a id="r18"></a>
### R18 · P1 — Web/iOS support compilation-এর বাইরে অসম্পূর্ণ

**Evidence — Source-confirmed:** [`lib/data/services/firebase_options.dart:L1-L21`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/firebase_options.dart#L1-L21), [`lib/data/providers/auth_provider.dart:L52-L84`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/auth_provider.dart#L52-L84), [`lib/presentation/screens/admin/avatar_manager_screen.dart:L354-L360`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/admin/avatar_manager_screen.dart#L354-L360), [`lib/presentation/screens/admin/shop_manager_screen.dart:L385-L405`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/admin/shop_manager_screen.dart#L385-L405), [`ios/Runner/Info.plist:L1-L60`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/ios/Runner/Info.plist#L1-L60)।

`currentPlatform` সব platform-এ Android Firebase options ফেরায়। Google sign-in native `authenticate()` flow-ই ব্যবহার করে; web-specific supported flow/client configuration নেই। Admin image upload `File(image.path)`/`Image.file` ব্যবহার করে, web byte-based path নয়। iOS configuration-এ Google callback/photo-library permission setup অসম্পূর্ণ; প্রয়োজনীয় permission target features অনুযায়ী যাচাই করতে হবে।

**করণীয়:** Supported-platform matrix; `flutterfire configure` দিয়ে per-platform options; correct Google OAuth web/iOS flow; `XFile.readAsBytes()`/memory preview/conditional upload; required plist/URL-scheme/APNs setup।

**Done when:** Android, selected web admin target এবং supported iOS device-এ sign-in + image upload + core navigation smoke tests pass। Android-only release হলে অন্য targets-কে explicitly unsupported বলা যেতে পারে।

<a id="r19"></a>
### R19 · P1 — Store release configuration এখনো development-oriented

**Evidence — Source-confirmed:** [`android/app/build.gradle.kts:L14-L40`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/android/app/build.gradle.kts#L14-L40), [`lib/core/constants/ad_config.dart:L21-L33`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/core/constants/ad_config.dart#L21-L33), [`android/app/src/main/AndroidManifest.xml:L14-L19`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/android/app/src/main/AndroidManifest.xml#L14-L19), [`ios/Runner/Info.plist:L52-L58`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/ios/Runner/Info.plist#L52-L58)।

Android `release` এখনো debug signing key ব্যবহার করে। AdMob identifiers official test IDs; current ad-unit constants Android-specific, iOS selection নেই। Release configuration, native signing/build ও live ad delivery এই workspace-এ যাচাই হয়নি।

**করণীয়:** CI/release-only signing configuration এবং protected secret storage; production/test flavors, correct per-platform ad IDs, versioning/rollback checklist; real-device OAuth signing fingerprints। Class-10 audience-এর জন্য বয়স-উপযোগী consent/ad-targeting এবং store declarations আলাদাভাবে যাচাই করা প্রয়োজন—UMP থাকলেই সব privacy/store obligations পূরণ হয়েছে ধরে নেওয়া যাবে না।

**Done when:** Properly signed AAB/internal-test release; no debug signing; intended ad/consent behavior ও account deletion পরীক্ষিত। কোনো signing secret repository-তে commit নয়।

<a id="r20"></a>
### R20 · P2 — CI gate ও business-flow integration coverage নেই

**Evidence — Executed inventory + tests:** Snapshot-এ `.github/workflows/` tracked file নেই; 7টি test file-এ +92/-2 result। [`test/widget_test.dart:L167-L177`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/test/widget_test.dart#L167-L177)-এর “queued and can be drained” test local enqueue/remove পরীক্ষা করে, real `SyncService.drainPending()` replay নয়। [`test/question_bank_test.dart:L405-L488`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/test/question_bank_test.dart#L405-L488)-এর append checks in-memory behavior পরীক্ষা করে, simultaneous Firestore writers নয়।

**করণীয়:** Pinned Flutter CI: lockfile enforcement → analyzer → existing tests → strict content/l10n checks → emulator rules tests → supported target builds। Auth/account switching, practice rewards, timers, outbox, two-client battle, purchases এবং deletion-এর integration/negative tests যোগ করা। Metrics হিসেবে শুধু test count নয়, critical-flow coverage ব্যবহার করা।

**Done when:** Clean clone-এ repeatable green pipeline; failing tests/empty release bank/security regressions merge বা release আটকে দেয়।

<a id="r21"></a>
### R21 · P2 — Admin append/cache/progress lifecycle শক্ত করা দরকার

**Evidence — Source-confirmed:** [`lib/data/services/question_bank_service.dart:L145-L219`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/question_bank_service.dart#L145-L219), [`lib/presentation/screens/admin/question_manager_screen.dart:L579-L598`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/admin/question_manager_screen.dart#L579-L598), [`lib/data/repositories/quiz_repository.dart:L194-L200`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/repositories/quiz_repository.dart#L194-L200), [`lib/data/services/daily_quiz_generator.dart:L48-L54`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/daily_quiz_generator.dart#L48-L54)।

- Max-ID + sequence allocation এবং explicit-ID `set()` single-writer case-এ useful, কিন্তু দুই simultaneous generator একই ID range পেলে overwrite হতে পারে। Counter/audit writes question batches-এর একই atomic boundary-তে নেই।
- Daily invalidation `daily_quiz_questions` সরায়, actual generator cache `daily_quiz_mixed_<date>` নয়। Publish/edit এবং ranked-day freeze-এর policy মিলিয়ে নিতে হবে।
- Positional chapter sets append-এ stable, কিন্তু delete/reorder/correction-এর পরে question-to-set/progress identity আলাদা করে যাচাই দরকার।
- `ADMIN_TODO.md`-এর export, offline parity, reorder UI ও localisation work এখনো backlog হিসেবে ধরতে হবে।

**করণীয়:** Unique/reserved ID allocation, revision-aware writes, stable question/set IDs, publication versions, deliberate tombstone/delete semantics ও single cache-key registry।

**Done when:** Concurrent append-এ আগের প্রশ্ন হারায় না; counts/audits recoverable; edit/undo/cache/old student progress-এর regression tests pass।

<a id="r22"></a>
### R22 · P2 — Trilingual/accessibility completion কাজ বাকি

**Evidence — Source-confirmed:** [`lib/data/providers/quiz_provider.dart:L715-L725`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/quiz_provider.dart#L715-L725), [`lib/presentation/screens/daily_quiz/daily_quiz_screen.dart:L32-L38`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/presentation/screens/daily_quiz/daily_quiz_screen.dart#L32-L38), [`lib/data/providers/auth_provider.dart:L129-L173`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/providers/auth_provider.dart#L129-L173), [`tool/verify_l10n.py:L145-L199`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/tool/verify_l10n.py#L145-L199)।

Learner-facing quiz title, hints ও auth errors-এ raw English আছে। Existing l10n checker এগুলোর translation completeness মাপে না। Admin English-only থাকবে কি না একটি product decision; সেটিকে learner UI-এর language promise থেকে আলাদা করতে হবে।

**করণীয়:** EN/BN/HI learner strings catalog-এ আনা; Hindi/Bangla long-text/200% text scale test; icon-only control labels, screen-reader order, contrast, reduced motion এবং lifecycle/back navigation যাচাই। 340-dp avatar test useful, কিন্তু পুরো app-এর accessibility/performance certification নয়।

**Done when:** Selected user language-এ complete learner journey; large text-এ clipping/essential-control loss নেই; TalkBack/VoiceOver smoke checklist complete।

<a id="r23"></a>
### R23 · P2 — Audio assets placeholder; performance বাজেট দরকার

**Evidence — Executed asset scan + source:** সব 31 WAV 0 bytes। [`lib/data/services/sound_service.dart:L8-L17`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/lib/data/services/sound_service.dart#L8-L17) নিজেও placeholder/fail-soft behavior document করে। `assets/` মোট প্রায় 18.5 MiB; কয়েকটি PNG প্রায় 1.5–2.1 MiB। [`pubspec.yaml:L59-L68`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/pubspec.yaml#L59-L68)-এ assets আছে, offline typography-এর জন্য font bundling স্পষ্ট নয়।

**করণীয়:** Licensed/owned real audio assets ও validity/duration gate; image dimensions/format/compression audit; required font files bundle করা; low-memory Android-এ frame time, memory, startup এবং quiz latency profile করা।

**Done when:** Intentional audible feedback কাজ করে; corrupt/empty assets release gate-এ ধরা পড়ে; measured performance budget পূরণ হয়। Empty sound-কে বর্তমান startup crash বলা হচ্ছে না—service ইতিমধ্যে timeout দিয়ে fail-soft করে।

<a id="r24"></a>
### R24 · P2 — README/toolchain/roadmap actual implementation-এর সঙ্গে sync করা দরকার

**Evidence — Source inventory:** [`README.md:L1-L61`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/README.md#L1-L61), [`pubspec.yaml:L6-L7`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/pubspec.yaml#L6-L7), [`pubspec.yaml:L47-L57`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/pubspec.yaml#L47-L57), [`ADMIN_TODO.md:L74-L92`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/ADMIN_TODO.md#L74-L92), [`AGENTS.md:L260-L267`](https://github.com/Keshab1997/quizbaaz-flutter/blob/5de9fff83cdc74b28a79d68a8f7c60d6ee1490c2/AGENTS.md#L260-L267)।

README-তে shipped offline question bank, competitive/anti-cheat ও completed feature language আছে, কিন্তু empty assets, unfinished challenge flow এবং client-authoritative scoring সেই readiness সমর্থন করে না। Provider app-এর README tech stack-এ “Provider / Riverpod” বলা; MIT badge থাকলেও tracked `LICENSE` নেই। `pubspec.yaml` Dart 3.0 minimum বলে, resolved lockfile-এর requirement Dart ≥3.10.3 / Flutter ≥3.38.4। Git dependency `ref: master`, যদিও current lockfile resolved revision pin করছে।

**করণীয়:** Implemented / experimental / planned feature matrix; tested SDK pin/setup instructions; reviewed dependency tag/commit policy; intended licence owner confirm করে LICENSE/badge consistent করা; AGENTS/roadmap/TODO-র outdated assertions ঠিক করা।

**Done when:** নতুন contributor documented toolchain-এ app/checks চালাতে পারে; README এমন behavior promise করে না যা release snapshot-এ নেই।

## Page-by-page work map

এই table screen coverage map; “দেখা হয়েছে” মানে full native visual QA complete নয়।

| Page / area | আগে কোন কাজ | Finding / verification |
|---|---|---|
| Dashboard / home | Correct per-day ranking cache, account reset, bootstrap timer handling | R05, R06, R12 |
| Daily quiz / loading card | Firebase-free construction, real questions, timing/state machine | R06, R07, R09 |
| Chapter list / sets | Offline question population; correct retry/practice mode | R07, R08, R21 |
| Quiz result / answer review | Single completion, actual granted rewards/history, unified sign-in | R04, R08, R09 |
| Battle arena | Answer serialization, match handshake, unique match/reward identity | R02, R11 |
| Online battle / challenges | Accepted opponent integration, route, scoped queries/indexes | R10, R17 |
| Leaderboard / champions | Trusted submissions, UID-only identity, date/version/timezone | R02, R12 |
| Profile / Google account | UID, await/error path, full account isolation | R04, R05 |
| Avatar selection | First inventory mutation, ownership rules, platform-safe upload | R01, R02, R16, R18 |
| Shop / purchase history | Atomic balance/inventory/receipt; owner history rules | R03, R13, R16 |
| Rewards / gift claims | Trusted award/claim state; account-scoped cache and cleanup | R02, R05, R15 |
| Quiz history | Missing rules; offline/remote merge and reliable outbox | R03, R14 |
| Language / settings | Learner strings, preserved device preferences, large text | R05, R22 |
| Admin dashboard / user manager | Trusted admin boundary and real remote status/errors | R02, R03 |
| Admin chapter/question/AI review | Safe publish, concurrent append, export and cache consistency | R03, R07, R21 |
| Admin shop/avatar managers | Secured uploads, collection permissions, web-compatible image path | R01, R03, R18 |
| Notifications / OneSignal / ads | Mockable lifecycle; real-device permission/deep-link/consent matrix | R06, R18, R19 |
| Native/web build & deployment | Target matrix, signing, CI, release documentation | R18–R24 |

## Recommended execution order

### Phase 1 — Safety and identity

- [ ] R01: owner rotates exposed upload credential; client upload boundary redesigned.
- [ ] R02–R03: define trusted backend/roles, collection rules matrix এবং staging emulator tests।
- [ ] R04–R05: one UID-based account linking/logout/session flow; existing-data migration plan।
- [ ] R15: re-auth cancel/failure যেন destructive না হয়; safe deletion workflow।

**Exit gate:** Security-negative tests pass; normal guest/student/admin operations work; account switching never shares another account's state।

### Phase 2 — Offline learning and economy correctness

- [ ] R06–R07: Firebase-free startup + actual reviewed question content।
- [ ] R08–R09: practice guard এবং deterministic, tested quiz lifecycle।
- [ ] R13–R14, R16: mutable/atomic local state, trusted balance ledger, reliable outbox।
- [ ] R12: daily question publication/timezone contract; ranked বনাম practice distinction।

**Exit gate:** Fresh offline install playable; rewards exactly once; two-device/offline purchase/sync test pass।

### Phase 3 — Real multiplayer

- [ ] R10–R11: challenge entry point → unique shared room → answers → result → rematch।
- [ ] R17: scoped queries, versioned indexes, expiry/cleanup।
- [ ] Latency, disconnect, app background/kill, reconnect ও 3+ concurrent participants-এর tests।

**Exit gate:** দুই real test device-এ full match/rematch; no stale result, premature forfeit, wrong opponent or duplicate reward।

### Phase 4 — Release readiness and polish

- [ ] R18–R19: supported target configuration, signed internal-test artifact, platform smoke checks।
- [ ] R20: CI mandatory; R21–R24: admin hardening, localisation/assets/docs।
- [ ] Accessibility, actual device performance, notification/deep-link এবং privacy/store checklist।

**Exit gate:** CI green + reviewed content + security gates + real-device acceptance evidence; শুধু analyzer/build pass দিয়ে production approval নয়।

## Regression checklist for the next code changes

- [ ] App launches with Firebase unavailable; existing two failing widget tests turn green.
- [ ] Profile/result sign-in use the same Firebase UID; completion/error is awaited.
- [ ] Account A → B never carries A's role, balance, rank, claim flags or notification identity.
- [ ] Fresh install has approved offline questions; zero-question release bank fails validation.
- [ ] Practice replay changes no wallet/XP/history/consumables; eligible completion awards once.
- [ ] Freeze/extra-life/skip timers produce valid elapsed times and single transitions.
- [ ] New user can make a first legitimate purchase without immutable-map/partial-debit errors.
- [ ] Denied/old-account outbox items do not block valid pending work; replay is idempotent.
- [ ] Sensitive role/wallet/score/opponent-state writes are denied to ordinary clients.
- [ ] Battle answer data round-trips; delayed room creation is not a forfeit; rematches get new IDs.
- [ ] Challenge acceptance reaches the intended opponent, using registered navigation and valid queries.
- [ ] Daily packet/version/timezone and ranking cache remain consistent across midnight/devices.
- [ ] Canceling re-auth during account deletion leaves the account/data intact.
- [ ] Chosen native/web targets pass sign-in, upload, notification, consent and accessibility smoke tests.

---

**Bottom line:** প্রথম কাজ নতুন UI নয়—**security/rules + identity**, তারপরে **offline content + quiz/economy correctness**, তারপর **reliable multiplayer**। এই review একটি কাজের roadmap; এখানে তালিকাভুক্ত কোনো bug এই documentation-only change-এ fixed হিসেবে দাবি করা হয়নি।
