# Admin AI Question Generator — Implementation Plan

**Status:** planning · **Owner:** @Keshab1997 · **Target:** QuizBaaz 3D admin panel

Build an admin workflow that adds **chapters** and **questions** to the bank,
where one click produces **10 exam-accurate questions** in **English, বাংলা and
हिन्दी** — question, four options, correct answer and explanation — using the
LLM key pool from
[`admin_api_key_manager`](https://github.com/Keshab1997/admin_api_key_manager).

Two rules that shape every decision below:

1. **Nothing is ever overwritten.** Generating again must *add* to a chapter,
   never replace it, so banks accumulate over months into hundreds of
   questions per chapter.
2. **Nothing reaches a student unreviewed.** The model drafts; the admin
   approves. A wrong question in an exam-prep app costs more trust than a
   missing one.

---

## 0. Blocker to clear first

`admin_api_key_manager` cannot be installed into QuizBaaz as it stands:

| Package | QuizBaaz needs | admin_api_key_manager allows | Result |
|---|---|---|---|
| `firebase_core` | `^4.0.0` | `^3.0.0` (`<4.0.0`) | ❌ conflict |
| `cloud_firestore` | `^6.8.0` | `^5.0.0` (`<6.0.0`) | ❌ conflict |

`flutter pub get` will refuse outright. Fix in the **package** repo by widening
the constraints — it uses only stable Firestore APIs, so nothing else changes:

```yaml
dependencies:
  cloud_firestore: '>=5.0.0 <7.0.0'
  firebase_core: '>=3.0.0 <5.0.0'
```

- [ ] **T0.1** Widen constraints in `admin_api_key_manager/pubspec.yaml`, push
- [ ] **T0.2** Smoke-test the package against Firestore 6.x (read, write, snapshot listener)
- [ ] **T0.3** Add the git dependency to QuizBaaz `pubspec.yaml`, confirm `flutter pub get`

> If widening turns out to break, fall back to vendoring the four service files
> under `lib/data/services/api_keys/`. Prefer the package — a shared fix helps
> SpeakEasy too.

---

## 1. The architectural decision: where do admin questions live?

Today the bank is **bundled JSON assets**, which are read-only at runtime. An
admin cannot write to `assets/data/`. So admin-authored content must live in
**Firestore** and be **merged** with the bundled bank at read time.

```
┌────────────────────┐     ┌────────────────────┐
│  assets/data/*.json│     │     Firestore      │
│  (shipped, stable) │     │ (admin-authored)   │
└─────────┬──────────┘     └─────────┬──────────┘
          └───────────┬──────────────┘
                      ▼
             QuizRepository.merge()
             dedupe by question id
             Firestore wins on conflict
                      ▼
                 Hive cache
                      ▼
                     UI
```

Consequences, all intentional:

- The app still works offline and on a fresh install — assets are the floor.
- Admin additions appear without an app update.
- A question authored in the app can later be exported into assets (see §7) so
  it ships to users who never sync.

### Firestore schema

```jsonc
// question_banks/{chapterId}
{
  "chapter_id": "math_ch_01",
  "chapter_title": { "en": "…", "bn": "…", "hi": "…" },
  "question_count": 47,          // maintained by a counter, not a full read
  "updated_at": "2026-08-23T…",
  "updated_by": "uid"
}

// question_banks/{chapterId}/questions/{questionId}
{
  "id": "math_ch1_q001",
  "question":    { "en": "…", "bn": "…", "hi": "…" },
  "options": [
    { "en": "…", "bn": "…", "hi": "…" }
  ],
  "correct_index": 1,
  "explanation": { "en": "…", "bn": "…", "hi": "…" },
  "points": 10,
  "time_limit_sec": 15,

  // provenance — so a bad batch can be found and rolled back
  "source": "ai",                // ai | manual | asset
  "model": "gemini-2.0-flash",
  "generated_at": "…",
  "created_by": "uid",
  "reviewed": true,
  "fingerprint": "sha1-of-normalised-english-stem"
}

// question_categories/{categoryId}
{ "category_name": {"en":"…","bn":"…","hi":"…"}, "icon": "…", "color_hex": "#…", "priority": 1 }

// question_categories/{categoryId}/chapters/{chapterId}
{ "title": {...}, "description": {...}, "chapter_number": 3, "is_unlocked": true }
```

**Question ids are document ids.** Writing uses `set()` on a specific id, so a
re-run cannot create a second copy, and nothing ever calls `delete()` on the
collection. Deletion is a deliberate, single-question admin action.

- [ ] **T1.1** `QuestionBankService` — Firestore CRUD, batched writes, counter upkeep
- [ ] **T1.2** Extend `QuizRepository` to merge asset + Firestore banks, dedupe by id
- [ ] **T1.3** Cache the merged result in Hive; invalidate on admin write
- [ ] **T1.4** Firestore rules: public read, admin-only write on all three collections

---

## 2. Never lose a question — the append guarantee

The failure this design is built to prevent: "I generated 10 more and my
previous 40 vanished."

| Guard | Mechanism |
|---|---|
| No bulk replace | Only `set(id)` on individual question docs. No `delete()` on a collection anywhere in the admin code path |
| Idempotent re-runs | Question id is the doc id, derived from `chapterId + sequence` |
| Sequence never reuses | Next number = `max(existing numeric suffix) + 1`, read before generating |
| Duplicate content | `fingerprint` = SHA-1 of the normalised English stem (lowercase, punctuation and whitespace stripped). Reject on match |
| Near-duplicate | Token-overlap check against existing stems; >0.85 similarity is flagged for review, not silently dropped |
| Accidental wipe | Every write is mirrored to `admin_audit_logs` with actor, chapter and question ids |
| Undo | A batch gets a `batch_id`; "Undo last batch" deletes only that batch's ids, within 24h |

- [ ] **T2.1** `fingerprint()` + normaliser, with tests for punctuation/case/spacing
- [ ] **T2.2** Next-sequence resolver that reads existing ids first
- [ ] **T2.3** Near-duplicate similarity check
- [ ] **T2.4** Batch id + "Undo last batch" action
- [ ] **T2.5** Test: generating twice into a 40-question chapter yields 60, never 20

---

## 3. Accuracy — how we stop the model inventing wrong answers

Accuracy is the hard part; "1 click, 10 questions" is easy. Layers, cheapest
first:

**3.1 A prompt that constrains rather than invites**
- Full chapter context: subject, chapter title in all three languages, board
  (WB / CBSE Class 10), and the chapter description.
- The stems of existing questions, so it cannot repeat them.
- Strict JSON schema, `response_mime_type: application/json` where the provider
  supports it.
- Explicit rules: exactly 4 options, one correct, distractors must be plausible
  student mistakes, numbers/formulas/units unchanged across languages,
  terminology follows the textbook, explanation shows the reasoning.

**3.2 Machine validation before a human ever sees it** — reuses the exact rules
already in `tool/validate_questions.py`, ported to Dart as
`QuestionValidator` so both sides agree:

| Check | Action |
|---|---|
| Not valid JSON / schema mismatch | Reject, retry once with the parse error appended |
| ≠ 4 options | Reject |
| `correct_index` out of range | Reject |
| Two options identical in any language | Reject |
| A language missing on any field | Reject |
| bn or hi identical to en (Latin script) | Reject — translation was skipped |
| Fingerprint already in the chapter | Reject as duplicate |
| Explanation shorter than 20 chars | Flag |
| Explanation does not support `correct_index` | Flag for review |

Rejected items are **regenerated**, so 10 requested still means 10 offered.

**3.3 A verification pass (optional, toggle in the UI)**
Second call, different key from the pool: *"Here is a question and its marked
answer. Is the marked answer correct for WB Class 10? Reply
`{verdict: ok|wrong|unsure, correct_index: n, reason: '…'}`."*
Disagreements are surfaced in the review screen in red. Costs one extra call
per question; worth it for Math and Physical Science.

**3.4 The human gate**
Nothing is written until the admin taps **Approve**. The review screen shows
each question with all three languages, the marked answer highlighted, the
explanation, and any flags.

- [ ] **T3.1** `QuestionPromptBuilder` — chapter context + existing stems + schema
- [ ] **T3.2** `QuestionValidator` in Dart, mirroring the Python validator
- [ ] **T3.3** Retry-on-reject loop, capped at 3 rounds, top-up to the requested count
- [ ] **T3.4** Optional verification pass, per-question verdict badges
- [ ] **T3.5** Golden tests: malformed JSON, 3 options, bad index, duplicate options, untranslated text

---

## 4. The generation service

`AiQuestionGenerator` (`lib/data/services/ai_question_generator.dart`)

```dart
Stream<GenerationProgress> generate({
  required ChapterModel chapter,
  required int count,              // default 10
  required List<String> existingStems,
  Difficulty mix = Difficulty.balanced,
  bool verify = false,
});
```

- Takes a key via `ApiKeyManager.instance.getNextKey()`; reports success and
  failure back so cooldowns and failover work.
- Emits progress (`requested / received / accepted / rejected / retrying`) so
  the UI can show a real bar instead of a spinner.
- Generates in **two chunks of 5** rather than one of 10: shorter responses are
  markedly less likely to drift, truncate, or lose a language near the end.
- Handles `null` key (no healthy key) with a clear message pointing at the API
  Keys screen.

- [ ] **T4.1** `AiQuestionGenerator` with progress stream
- [ ] **T4.2** Provider adapters: Gemini native and OpenAI-compatible `/chat/completions`
- [ ] **T4.3** Chunking, retry, top-up
- [ ] **T4.4** Wire `reportSuccess` / `reportFailure` into the key pool
- [ ] **T4.5** Friendly errors: no key, all keys cooling, quota exhausted, offline

---

## 5. Admin screens

### 5.1 Chapter Manager — `admin/chapter_manager_screen.dart`
- Subject → chapter tree, mirroring today's `chapters_list.json` layout so it
  feels familiar.
- Per chapter: live question count, translation coverage (`en 47 · bn 47 · hi 45`).
- **Add / Edit chapter** sheet with three-language fields for title and
  description, chapter number, student-visibility toggle and unlock toggle.
  A disabled chapter is hidden from student chapter lists; it remains visible
  to admins so it can be enabled again.
- **Add subject** sheet with three-language name, icon and colour.

- [ ] **T5.1** Chapter tree with counts and coverage
- [ ] **T5.2** Add/edit chapter sheet (trilingual)
- [ ] **T5.3** Add/edit subject sheet (trilingual)
- [ ] **T5.4** Reorder chapters

### 5.2 Question Manager — `admin/question_manager_screen.dart`
- Opened from a chapter. Lists existing questions with search and filters
  (needs translation / AI / manual / flagged).
- Per question: expand to see all three languages, edit, delete (with confirm).
- **➕ Add manually** — the trilingual form.
- **✨ Generate 10 with AI** — the headline button.

- [ ] **T5.5** Question list with search + filters
- [ ] **T5.6** Manual add/edit form, trilingual, live validation
- [ ] **T5.7** Delete with confirmation and audit log

### 5.3 The trilingual field widget — `admin/widgets/trilingual_field.dart`
One reusable widget used by every form:

```
┌─────────────────────────────────────────┐
│ Question                    [EN][BN][HI]│   ← tabs, dot marks filled
│ ┌─────────────────────────────────────┐ │
│ │ Which enzyme in saliva breaks down… │ │
│ └─────────────────────────────────────┘ │
│ ⚠ Hindi is empty          [✨ Translate]│   ← fills the other two from English
└─────────────────────────────────────────┘
```

- Tab per language, a filled/empty dot on each so gaps are obvious at a glance.
- Per-field **Translate** button (one LLM call) for manual entry — this is the
  *authoring-time* use of machine translation, which is fine; runtime is what
  we removed.
- Inline validation: empty required language, identical-to-English.

- [ ] **T5.8** `TrilingualField` widget + tests
- [ ] **T5.9** Per-field translate action

### 5.4 Generation Review — `admin/ai_generation_review_screen.dart`
The screen that makes the feature trustworthy.

```
✨ Generated 10 questions · Real Numbers          [Regenerate all]
─────────────────────────────────────────────────────────────
 ✅ 1. What is the HCF of 96 and 404?           EN BN HI
      ● 4  ← marked correct                    [edit] [✕ drop]
      💡 404 = 96×4+20 …
─────────────────────────────────────────────────────────────
 ⚠️ 2. Verifier disagrees: says index 2, not 0  EN BN HI
─────────────────────────────────────────────────────────────
 🔁 3. Near-duplicate of math_ch1_q014 (0.91)
─────────────────────────────────────────────────────────────
        [ Approve 8 selected and add to chapter ]
```

- Every question editable before saving.
- Selected-count on the save button; the admin can drop the bad ones and keep
  the rest rather than discarding a whole batch.
- Saving **appends**; a banner confirms `47 → 55 questions`.

- [ ] **T5.10** Review list with per-question status, edit, drop
- [ ] **T5.11** Approve-selected → batched append + audit log
- [ ] **T5.12** Before/after count banner and Undo

### 5.5 Dashboard entries
- [ ] **T5.13** Add "Chapter Manager", "Question Bank" and "API Keys" tiles to
      `admin_dashboard_screen.dart`, gated on `userProvider.isAdmin`
- [ ] **T5.14** Mount `AdminApiKeysScreen` from the package behind the same gate

---

## 6. Strings

Everything user-facing goes through `S.*`; admin screens are currently English
and stay English (author-only surface), but the shared widgets and any snackbar
a non-admin could see must be catalogued.

- [ ] **T6.1** Add admin generator keys to `strings_en/bn/hi.dart`
- [ ] **T6.2** `python3 tool/gen_strings.py && python3 tool/verify_l10n.py`

---

## 7. Export back to assets

Firestore content is invisible to a user who never syncs, and to a fresh
install offline. So the admin can export a chapter back into
`assets/data/questions/*.json`, which is then committed.

- [ ] **T7.1** "Export chapter to JSON" — share sheet / clipboard
- [ ] **T7.2** `tool/pull_firestore_questions.py` — pull all banks into assets
- [ ] **T7.3** Round-trip test: export → `validate_questions.py` passes

---

## 8. Testing

- [ ] **T8.1** `QuestionValidator` unit tests — one per rejection rule
- [ ] **T8.2** Fingerprint/normaliser tests
- [ ] **T8.3** Generator tests against recorded LLM responses (good, malformed, truncated, missing language)
- [ ] **T8.4** Append test: 40 + 10 = 50, ids unique, nothing removed
- [ ] **T8.5** Merge test: asset + Firestore, Firestore wins, no duplicates
- [ ] **T8.6** Widget test: `TrilingualField` marks a missing language
- [ ] **T8.7** `flutter analyze` clean, `verify_l10n.py` clean, `validate_questions.py` clean

---

## 9. Order of work

| Phase | Contents | Why this order |
|---|---|---|
| **A** | T0.1–T0.3 | Nothing can start until the package installs |
| **B** | T1.1–T1.4, T2.1–T2.5 | Storage and the append guarantee, before anything writes |
| **C** | T5.8–T5.9, T5.1–T5.7 | Manual admin CRUD — a complete, useful feature on its own |
| **D** | T3.1–T3.5, T4.1–T4.5 | Generation on top of a bank that already works |
| **E** | T5.10–T5.14 | The review screen and the dashboard entries |
| **F** | T6, T7, T8 | Strings, export, full test pass |

Phase C ships something usable even if generation is delayed. Phase B first
means no batch can ever be lost, including the very first one.

---

## 10. Decisions still open

| # | Question | Default if unanswered |
|---|---|---|
| D1 | Widen the package constraints, or vendor the services into QuizBaaz? | Widen the package |
| D2 | Run the verification pass by default, or opt-in per batch? | Opt-in, on by default for Math and Physical Science |
| D3 | Generate 10 in one call or 2×5? | 2×5 — shorter responses drift less |
| D4 | Should admin questions go live immediately, or wait for an export+release? | Live immediately; export is for offline parity |
| D5 | Keep admin UI English-only? | Yes — author-only surface |

---

## 11. Out of scope for now

- Image-based questions
- Per-question analytics (how many students got it wrong)
- Bulk CSV / Excel import
- Scheduling generated questions into the daily quiz automatically
