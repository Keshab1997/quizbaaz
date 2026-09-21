# ⚔️ Battle Mode 1v1 Upgrade — Real Player + Smart Bot & VS Intro

> **Plan doc** · The battle arena as it works today (matching, VS intro, one
> question set per match, symmetric scoring, forfeit handling).

---

## 🎯 Goal (as requested)

1. Battle mode becomes **real 1v1**: if a real online player is found → play against them.
2. If **no real player is found** → play against a **smart bot** (existing bot, upgraded).
3. **5 questions per battle** (was 7 by default).
4. Questions are **mixed from all chapters** (different subjects in one battle).
5. **Every battle throws NEW questions** — no repeats until the pool is exhausted, then the
   cycle restarts (so a match is always possible).
6. **Real-game feel**: cricket-league style **VS intro animation** while "finding opponent",
   and a big splash when a real player is matched.
7. **Correct points system**: transparent, symmetric for both sides, speed + streak bonus.

---

## 📐 Design overview

```text
           startBattle(difficulty)
                    │
            ┌───────▼────────┐
            │    searching   │  ← Firestore queue (`battle_queue/{uid}`), max 6 s
            └───────┬────────┘
        real found  │           not found / guest / offline
            ┌───────▼────────┐           ┌───────────────────────┐
            │  LIVE ROOM     │           │      BOT MATCH        │
            │ battle_rooms/* │           │ local simulation      │
            └───────┬────────┘           └───────────┬───────────┘
                    └───────────────┬───────────────┘
                            ┌───────▼────────┐
                            │   vs intro     │  ← cricket-style VS animation
                            └───────┬────────┘
                          countdown → 5 questions → reveal → result
```

### 1. Question selection — `BattleQuestionGenerator` (new)

* Pool = **all chapters** (bundled assets **+ Firestore**, merged & deduped by id) — same
  source the daily quiz uses, so "questions come from Firestore" is honoured.
* Only chapters with `total_questions > 0` are fetched (avoids 50+ pointless reads).
* **Mixed**: chapters are shuffled, then 1 question is drawn per chapter round-robin until
  `battle_question_count` (5) is reached → guaranteed subject diversity.
* **No repeats**: every selected question id is appended to `battle_used_questions`
  (Hive, capped at 1000). Filtered out on the next battle. When fewer unseen questions
  remain than needed, the used list is cleared and the cycle restarts.
* Options are shuffled once per battle (`withShuffledOptions`) — same anti-pattern-matching
  rule as the daily quiz.
* For a **live room**, the room creator generates the set and writes it into the room
  document, so both players see identical questions.

### 2. Scoring (symmetric & transparent)

| part | value (config) | rule |
|---|---|---|
| base | `battle_base_points` = **10** | every correct answer |
| speed bonus | `battle_speed_bonus` = **10** (max) | `round(max × remaining / total)` — instant answer pays it all |
| first bonus | `battle_first_bonus` = **3** | locked in before the opponent answered |
| streak bonus | `battle_streak_bonus` = **2** × streak (cap `battle_max_streak_bonus` = **10**) | from the 2nd consecutive correct answer |
| **max / question** | 10 + 10 + 3 + 8 = **31** | player & bot use the identical formula |

* Wrong / timed-out answers pay **0** — guessing is never punished, students stay in the game.
* Bot keeps its difficulty-based accuracy (easy 45% / normal 62% / hard 78%) but its
  "think delay" now feeds the *same* time-scaled speed formula, so the scoreboard is fair.
* Once the player has locked in, a pending bot answer is compressed to ≤1.8 s so the
  round resolves quickly (no staring at "thinking…" after answering).
* Equal score at the end → **fastest total answer time wins** (same tie-break as the
  leaderboard); only a dead heat stays a draw.
* Reveal shows the breakdown: `+25 (10 base + 9 speed + 3 first + 4 streak)` plus the
  time each side took, e.g. `⏱ 2.3s`.
* Rewards scale with performance: win `40 + 2×correct` coins + 2 gems, draw
  `15 + correct`, loss `5 + correct` (a loss still pays, so students re-queue).

### 3. Matchmaking — `BattleRoomService` (new, Firestore)

Collections (+ rules in `firestore.rules`):

```text
battle_queue/{uid}    { uid, name, avatar, difficulty, created_at }   // max-age 45 s
battle_rooms/{roomId} roomId = 'room_<uidA>_<uidB>'  (sorted, deterministic)
```

Room doc shape:

```jsonc
{
  "room_id": "room_a_b",
  "difficulty": "normal",
  "status": "active" | "finished" | "abandoned",
  "questions": [ {…QuestionModel}, ×5 ],
  "state": {
    "q_index": 0,
    "phase": "lobby" | "countdown" | "question" | "reveal" | "finished",
    "countdown_until": 0, "question_until": 0, "reveal_until": 0,
    "next_q": 0
  },
  "players": {
    "a": { "uid", "name", "avatar", "score", "correct", "streak",
           "answers": { "0": {selected, correct, pts, time_bonus, streak_bonus, timed_out} },
           "ready_for_next": 0, "last_seen": 0 },
    "b": { … }
  },
  "winner": "a" | "b" | "draw" | null
}
```

* Join → heartbeat `last_seen` every 5 s; stale queue docs (> 45 s) are cleaned by the
  joiner before polling. Query: same difficulty, latest first.
* Matching: deterministic room id ⇒ both clients converge on one doc; the lexicographically
  smaller uid **creates** it (with the questions); the other waits for `questions`.
* Phase machine (both clients write only their own player fields + idempotent state):
  `countdown → question → (both answered) → reveal → (both ready) → next question → …
  → finished`; winner = higher score; tie = `draw`.
* **Forfeit**: opponent `last_seen` older than 20 s during an active question ⇒ instant win.
* **Guests / offline / Firestore error** ⇒ bot match (searching shortened to 3 s).

### 4. UI — Battle screen rework

| phase | view | notes |
|---|---|---|
| `setup` | existing difficulty picker | updated copy: 5 Qs, mixed chapters, no repeats, real/bot |
| `searching` | **NEW** radar/pulse animation, elapsed seconds, Cancel | bot fallback after `battle_search_seconds`; Cancel/Back stops timers and detaches any pending room or challenge listener |
| `found` | **NEW** cricket-style **VS intro**: two player cards slide in, glowing "VS" slams, LIVE PLAYER / BOT badge, confetti for real matches | ~3 s, then countdown |
| `countdown / question / reveal` | existing arena | opponent name+avatar (real) or bot; scoreboard + streak badges; points breakdown on reveal |
| `finished` | existing result | real opponent details, forfeit banner, coins/gems |

---

## ✅ TODO / implementation checklist

- [x] **Doc**: this plan
- [x] **AppConfig**: `battle_question_count` default 5; add `battle_base_points`,
      `battle_time_bonus_max`, `battle_streak_bonus`, `battle_search_seconds`
      (all remote-overridable via `config/app` Firestore doc)
- [x] **HiveService**: `battle_used_questions` store (load / append / cap 1000 / clear)
- [x] **BattleQuestionGenerator** (new service): pooled mixed selection, no-repeat cycle,
      chapter diversity, concurrent fetches (6 at a time)
- [x] **BattleRoomService** (new service): queue join/cleanup, deterministic room creation,
      room stream, heartbeats, forfeit detection
- [x] **BattleProvider**: new phases (`searching`, `found`), real-room state machine,
      bot fallback, symmetric scoring with streak, single-award guard per room
- [x] **Battle screen**: searching view, VS intro view, arena/result updates, i18n keys
- [x] **firestore.rules**: `battle_queue` (signed-in read; owner writes; signed-in delete so the
      claim transaction can evict both players' entries atomically) + `battle_rooms`
      (participants read/write), world-readable `winners` mirror after finish
- [x] **Strings**: new key set in en / bn / hi + `gen_strings.py` regen

### ⬜ Deployment / QA (outside this repo's code)

- [ ] `firebase deploy --only firestore:rules` (battle collections)
- [ ] Two devices, same difficulty → verified live match, same 5 questions
- [ ] One device quits mid-match → forfeit flow on the other side
- [ ] Guest + airplane mode → bot match, searching shortened
- [ ] Play 10+ battles → before any question repeats; then cycle restart
- [ ] `tool/validate_questions.py` still green (no bank touched)

---

## 💡 Ideas beyond the ask (optional backlog)

1. **ELO / rating**: store a simple rating per user (win +25 / loss −25, draw 0);
    matchmaking sorts by rating bracket first — makes wins "mean" something.
2. **Battle league**: weekly top-10 ladder with a banner like the daily champion's.
3. **Power-ups in battle**: 50-50, skip (already in shop conceptually) usable once per match.
4. **Spectator mode / replays**: store finished rooms read-only for 24 h; shareable result card.
5. **Regional ping**: `created_at + (region bias)` so two Howrah users match each other first.
