# Question Authoring Guide — QuizBaaz 3D

How to add questions to the bank so they render correctly in **English,
বাংলা and हिन्दी**, and pass `tool/validate_questions.py`.

---

## 1. Where questions live

```text
assets/data/
├── chapters_list.json          index of 12 subjects → 56 chapters
├── daily_quiz.json             the 10 questions of the day
└── questions/
    ├── class10_math_ch1.json   one bank per chapter
    └── …
```

Each chapter bank is referenced by `json_file` in `chapters_list.json`. The two
files must agree — the validator fails the build if `total_questions` does not
match the number of questions actually in the bank.

---

## 2. The shape

```json
{
  "chapter_id": "math_ch_01",
  "chapter_title": {
    "en": "Real Numbers",
    "bn": "বাস্তব সংখ্যা",
    "hi": "वास्तविक संख्याएँ"
  },
  "class_standard": "Class 10",
  "questions": [
    {
      "id": "math_ch1_q001",
      "question": {
        "en": "What is the HCF of 96 and 404?",
        "bn": "৯৬ এবং ৪০৪-এর গ.সা.গু. কত?",
        "hi": "96 और 404 का म.स.प. क्या है?"
      },
      "options": [
        { "en": "2",  "bn": "২",  "hi": "2" },
        { "en": "4",  "bn": "৪",  "hi": "4" },
        { "en": "8",  "bn": "৮",  "hi": "8" },
        { "en": "16", "bn": "১৬", "hi": "16" }
      ],
      "correct_index": 1,
      "explanation": {
        "en": "404 = 96 × 4 + 20, then 96 = 20 × 4 + 16, 20 = 16 × 1 + 4, 16 = 4 × 4. So HCF = 4.",
        "bn": "৪০৪ = ৯৬ × ৪ + ২০, ৯৬ = ২০ × ৪ + ১৬, ২০ = ১৬ × ১ + ৪, ১৬ = ৪ × ৪। তাই গ.সা.গু. = ৪।",
        "hi": "404 = 96 × 4 + 20, फिर 96 = 20 × 4 + 16, 20 = 16 × 1 + 4, 16 = 4 × 4। अतः म.स.प. = 4।"
      },
      "points": 10,
      "time_limit_sec": 15
    }
  ]
}
```

### Field rules

| Field | Rule |
|---|---|
| `id` | Unique across the **entire** bank, not just the chapter. Convention: `<chapter>_q001` |
| `question` | All three languages. `en` is mandatory — it is the fallback |
| `options` | 2–6 entries, each with all three languages. No two options may read the same in any language |
| `correct_index` | 0-based, must point inside `options` |
| `explanation` | Optional but strongly encouraged; shown on the review screen |
| `points` | 1–1000, default 10 |
| `time_limit_sec` | 5–300, default 15 |

Each option keeps its three languages together instead of using three parallel
arrays. That makes `correct_index` unambiguous and lets a reviewer spot a bad
translation without counting positions.

A bare string is accepted as English-only shorthand (`"question": "…"`), but
the validator warns about it — use it for drafts, not for shipped content.

---

## 3. Prompt for generating a batch with AI

Paste this, replacing the bracketed parts:

> You are writing multiple-choice questions for a **West Bengal / CBSE Class 10**
> exam-prep app used by Bengali-speaking students.
>
> Chapter: **[Real Numbers — Mathematics]**
> Write **[15]** questions.
>
> Output **only** a JSON array, no prose, no markdown fence. Each element:
>
> ```json
> {
>   "id": "[math_ch1]_q001",
>   "question": { "en": "...", "bn": "...", "hi": "..." },
>   "options": [
>     { "en": "...", "bn": "...", "hi": "..." },
>     { "en": "...", "bn": "...", "hi": "..." },
>     { "en": "...", "bn": "...", "hi": "..." },
>     { "en": "...", "bn": "...", "hi": "..." }
>   ],
>   "correct_index": 0,
>   "explanation": { "en": "...", "bn": "...", "hi": "..." },
>   "points": 10,
>   "time_limit_sec": 15
> }
> ```
>
> Rules:
> * Exactly 4 options. Only one is correct. `correct_index` is 0-based.
> * Ids run `_q001`, `_q002`, … with no gaps.
> * All three languages for every field. Translate the *meaning*, do not
>   transliterate. Keep standard board terminology — in Bangla and Hindi, a
>   technical term may stay in English if that is what the textbook uses.
> * Numbers, formulas, chemical symbols and units stay as they are.
> * Distractors must be plausible mistakes a student would actually make, not
>   obviously silly.
> * Explanations: one or two sentences, showing the reasoning, not just the
>   answer.
> * Mix difficulty: roughly 40% easy, 40% medium, 20% hard.
> * Do not repeat a question already in this chapter.

Then paste the array into the chapter file's `questions` list and run the
validator.

---

## 4. Before committing — always

```bash
python3 tool/validate_questions.py --strict
```

It catches what a quick read misses:

* a duplicate `id` across two chapters
* `correct_index` past the end of `options`
* an option list that lost a language halfway through
* two options that read identically in one language (unanswerable)
* Bangla or Hindi text left identical to the English (translation skipped)
* `total_questions` in `chapters_list.json` disagreeing with the real count

Useful variants:

```bash
python3 tool/validate_questions.py --stats    # per-chapter coverage table
python3 tool/validate_questions.py --strict   # same strict gate used in CI
```

---

## 5. Keeping counts honest

After adding questions, update `total_questions` for that chapter in
`chapters_list.json`. The chapter card shows this number, and the validator
treats a mismatch as an error rather than a warning — a card promising 20
questions and delivering 3 is worse than a card that says 3.

---

## 6. Quality bar

This is exam prep. A wrong or awkwardly translated question costs more trust
than a missing one, so:

* Verify the answer against the textbook before adding it.
* Read the Bangla and Hindi out loud. Machine-sounding phrasing is a signal
  that the terminology is off.
* Prefer fewer, correct questions over filling a chapter quickly.
* When a term genuinely has no good Bangla/Hindi equivalent, keep the English
  word — that is what the classroom does.
