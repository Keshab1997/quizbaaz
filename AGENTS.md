# AGENTS.md — QuizBaaz 3D

<!-- flutter-builder:agent-pack:start v1.12.1 -->
## Rule #1 — CI is manual; preflight is your check

This repository runs CI **only when the human dispatches it** (Actions → *Flutter
CI* → Run workflow). Nothing runs on a push. So:

- Work lands on `main` **directly** — no feature branch, no pull request.
- Do **not** wait for a run after pushing. Nothing started; waiting only wastes
  time.
- `tool/preflight.py` is your only automatic check. Run it before every push —
  it is seconds, not minutes, and catches the mistakes that would otherwise
  surface in the next manual CI run.
- Do **not** run `flutter test`, `flutter analyze`, `flutter build`,
  `dart analyze` or `gradlew` locally to "check quickly". The sandbox usually has
  no Flutter SDK, and a local pass would not match CI anyway.
- **When CI does run, it is the source of truth** — read its result before
  calling a batch done. But it runs when the human says so, not on your push.

```bash
python3 tool/preflight.py     # before every push: dead code / unused params / unused imports
python3 tool/agent_loop.py -m "fix(scope): what changed"   # preflight + commit + push, one call
```

## The batch loop — many small changes, one push, one CI run

Small edits are cheap; CI runs are not. So batch them instead of running CI per
change:

1. **Edit** the smallest diff that does one thing.
2. **`python3 tool/preflight.py`** — 1 second, no SDK. Fix what it reports.
3. **Commit and push to `main`.** `python3 tool/agent_loop.py -m "…"` does
   preflight, the secret guard, the commit and the push in one call. Repeat for
   each small change; every commit goes straight to `main`.
4. **Do not wait for CI.** Nothing started. Keep working.
5. **When the batch is ready, tell the human** to run CI once (Actions → *Flutter
   CI* → Run workflow). If a run is already in flight, `python3 tool/ci_watch.py`
   prints the conclusion of every workflow plus the interesting lines of the
   failed ones.

Rules of thumb: a CI run per push wastes the most time; push freely, run CI once
per batch. When a red run does arrive, read the log before editing — guessing at
a red build doubles the rounds.

### The same loop as one command

`tool/agent_loop.py` performs preflight, the secret guard, the commit and the
push in a single call:

```bash
python3 tool/agent_loop.py -m "fix(profile): guard a null avatar"
python3 tool/agent_loop.py -m "fix(profile): drop the unused import" --amend
python3 tool/agent_loop.py -m "chore: wip" --no-push     # commit without pushing
python3 tool/agent_loop.py -m "…" --watch                # wait, only if a run is in flight
```

It refuses, before touching the repository, when

- a staged file looks like a credential (`.env`, `*.jks`, `*.keystore`, `*.pem`,
  `key.properties`, `google-services.json`, `secrets/**`, …) — a refusal costs
  one edit, a leaked keystore costs a rotation;
- `preflight.py` reports anything — use `--no-preflight` only when the findings
  are deliberate.

It commits on the current branch (normally `main`) and pushes there; no branch,
no pull request. Exit codes: `0` committed/pushed, `1` the push failed,
`2` refused before changing anything. An `--amend` push uses
`--force-with-lease`, never a bare `--force`.

## Seeing a screen — look, do not guess

You cannot run the app, but you can *see* it. `tool/see_screen.py` asks CI to
build the app for web and photograph the routes you name, waits for the run,
downloads the images and prints their paths. Then open them — with your image
tool, not your imagination:

```bash
python3 tool/see_screen.py --route /settings           # one screen
python3 tool/see_screen.py --route / --route /profile  # several, one build
python3 tool/see_screen.py --route /settings --wait-ms 12000   # slow first frame
```

* **Use it before and after a UI change.** Before: see what the screen looks
  like now. After: see what your change did. A green CI says the code compiles;
  only the picture says the layout is right.
* This is the one thing that does start a run — it dispatches the UI-screenshots
  workflow itself, so use it deliberately, not on every edit.
