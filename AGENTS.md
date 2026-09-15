# AGENTS.md — QuizBaaz 3D

Working instructions for coding agents in this repo. Read the whole file before
your first edit; it is short on purpose. Everything here is *current* — if you
change the code so a statement below becomes false, update this file in the
same commit.

**Owner:** Keshab Sarkar ([@Keshab1997](https://github.com/Keshab1997)) ·
**Repo:** `Keshab1997/quizbaaz-flutter` · **Stack:** Flutter 3.x / Dart 3.x

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
python3 tool/validate_questions.py
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
- `docs/01`…`docs/16` are the architecture blueprints; `docs/10` is the question
  authoring guide, `docs/11` the admin generator plan, `docs/15` local Daily Quiz
  reminders, `docs/16` OneSignal/FCM live push. **Read the matching doc before
  touching that subsystem.** `ADMIN_TODO.md` tracks admin work.

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
python3 tool/validate_questions.py   # question banks: schema, ids, translations

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

**Touching the quiz flow**
`QuizProvider` owns the timer, lifelines, scoring and anti-cheat. Read it fully
before editing — lifeline state (`fiftyFiftyUsed`, `freezeUsed`, `skipUsed`,
`hintUsed`, `audienceUsed`, stock counters) resets per question and the reset
points are easy to miss.

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
