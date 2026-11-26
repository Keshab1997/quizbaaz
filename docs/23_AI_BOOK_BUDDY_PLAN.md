# 23 — AI Book Buddy (`smart_ocr_ai_bridge` Integration)

Interactive textbook scanner, AI study tutor, and instant MCQ practice quiz
generator for **QuizBaaz**, powered by
[`smart_ocr_ai_bridge`](https://github.com/Keshab1997/smart_ocr_ai_bridge) +
[`admin_api_key_manager`](https://github.com/Keshab1997/admin_api_key_manager).

---

## 1. What Students Can Do

1. **Scan a Book Page (Camera or Gallery)**
   - Students take a photo of any textbook page, handwritten note, or diagram
     (or upload from their gallery).
   - `SmartOcrAiBridge` runs 5-script on-device ML Kit OCR (`Latin`,
     `Devanagari`, `Chinese`, `Japanese`, `Korean`) at **0 API cost**, cleans
     Indic/Bengali OCR artifacts, and compacts whitespace.
   - Under `OcrRoutingMode.hybridAuto`, readable pages (`ocrScore >= 20`) send
     **compacted text only** (~85%–95% fewer tokens than vision). Pages with
     handwriting, pure Bengali script without Latin/Devanagari anchors, or
     diagrams automatically fall back to multimodal vision bytes.

2. **Ask Anything & Get Clear Explanations**
   - One-tap quick chips (*Explain simply*, *Key bullet points*, *Important
     exam notes*) plus free-form follow-up questions in the student's active UI
     language (`en` / `bn` / `hi`).
   - Follow-up questions on an already-scanned page reuse the compacted OCR
     text via `SmartOcrAiBridge.analyzeExtractedText(...)` + the 0-token LRU
     cache (`OcrPromptCache`), avoiding repeated image uploads.

3. **Generate & Play Practice MCQs Instantly**
   - Students can ask AI to generate **5 or 10 MCQs** directly from the scanned
     book page (`QuestionModel` JSON with 4 options, `correct_index`, and
     concise explanation).
   - Tapping **Play Quiz Now** launches QuizBaaz's native `DailyQuizScreen`
     player (`QuizProvider.startCustomPracticeQuiz(...)`) with shuffled options,
     countdown timer, sound effects, answer review, and replay support.
   - **Economy safety:** Every AI Book Buddy quiz runs strictly in **practice
     mode** (`_isPractice = true`, `_isDailyQuiz = false`). It awards **0
     coins, 0 gems, 0 XP**, writes no ranked history, and never touches the
     leaderboard — preventing reward farming.

4. **Offline Saved Study Notebook (Hive)**
   - Scanned pages, extracted text, Q&A explanations, and generated MCQ sets
     are persisted locally in Hive (`qb_stats` key `book_buddy_sessions`, capped
     at 20 recent sessions) so students can re-read explanations and replay
     generated quizzes completely offline.

---

## 2. Architecture & File Map

| Layer | File | Responsibility |
|---|---|---|
| Package wiring | `pubspec.yaml`, `android/app/build.gradle.kts`, `lib/main.dart` | `smart_ocr_ai_bridge` dependency, 4 non-Latin ML Kit Android artifacts, `SmartOcrAiBridge.instance.bindApiKeyManager(ApiKeyManager.instance)` |
| Data model | `lib/data/models/book_study_session.dart` | Serialisable study session (`BookStudySession`, `BookChatTurn`) stored in Hive (`fromJson`/`toJson`) |
| Service | `lib/data/services/book_buddy_service.dart` | Wraps `SmartOcrAiBridge` for page scanning, Q&A explanations, and validated `QuestionModel` MCQ generation |
| Persistence | `lib/data/services/hive_service.dart` | `loadBookStudySessions()`, `saveBookStudySessions()`, `clearBookStudySessions()` |
| State | `lib/data/providers/book_buddy_provider.dart` | `ChangeNotifier` managing active scan, chat turns, generated MCQs, token-savings badge, and saved Hive sessions |
| Quiz integration | `lib/data/providers/quiz_provider.dart`, `lib/presentation/screens/quiz_result/quiz_result_screen.dart` | `startCustomPracticeQuiz(...)` + `retryCustomPractice()` in unranked practice mode |
| UI | `lib/presentation/screens/book_buddy/book_buddy_screen.dart`, `dashboard_screen.dart` | Glassmorphism + neon AI Book Buddy screen, quick-action chips, MCQ launcher, and Dashboard entry point |
| Localisation | `lib/l10n/strings_{en,bn,hi}.dart` → `tool/gen_strings.py` | Full trilingual UI strings (`S.bookBuddy*`) — zero hardcoded user-facing strings |
| Tests | `test/book_buddy_test.dart` | Offline unit tests covering OCR/vision routing, Q&A, MCQ JSON parsing, Hive persistence, and 0-reward practice quiz execution |

---

## 3. Direct Client Key-Pool Note (Deferred Security Follow-Up)

Per owner decision (2026-11-26), Cloud Functions proxy was **intentionally
skipped** to avoid Firebase Blaze/Cloud Functions billing costs right now.

- Currently in `firestore.rules` (v2.3.0), `admin_api_keys` is readable only by
  accounts holding the `admin: true` custom claim (`isAdmin()`).
- Consequently, AI Book Buddy works immediately out-of-the-box on admin/owner
  devices (and any device with cached keys in `KeyCache`).
- **When rolling out live AI calls to non-admin student devices**, pick one of:
  1. **Zero-cost Cloudflare Worker / Vercel Edge proxy** holding free-tier
     Gemini/OpenRouter keys behind a per-UID rate limit, wired via a custom
     `KeyPoolAdapter`; or
  2. **Scoped read-only student key collection** (e.g. `student_ai_keys`
     holding rate-limited free-tier keys only, separate from `admin_api_keys`).

---

## 4. Implementation Checklist (TODO Tracker)

### Done / Active Batch
- [x] **T1 — Docs & Roadmap:** Author `docs/23_AI_BOOK_BUDDY_PLAN.md` with architecture, file map, economy rules, and TODO checklist.
- [x] **T2 — Package & Android ML Kit Setup:**
  - [x] Make `smart_ocr_ai_bridge` v1.1.0 Flutter-Web compatible (`conditional import` + `analyzeExtractedTextAsJson`) so `quizbaaz` web preview keeps building cleanly.
  - [x] Add `smart_ocr_ai_bridge` git dependency to `quizbaaz/pubspec.yaml`.
  - [x] Add the 4 required ML Kit script artifacts (`chinese`, `devanagari`, `japanese`, `korean`) to `android/app/build.gradle.kts`.
  - [x] Bind `SmartOcrAiBridge.instance.bindApiKeyManager(ApiKeyManager.instance)` in `lib/main.dart` (non-blocking `unawaited` startup).
- [x] **T3 — Data Models & Hive Storage:**
  - [x] Create `BookStudySession` & `BookChatTurn` models (`lib/data/models/book_study_session.dart`).
  - [x] Add Hive persistence helpers in `HiveService` (capped at 20 recent study sessions, cleared on sign-out/reset).
- [x] **T4 — AI Book Buddy Service & Provider:**
  - [x] Build `BookBuddyService` (`lib/data/services/book_buddy_service.dart`) using `SmartOcrAiBridge` (`hybridAuto`, follow-up text-only reuse, and resilient MCQ JSON parser into `QuestionModel`).
  - [x] Build `BookBuddyProvider` (`lib/data/providers/book_buddy_provider.dart`) and register it in `MultiProvider` (`lib/main.dart`).
- [x] **T5 — Practice Quiz Player Integration:**
  - [x] Add `startCustomPracticeQuiz` & `retryCustomPractice` on `QuizProvider` (strictly unranked `_isPractice = true`: 0 coins, 0 gems, 0 XP, 0 leaderboard writes).
  - [x] Wire replay button on `QuizResultScreen` for custom Book Buddy quizzes.
- [x] **T6 — Trilingual UI (`en` / `bn` / `hi`) & Dashboard Entry:**
  - [x] Add `bookBuddy*` keys to `strings_en.dart`, `strings_bn.dart`, `strings_hi.dart` and regenerate `lib/l10n/app_strings.dart` via `tool/gen_strings.py`.
  - [x] Build `BookBuddyScreen` (`lib/presentation/screens/book_buddy/book_buddy_screen.dart`) with camera/gallery picker, OCR/token-savings badge, quick study prompts, Q&A thread, 5/10 MCQ generator, and offline history drawer/sheet.
  - [x] Add prominent entry card + quick action on `DashboardScreen` and update `AGENTS.md` layout notes.
- [x] **T7 — Verification & Quality Gates:**
  - [x] Add unit tests in `test/book_buddy_test.dart` (OCR routing, Q&A, MCQ parsing, Hive storage, 0-coin practice guarantee).
  - [x] Pass `python3 tool/preflight.py`, `python3 tool/verify_l10n.py`, `flutter analyze`, and `flutter test test/book_buddy_test.dart`.

### Remaining / Future Enhancements (Deferred)
- [ ] **F1 — Non-Admin Student Key Delivery (Zero-Cost Proxy or Student Key Pool):** Keep `firestore.rules` untouched for now; before public student rollout, attach either a free Cloudflare Worker endpoint or a dedicated rate-limited `student_ai_keys` Firestore collection so raw admin keys are never exposed to general players.
- [ ] **F2 — Multi-Page Chapter Stitching:** Allow scanning 2–4 consecutive textbook pages into a single combined study session & 20-question chapter mock test.
- [ ] **F3 — Image Cropper Before OCR:** Optional crop/rotate step before ML Kit runs so students can isolate a single paragraph or math box on a crowded page.