* The routes are the app's own (`/settings`, `/profile`) — the same names the
  app navigates to. A screen behind a login or several taps cannot be reached
  this way; ask the human for a screenshot of that one instead.
* It is the **web** build: layout, colours and text are faithful; fonts and
  platform widgets differ, and camera/bluetooth/notification plugins render as a
  blank screen. The script says so when the pixels are flat — believe it rather
  than "fixing" the capture.
* `--out` defaults to `.agent-screens/` (git-ignored). The images are throwaway
  artifacts: never commit them, and never use one as a test fixture.
* No token? `gh auth login` once, or pass `--token-file`.

## What a push costs here

| Situation | What runs |
|---|---|
| Push to `main` (any change) | nothing — CI is manual |
| Docs-only change (`**.md`, `docs/**`, `distribution/**`) | nothing |
| You ask the human to run CI | CI once, for the whole batch |
| `see_screen.py` | the UI-screenshots workflow, once per call |

If you want a run right now, do **not** retrigger it with an empty commit — use
*Actions → Run workflow* (or ask the human to).

## CI map

| Workflow | Runs when | What it does |
|---|---|---|
| `ci.yml` → shared `flutter-build.yml` | **manual** (`workflow_dispatch`) | `dart format` check → `flutter analyze --fatal-infos` → `flutter test` + coverage |
| `web-preview.yml` | manual dispatch, branch delete | builds the web app, deploys `preview/<branch>/` to GitHub Pages |
| `manual-build.yml` | manual dispatch | APK / AAB artifact |
| `publish-release.yml` | manual dispatch | signed build → tag → GitHub Release (+ Play internal if configured) |
| `release.yml` | `v*` tag push | signed AAB artifact for the tag |

The reusable workflows are pinned by tag; bump the pin in one place
(`.github/workflows/*.yml`) and every project picks the change up.

## Reading CI without wasting a turn

```bash
python3 tool/ci_watch.py                       # HEAD commit, waits, prints failures
python3 tool/ci_watch.py --branch main         # newest runs of a branch
python3 tool/ci_watch.py --once                # no waiting: current state only
python3 tool/ci_watch.py --sha <sha>           # a specific commit
python3 tool/ci_watch.py --token-file secrets/gh_token.txt
```

Token order: `--token-file`, then `$GITHUB_TOKEN` / `$GH_TOKEN`, then `gh auth
token`. Never print a token, and never paste one into a log or a commit.

Raw API equivalents, if you need them:

```bash
GET /repos/{owner}/{repo}/actions/runs?head_sha=<sha>     # run list + conclusions
GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs      # failing job and step
GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs      # plain-text log
```

The log endpoint answers with a **302 to blob storage**; the pre-signed URL
rejects a request that still carries the `Authorization` header
(`InvalidAuthenticationInfo`), so strip it on redirect — `ci_watch.py` does.

## Working rules

- **Small, focused diffs.** One concern per commit; conventional commit
  messages (`fix(profile): …`, `feat(cv): …`, `chore(ci): …`).
- **Push straight to `main`.** No feature branch, no pull request. Batch small
  changes and let the human run CI once at the end.
- **Secrets never enter git:** `google-services.json`, `android/key.properties`,
  `*.jks` / `*.keystore`, `.pem`, tokens. CI receives them from repository
  secrets. Do not add them to the repo to "make CI pass".
- **Respect existing structure:** edit existing files over adding new ones, and
  read the file you are about to change (comments explain *why* the code is the
  way it is — keep that voice).

## Ask the human before

- running CI, when a batch is ready to be checked (they own the run button);
- **tagging a release**, or touching workflows / secrets / repository settings;
- force-pushing over history you do not own, or deleting branches, tags, or
  repository content;
- anything that publishes publicly, spends money, or is irreversible.

<!-- flutter-builder:agent-pack:end -->

Working instructions for coding agents in this repo. Read the whole file before
your first edit; it is short on purpose. Everything here is *current* — if you
change the code so a statement below becomes false, update this file in the
same commit.

