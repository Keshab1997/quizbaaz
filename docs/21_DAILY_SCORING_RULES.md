# 21 · Daily competition: scoring, packets and the leaderboard

How a daily quiz score becomes a leaderboard row — and the two things that
silently stop it from ever getting there.

Read this before touching `lib/data/services/daily_score_lock.dart`,
`lib/data/providers/user_provider.dart` (`recordQuizResult`) or
`tool/publish_daily_packet.py`.

---

## 1. The rule: one counted score per player per day

> **The first ranked run of a competition day is the score.**
> Every later run that day is played for coins, XP, history and the streak —
> and is ignored by the leaderboard, even with a better score.

It used to be "best run of the day wins". That made the leaderboard a replay
grind (whoever had time to sit through it three times), made the player's own
row jump around all evening, and made the score impossible to explain: *"I got
90, why does it say 60?"* — because the 60 was counted first.

Two exceptions, both deliberate:

| Case | What happens |
| --- | --- |
| **Score Shield** (shop item, 12 gems) | Reopens a locked day for **one** replacement run. The next ranked daily run replaces the locked score and re-locks the day. One per day, however many shields the player owns. |
| **Unranked (practice) run** | Counts for nothing on the leaderboard. See §2 — this is the case that makes scores disappear. |

The trusted backend enforces the same shape independently:
`submitDailyResult` (`functions/src/daily.ts`) is idempotent per day through
`users/{uid}/daily_claims/{date}` — the first submission writes the row, every
later one returns `already-credited` and leaves it alone. A Score Shield retry
is therefore mirrored by the client's own push, never by a second server
credit.

### Where it lives

| Piece | File |
| --- | --- |
| Rule + Hive markers | `lib/data/services/daily_score_lock.dart` |
| Applied on a finished run | `UserProvider.recordQuizResult` → `_settleDailyScore` |
| Server credit (once per day) | `QuizProvider._grantRewards` → `TrustedOpsService.submitDailyResult` |
| Server write | `functions/src/daily.ts` |
| Player-facing copy | `QuizResultScreen._buildRankingNotice` + the shield card |

Hive markers, all keyed by the **competition** day (`CompetitionClock`), so a
player who travels cannot unlock a second attempt by changing timezone (R12):

```text
daily_best_score_<day>          the counted score   ┐ kept under the old names
daily_best_time_<day>           its time (tie-break)┘ so a mid-day update does
                                                     not orphan today's score
daily_score_locked_<day>        the day has a counted score
daily_score_attempts_<day>      ranked runs finished today
daily_score_retry_<day>         a shield has reopened the day
daily_score_retries_used_<day>  shields spent on this day (0 or 1)
```

`DailyScoreOutcome` (`counted` · `replaced` · `ignored` · `notApplicable`) is
what the result screen renders, so the player is never left guessing whether
their run counted.

---

## 2. Ranked vs practice: why a score sometimes never arrives

A daily run is **ranked** only when the day has an approved, complete, open
packet in Firestore:

```text
daily_quiz_packets/{yyyy-MM-dd}    (competition timezone, UTC+5:30)
```

written by the trusted backend only (`firestore.rules`: `allow write: if
false`). Without one, every device falls back to a locally assembled practice
set: the quiz plays normally, but the score is deliberately **never** submitted
— the questions differ per device, so ranking them would be fake (R12).

**Symptom:** nobody's score appears on the leaderboard, all day.
**Cause:** no packet was published for that date.

### Publishing

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
python3 tool/publish_daily_packet.py --dry-run          # show today's packet
python3 tool/publish_daily_packet.py                    # publish today
python3 tool/publish_daily_packet.py --days 3           # today + the next two
python3 tool/publish_daily_packet.py --days 3 --force   # re-issue them
```

Selection is deterministic per day (the date is the seed) and is drawn from the
**bundled** banks only, so an offline device resolves exactly the same question
ids as an online one. Days that already have a packet are skipped unless
`--force` is passed (re-issuing bumps `version`, which makes every device throw
its resolved set away).

### The cron that keeps it alive

`.github/workflows/daily-packet.yml` runs **18:30 UTC = 00:00 IST** and
publishes **three** competition days at a time, so one missed run still leaves
two days of packets standing.

One-time setup: add the repository secret **`FIREBASE_PACKET_WRITER_SA`**
(Settings → Secrets and variables → Actions) holding the JSON of a service
account allowed to write `daily_quiz_packets`. The workflow fails loudly with
setup instructions while the secret is missing — a silent no-op here would look
exactly like "the leaderboard is broken".

Run it by hand any time: Actions → *Daily Quiz Packet* → **Run workflow**
(`days`, `force`).

---

## 3. Sanity checks

```bash
flutter test test/daily_score_lock_test.dart   # the one-score-per-day rule
flutter test test/daily_packet_test.dart       # ranked vs practice resolution
python3 tool/publish_daily_packet.py --dry-run # what tomorrow's packet looks like
```

Checking a live day:

1. `python3 tool/publish_daily_packet.py --dry-run --date <today>` — is there a
   packet, and is it approved?
2. Play the daily quiz once: the result screen must say *"🏆 Today's score N is
   saved on the leaderboard"*.
3. Play it again: it must say *"🔒 Today's leaderboard score is locked at N"*.
4. Firestore → `leaderboard/<today>/scores/<uid>` — one row, the first score.

---

## 4. Follow-ups

- **Champion publishing** (yesterday's winners, gifts) is still a manual admin
  step — see `ADMIN_TODO.md`.
- **Score Shield purchase copy** lives in `models/shop_item.dart` as plain
  English; the shop screen itself is localised, the catalogue is not.