**Owner:** Keshab Sarkar ([@Keshab1997](https://github.com/Keshab1997)) ·
**Repo:** `Keshab1997/quizbaaz` · **Stack:** Flutter 3.x / Dart 3.x

---

## 1. Orient yourself in 60 seconds

Gamified Class-10 quiz app for Indian students. Offline-first, Firebase-mirrored.

| Surface | Entry point |
|---|---|
| Home / streak / champion podium | `presentation/screens/dashboard/` |
| Daily 10-question timed quiz (+ lifelines) | `presentation/screens/daily_quiz/` |
| Chapter-wise question bank | `presentation/screens/chapter_quiz/` |
| 1 vs 1 bot battle | `presentation/screens/battle/` |
| Leaderboard, rewards, shop, history, notifications, profile | one folder each under `screens/` |
| Admin panel (author-only) | `presentation/screens/admin/` |

**The four ideas that explain most of the codebase:**

1. **Hive is the source of truth.** The UI reads and writes Hive; Firestore is
   only ever a mirror. This is why the app works with no network at all.
2. **Providers own state.** Every screen is a dumb renderer of a
   `ChangeNotifier` in `lib/data/providers/`.
3. **No placeholder data, ever.** If a value is not in Hive yet, the screen
   shows an empty state. Never invent a fake score, name, or avatar.
4. **No hardcoded user-facing strings.** Everything goes through `S.*` (§5).

---

## 2. Layout — put new code exactly here

```text
lib/
├── core/
│   ├── constants/    app_colors.dart · app_assets.dart      (no logic)
│   └── theme/        app_theme.dart — glassmorphism + neon tokens
├── data/
│   ├── models/       plain serialisable classes (fromJson/toJson)
│   ├── providers/    ChangeNotifier state — the only source of UI state
│   ├── repositories/ thin layer between providers and services
│   └── services/     hive · firestore · sync · shop · imgbb · translation · notifications · inbox · onesignal
├── l10n/             string catalogues + generated `S` accessor      (§5)
└── presentation/
    ├── screens/      one folder per feature, one screen per file
    └── widgets/      reusable: glass_card · neon_button · cached_avatar ·
                      streak_flame · champion_podium · name_effect_text ·
                      purchase_celebration · app_background · translatable_text
```

Naming: `*_screen.dart`, `*_widget.dart`, `*_provider.dart`, `*_service.dart`.
One public class per file.

**Size map** (helps you decide what to read before editing):
`user_provider` ~1050 · `quiz_provider` 782 · `firestore_service` 470 ·
`hive_service` ~620 · `shop_service` 418 · `sync_service` 355 ·
`battle_provider` 1099 · `notification_service` ~260 · `onesignal_service` ~190 · `notification_inbox` ~180 · `locale_provider` 90.

---

## 3. Hard rules (breaking these breaks the app)

| Rule | Why |
|---|---|
| Never write to Firestore from a widget | Writes go through `SyncService` or a repository, so offline queuing still works |
| Never invent placeholder/demo data in the UI | Empty state is the designed behaviour for a fresh install |
| Never hardcode a user-facing string | It must be translatable — see §5 |
| Never machine-translate quiz content at runtime | Terminology accuracy, offline use and rate limits — content ships pre-translated |
| Never put `S.*` inside a `const` expression | `S.foo` is a runtime getter; `const Text(S.cancel)` does not compile. Drop the *outer* `const` only, then re-add it to the children the analyzer flags |
| Never hardcode a colour | Use `AppColors`; the neon palette is a brand asset |
| Never hardcode an asset path in a widget | Declare in `pubspec.yaml` **and** reference via `AppAssets` |
| Never hand-edit `firebase_options.dart` | Regenerate with `flutterfire configure` |
| Never hand-edit `lib/l10n/app_strings.dart` | Generated — run `tool/gen_strings.py` |
| Never commit secrets, real API keys, or `.env` | Use env vars / local settings |
| Do not add Riverpod, GetX, or Bloc | The app is Provider-based; a partial migration is worse than none |
| Never `await` optional SDKs before `runApp` | Sounds, AdMob, UMP consent, local notifications, OneSignal and the LLM key pool can hang forever (empty placeholder WAVs, missing Play Services, OS permission dialogs). Only Hive is required for the first frame — everything else is `unawaited` with a timeout |

---

## 4. State, storage and sync

**Providers** (`lib/data/providers/`) — consume with `Consumer` or
`context.watch<T>()`; mutate with `context.read<T>()`.

`UserProvider` · `QuizProvider` · `BattleProvider` · `RewardsProvider` ·
`AuthProvider` · `LocaleProvider`

**Hive boxes** (all opened in `HiveService.initialize()`, schema v2):

| Box | Contents |
|---|---|
| `qb_user` | current `UserModel` |
| `qb_stats`   | `UserStats`, quiz / purchase / notification history |
| `qb_cache` | remote payloads with a timestamp (TTL cache) |
| `qb_meta` | flags, schema version, language choice, sync timestamps |
| `qb_pending` | Firestore writes queued while offline |

Cache keys are constants on `HiveService` (`cacheLeaderboard`,
`cacheChampions`, `cacheChapters`, `cacheDailyQuiz`, `cacheShopItems`) — add new
ones there so everything can be invalidated in one place. Use
`HiveService.cachePut/cacheGet(maxAge:)` and `setMeta/getMeta<T>`.

**Firestore collections:** `users` · `scores` · `leaderboard` · `winners` ·
`gifts` · `quiz_history` · `purchase_history` · `meta` · `admin_audit_logs`.
Also written/read by the `admin_api_key_manager` package: `admin_api_keys` ·
`admin_key_groups` · `api_error_logs` · `admin_alerts`. **A collection with no
rule in `firestore.rules` is denied outright** (there is no catch-all), so a new
collection is broken the moment the client touches it — that is exactly how Admin
→ API Keys ended up rendering `permission-denied` (rules v2.2.0).

**Remote config beats code.** `config/app` is an `AppConfig` document, and
`AppConfig.fromJson` prefers its keys over the built-in defaults, so editing
`app_config.dart` changes *nothing* on a device while the document still holds
the old value — and the value is mirrored into `qb_cache/app_config`, so it
survives going offline. The quiz countdown is the usual casualty:
`QuizProvider.questionTimeSec` is `config.secondsPerQuestion`, not a constant.
Battles read `question.timeLimitSec` instead, so a per-question
`time_limit_sec` overrides the global one there. Both are pulled once at
startup, so a config change needs an app restart to reach a device.

**SyncService** — `pushUser`, `pushStats`, `pushLeaderboardEntry`,
`pushQuizHistory`, `pushPurchaseHistory`, `pushGift`, `drainPending`,
`pullUser`, `pullStats`, `pullConfig`, `cachedConfig`, `syncAll`.
Offline pushes are enqueued and replayed by `drainPending()` at startup.

---

## 5. Localisation — en / bn / hi

Two independent layers, and users mix them (English UI, Tamil questions).

### 5.1 App language (hand-translated)

```text
lib/l10n/
├── strings_en.dart    base catalogue — SOURCE OF TRUTH for keys
├── strings_bn.dart    বাংলা
├── strings_hi.dart    हिन्दी
└── app_strings.dart   GENERATED accessor `S` — never edit by hand
```

**Adding a string:**

1. Add `'someKey': 'Some text',` to `strings_en.dart`. Use `{name}`
   placeholders — never Dart interpolation — so word order can change per
   language.
2. Add the same key to `strings_bn.dart` and `strings_hi.dart`.
3. `python3 tool/gen_strings.py` → regenerates `S` and reports any gap.
4. Use it: `Text(S.profileTitle)` · `Text(S.chapterCount(n: 12))`.

**Behaviour:** `S` is a context-free static class. A key missing from bn/hi
falls back to English; missing everywhere renders as the key name. It never
throws. `LocaleProvider` swaps the catalogue and `MaterialApp` is keyed on the
language code, so the whole tree rebuilds and every `S.*` is re-read.

**Fonts:** `AppTheme.darkThemeFor(languageCode)` — Hind Siliguri for Bangla
(Poppins has no Bengali glyphs), Poppins otherwise.

### 5.2 Quiz content (pre-translated, shipped in JSON)

Questions carry all three languages in the asset files — there is **no runtime
translation**. An earlier build machine-translated questions on the device and
it was the wrong trade for exam prep: unreliable subject terminology, a network
dependency in areas with poor connectivity, and rate limits. Do not reintroduce
it.

`LocalizedText` (`lib/data/models/localized_text.dart`) is the shared shape:

```json
"question": { "en": "…", "bn": "…", "hi": "…" }
"question": "…"                                  // English-only shorthand
```

`resolve(lang)` falls back `requested → en → any → ''`, so a half-translated
chapter degrades instead of blanking.

Models expose **both** forms, and the UI should use the plain one:

```dart
question.question            // String, in the current UI language
question.options             // List<String>, current UI language
question.questionIn('en')    // a specific language (admin preview, secondary line)
```

So a screen just writes `Text(question.question)` — no context, no provider
lookup, no `TranslatableText`. Changing the app language rebuilds the tree and
the getters re-resolve.

Same pattern for `ChapterModel.title` / `.description` and
`CategoryModel.categoryName`. `ChapterModel.titleSecondary` returns the English
title when the UI is not in English, which is why chapter cards show both —
board students revise in English terminology.

**Authoring:** see `docs/10_QUESTION_AUTHORING_GUIDE.md`, which includes the
AI prompt for generating a batch. Always finish with:

```bash
python3 tool/validate_questions.py --strict
```

## 6. Data & assets

- Question banks: JSON under `assets/data/`. Every translatable field is a
  `{en, bn, hi}` map — see `docs/10_QUESTION_AUTHORING_GUIDE.md` for the schema,
  the rules and the AI prompt, and `docs/03_JSON_DATA_SCHEMAS.md` for the wider
  Category → Chapter → Question tree.
- Admin-authored questions will live in Firestore and be **merged** with the
  bundled assets at read time — assets are the offline floor, Firestore is the
  live layer. See `docs/11_ADMIN_AI_QUESTION_GENERATOR_PLAN.md` before touching
  the question pipeline.
- `chapters_list.json` and each chapter bank both carry the chapter title; they
  must agree, and `total_questions` must match the real count. The validator
  treats a mismatch as an error — a card promising 20 questions and delivering
  3 is worse than a card that says 3.
- Generate new chapter scaffolding with `tool/generate_chapters.py`.
- `docs/03` holds the JSON schemas, `docs/10` the question authoring guide,
  `docs/11` the admin generator plan, `docs/12` the battle arena, `docs/16`
  OneSignal/FCM live push, `docs/17` the Google Play release runbook, `docs/18`
  the owner-facing publish checklist, `docs/19` the Firestore→bundle pull,
  `docs/20` the Play Developer API autopublish of the store listing + AAB,
  `docs/21` the daily competition (one counted score per day, packets, the
  publishing cron) and `docs/22` the release-push pipeline (dashboard
  banner, `open: app_update` deep link, Update Center, OneSignal targeting).
  **Read the matching doc before touching that subsystem.** `ADMIN_TODO.md`
  tracks admin work; `PROJECT_REVIEW.md` holds the audit that the P1 sweep
  worked through.

---

## 7. Commands

```bash
flutter pub get
flutter analyze                 # must be zero errors AND zero warnings
flutter test
flutter run                     # device / emulator
flutter build web               # used for admin + GUI testing

python3 tool/gen_strings.py     # regenerate S, report translation gaps
python3 tool/verify_l10n.py     # unknown keys · const misuse · bracket damage
python3 tool/apply_l10n.py      # migrate raw English literals to S.* (re-runnable)
python3 tool/validate_questions.py --strict  # schema, ids, translations; warnings fail
python3 tool/set_question_seconds.py --show   # remote config/app seconds_per_question
python3 tool/set_question_seconds.py         # set it to 30 (restart devices after)
python3 tool/publish_daily_packet.py --dry-run   # today's daily packet, no write
python3 tool/publish_daily_packet.py             # publish daily_quiz_packets/{today}
python3 tool/publish_daily_packet.py --days 3    # today + the next two days
# (the daily cron does the last one at 00:00 IST — see docs/21; no packet for a
#  day means every run that day is unranked and no score reaches the board)
python3 tool/publish_play.py --validate          # Play listing: local sanity check
python3 tool/publish_play.py --listing           # publish listing via Play API (docs/20)
python3 tool/publish_play.py --aab app.aab --track alpha      # Closed testing (alias: closedtesting)
# Release notes: store_listing/whats_new.yaml (en/bn/hi) → Play API + in-app What's new dialog.

# Play listing/AAB publishing needs the service-account JSON in the secret
# PLAY_SERVICE_ACCOUNT_JSON (GitHub) or GOOGLE_APPLICATION_CREDENTIALS (local).
# The listing source of truth is store_listing/listing.yaml — never hand-edit
# the Console forms.

# After removing `const` from an expression that gained an S.* getter, the
# analyzer will flag the children that are still const-able. Feed the report
# straight back in instead of hand-editing 90 call sites:
flutter analyze | grep prefer_const_constructors > /tmp/analyze.txt
python3 tool/apply_const_hints.py /tmp/analyze.txt
```

> **Editing by line:column?** Dart columns are UTF-16 code units, Python string
> indices are code points. This codebase is full of emoji (`'👦 Male'`), so a
> naive `col - 1` lands mid-identifier on those lines. Use
> `utf16_col_to_index()` from `tool/apply_const_hints.py`;
> `tool/verify_l10n.py` fails the build if a `const` ends up spliced into an
> identifier.

Run `flutter analyze` **and** `python3 tool/verify_l10n.py` before claiming any
UI change is done.

Release binaries are built by GitHub Actions, not locally: `manual-build.yml`
(APK/AAB artifact, test or real AdMob IDs) and `publish-release.yml` (tag +
GitHub Release, real IDs only) both call the shared
`Keshab1997/flutter-builder` workflow. AdMob IDs come from repository
*variables* `ADMOB_*`, signing from the four `ANDROID_KEYSTORE_BASE64` /
`KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` *secrets*. Never paste
either into a workflow file or into `ad_config.dart` — see `docs/17`.

---

## 8. Task playbook

**Adding a screen**
`screens/<feature>/<name>_screen.dart` → strings via `S.*` → state from an
existing provider (add a new one only if the state is genuinely new) → colours
from `AppColors` → wrap surfaces in `GlassCard` → run gen + verify + analyze.

**Adding a shop item / power-up**
Model in `models/shop_item.dart` → catalogue entry → purchase path through
`shop_service.dart` → the item's label and category name are strings, so they
need catalogue keys too.

**Chapter sets**
A chapter is played ten questions at a time (`kQuestionsPerSet`). Set
boundaries are positional, and stay stable only because questions are
**appended, never inserted** — breaking that reshuffles sets people have
already cleared. Progress lives in Hive under `chapter_set_progress`;
`QuizProvider.startChapterQuiz(setIndex:, practice:)` plays one. A `practice`
run credits nothing: no coins, no gems, no stats, no leaderboard, no history
row. If you add a reward, gate it on `isPractice`.

**Touching the daily competition**
One counted score per player per competition day: the **first** ranked run is
written to the leaderboard and locks the day, later runs are ignored (a Score
Shield buys one replacement). A run is only *ranked* when the day has an
approved packet in `daily_quiz_packets/{yyyy-MM-dd}` — without one the quiz
still plays, but as an unranked practice set that never reaches the board.
The rule lives in `services/daily_score_lock.dart`, is applied in
`UserProvider._settleDailyScore`, and is mirrored by the idempotent
`submitDailyResult` callable. Read `docs/21_DAILY_SCORING_RULES.md` first.

**Touching the quiz flow**
`QuizProvider` owns the timer, lifelines, scoring and anti-cheat. Read it fully
before editing — lifeline state (`fiftyFiftyUsed`, `freezeUsed`, `skipUsed`,
`hintUsed`, `audienceUsed`, stock counters) resets per question and the reset
points are easy to miss. A deliberate exit must call `quitQuiz()` so it
cancels the timer, clears the run, and invalidates any delayed callback before
its route is popped; both app-bar and system Back must follow that same path.

**Anything that persists**
Write to Hive first, then enqueue/push to Firestore. Never the reverse.

**Debugging "the value is wrong"**
Check Hive before Firestore — the UI never reads Firestore directly.

**A helper method needs `context`**
Most screens here are `StatelessWidget`, so `context` is *not* an implicit
field — pass it as the first parameter (`_buildX(BuildContext context, ...)`)
the way `_buildOptionButton` already does. Reaching for `context` inside a
StatelessWidget helper is the single most common compile error in this repo.

---

## 9. Style

- Follow `flutter_lints` (`analysis_options.yaml`). Prefer `const` constructors
  everywhere `S.*` is not involved.
- Code identifiers, comments and doc comments are **English**. Only catalogue
  values are translated.
- Explain *why* in comments, not *what* — the code already says what.
- Keep models free of Firebase imports; isolate Firestore mapping in
  `firestore_service.dart` and the repositories.
- **`dart format` output depends on the root package's language version**, which
  is the lower bound of `environment.sdk` in `pubspec.yaml` — not on the SDK you
  happen to run. Below 3.7 the formatter rewrites the whole codebase into the
  legacy short style. Always format *after* `flutter pub get` (the language
  version is read from `.dart_tool/package_config.json`; without it the
  formatter guesses and silently picks the other style), and keep the declared
  floor in step with the style the code is written in. CI runs
  `dart format --output=none --set-exit-if-changed .` and fails on any drift.
  A trailing comment that pushes a field past the page width is why the
  formatter splits `final String` from its name — move the comment above the
  field instead of accepting that.

---

## 10. Commits & scope

- Branch from `main`; the user merges. One feature per commit.
- Prefix the area: `quiz:`, `admin:`, `shop:`, `ui:`, `i18n:`, `data:`.
- Subject line in the imperative, then a body explaining the reasoning and any
  trade-off. Reviewers read the body, not the diff.
- Update `AGENTS.md`, `README.md` and the relevant `docs/*.md` in the same
  commit as the behaviour change.

---

## 11. Skills

The **`superpowers`** plugin sits above default behaviour but below this file.
If there is even a 1% chance a skill applies, invoke it *before* improvising.

**Always on:** `using-superpowers` — check for a relevant skill before any
response or action, including clarifying questions.

**Process (run before implementation):**

| Trigger | Skill |
|---|---|
| New feature / component / behaviour change | `brainstorming` |
| Spec in hand, multi-step task | `writing-plans` |
| Executing a written plan | `executing-plans` |
| Independent tasks in this session | `subagent-driven-development` |
| 2+ independent tasks, no shared state | `dispatching-parallel-agents` |
| Isolated feature work | `using-git-worktrees` |
| Any bug, test failure, surprise | `systematic-debugging` |
| Implementing a feature or bugfix | `test-driven-development` |
| About to say "done / fixed / passing" | `verification-before-completion` |
| Task complete, before merge | `requesting-code-review` |
| Receiving review feedback | `receiving-code-review` |
| Deciding integration | `finishing-a-development-branch` |
| Creating or editing a skill | `writing-skills` |

**Project & platform:**

| Task | Skill |
|---|---|
| Click/type/screenshot the web build | `browser-use` / `web-gui-tester` |
| Generate `.docx` / `.pdf` / `.xlsx` / `.pptx` | `document-skills:*` or `officecli` |
| Mirror this repo to another GitHub account | `cross-account-github-sync` |
| Config broken (skill/MCP/hook/plugin) | `zcode-guide:diagnosing-*` |
| Cross-repo architecture question | `graphify` |
| Turn a repeated workflow into a skill | `skill-creator` |
| Telegram pairing / broadcast | `telegram:configure`, `telegram:access` |
