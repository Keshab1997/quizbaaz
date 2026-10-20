#!/usr/bin/env python3
"""Publish the day's daily-quiz packet to Firestore.

Why this exists
---------------
Since R12 (`0e73e69`, Sep 2026) the daily quiz only writes to the leaderboard
when the run is **ranked**, and a run is ranked only when an approved, complete
competition packet sits in `daily_quiz_packets/{yyyy-MM-dd}` (competition
timezone, UTC+5:30). The app has no client path to publish one
(`firestore.rules`: `allow write: if false`), and until this script there was
no publisher at all — so *every* daily run fell back to an unranked practice
set and no score ever reached the leaderboard.

This tool builds that packet from the **bundled** question banks (the offline
floor every install carries), so any device — online or offline — can resolve
the same question ids and the run is comparable for everybody (R12). A packet
built from Firestore-only admin questions would resolve on networked devices
and silently fall back to unranked on offline ones, which is why the pool is
bundle-only unless `--include-firestore` is passed.

Selection is deterministic per competition day (same seed the app shares), so
re-publishing the same day re-issues the *same* set — a re-issue only bumps
`version` so devices with a cached resolved set re-resolve it.

Keeping the leaderboard alive
-----------------------------
A packet is only useful while the app can still resolve every id it names. The
app resolves a packet through the **student-visible** catalogue: it drops
chapters an admin deleted (the `config/content_deletions` registry), chapters
an admin disabled (`question_categories/*/chapters/*.is_enabled == false`) and
questions an admin deleted (`question_banks/{chapterId}.deleted_question_ids`).
A packet published three days early can therefore rot: the day is only skipped
when a packet *exists*, not when it still *resolves*, so one admin delete in
between used to turn a whole competition day unranked and empty the
leaderboard — silently.

This tool closes that hole two ways:

* the selection pool is filtered to the same visible content the app uses, so a
  freshly built packet never names a hidden chapter or question; and
* an existing packet is re-issued (bumped `version`) whenever it no longer
  matches the current visible pool — not blindly skipped.

The write also targets the app's project explicitly (`.firebaserc`), so a
service account from the wrong project fails loudly instead of filing packets
somewhere no install can read.

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/publish_daily_packet.py --dry-run        # show today's packet, write nothing
    python3 tool/publish_daily_packet.py                  # publish today's packet
    python3 tool/publish_daily_packet.py --date 2026-09-22 --count 10
    python3 tool/publish_daily_packet.py --chapters phys_ch_01 bio_ch_01

Publishing several days at once (what the daily cron does, so a missed run
never leaves a competition day without a packet). A day that already has a
*valid* packet is left alone; a day whose packet no longer resolves is
re-issued, and --force re-issues every requested day:

    python3 tool/publish_daily_packet.py --days 3         # today + the next two
    python3 tool/publish_daily_packet.py --days 3 --force # re-issue all three

The service account writes one collection (`daily_quiz_packets`); the console's
Owner/Editor or a custom role scoped to Firestore is enough. It also needs read
access to `config/content_deletions`, `question_categories` and `question_banks`
to keep hidden content out of the packet.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

IST = timezone(timedelta(hours=5, minutes=30))
DEFAULT_COUNT = 10
SCORING_CONTRACT = 'v1'

#: The epoch the day-advancing selection cursor counts from. Fixed, so the
#: same competition day always yields the same set (a re-issued packet must
#: not change the quiz mid-day).
SELECTION_EPOCH = (2026, 1, 1)

#: How the day's `count` slots are split across chapters:
#:   'balanced'     one slot per chapter, round-robined across subjects. A
#:                  chapter's share is independent of how many questions its
#:                  bank holds (the historical shape).
#:   'blended'      slots proportional to sqrt(bank size): a big bank shows up
#:                  often without crowding every small subject out (default).
#:   'proportional' slots strictly proportional to bank size.
WEIGHTINGS = ('balanced', 'blended', 'proportional')

#: The Firebase project the app reads `daily_quiz_packets` from. A packet filed
#: anywhere else is invisible to every install (mirrors `.firebaserc`).
DEFAULT_PROJECT = 'quizbaaz-740bd'


# --------------------------------------------------------------------------- #
# competition clock (mirrors lib/data/services/competition_clock.dart)
# --------------------------------------------------------------------------- #
def competition_date_key(now: datetime | None = None) -> str:
    """The competition day `yyyy-MM-dd` that [now] falls in (UTC+5:30)."""
    moment = now or datetime.now(timezone.utc)
    return (moment + timedelta(hours=5, minutes=30)).strftime('%Y-%m-%d')


def shift_day(date_key: str, days: int) -> str:
    """The competition day `days` after/before `date_key` (yyyy-MM-dd)."""
    year, month, day = (int(part) for part in date_key.split('-'))
    moment = datetime(year, month, day, tzinfo=timezone.utc)
    return (moment + timedelta(days=days)).strftime('%Y-%m-%d')


def deadline_ms(date_key: str) -> int:
    """Instant (ms since epoch, UTC) the competition day closes.

    Matches CompetitionClock.dayEnd: start of the *next* competition day.
    """
    year, month, day = (int(part) for part in date_key.split('-'))
    day_start = datetime(year, month, day, tzinfo=timezone.utc) - timedelta(
        hours=5, minutes=30,
    )
    return int((day_start + timedelta(days=1)).timestamp() * 1000)


def date_seed(date_key: str) -> int:
    """Integer seed for the date, e.g. 20260922 — mirrors _dateSeed."""
    return int(date_key.replace('-', ''))


# --------------------------------------------------------------------------- #
# bundled banks
# --------------------------------------------------------------------------- #
def load_catalog(root: Path) -> tuple[dict, dict]:
    """Return (catalog, chapter_id -> {json_file, category_id})."""
    path = root / 'assets' / 'data' / 'chapters_list.json'
    if not path.exists():
        sys.exit(f'catalogue not found: {path}')
    catalog = json.loads(path.read_text(encoding='utf-8'))
    by_id: dict[str, dict] = {}
    for category in catalog.get('categories', []):
        for chapter in category.get('chapters', []):
            cid = chapter.get('chapter_id')
            if not cid:
                continue
            by_id[cid] = {
                'json_file': chapter.get('json_file', ''),
                'category_id': category.get('category_id', ''),
            }
    return catalog, by_id


def read_bank(path: Path) -> dict:
    if not path.exists():
        return {'questions': []}
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as exc:
        sys.exit(f'broken JSON in {path}: {exc}')


def bundled_refs(root: Path, chapters: dict[str, dict], only: set[str] | None):
    """[(chapter_id, question_id), ...] from the bundled banks.

    A chapter contributes only existing, id-carrying questions. Chapters whose
    bank has no questions are skipped (a zero-question chapter means "not
    authored yet" — never a placeholder).
    """
    refs: list[tuple[str, str]] = []
    for chapter_id, info in chapters.items():
        if only and chapter_id not in only:
            continue
        json_file = info.get('json_file') or ''
        if not json_file:
            continue
        bank = read_bank(root / json_file)
        for question in bank.get('questions') or []:
            qid = str(question.get('id', '')).strip()
            if not qid or not str((question.get('question') or {}).get('en', '')).strip():
                continue
            refs.append((chapter_id, qid))
    return refs


# --------------------------------------------------------------------------- #
# selection
# --------------------------------------------------------------------------- #
def _day_number(date_key: str) -> int:
    """Whole days from SELECTION_EPOCH to `date_key` (may be negative)."""
    year, month, day = (int(part) for part in date_key.split('-'))
    epoch = datetime(*SELECTION_EPOCH, tzinfo=timezone.utc)
    moment = datetime(year, month, day, tzinfo=timezone.utc)
    return (moment - epoch).days


def _chapter_weight(size: int, weighting: str) -> float:
    if weighting == 'proportional':
        return float(size)
    if weighting == 'blended':
        return math.sqrt(size)
    return 1.0


def _slots_by_weight(sizes: dict[str, int], count: int,
                     weighting: str) -> dict[str, int]:
    """Split `count` slots across chapters by weight (largest-remainder)."""
    weights = {cid: _chapter_weight(n, weighting) for cid, n in sizes.items()}
    total = sum(weights.values())
    if total <= 0:
        return {cid: 0 for cid in sizes}
    raw = {cid: count * w / total for cid, w in weights.items()}
    slots = {cid: int(math.floor(v)) for cid, v in raw.items()}
    leftover = count - sum(slots.values())
    order = sorted(sizes,
                   key=lambda cid: (raw[cid] - slots[cid], weights[cid]),
                   reverse=True)
    for cid in order[:max(0, leftover)]:
        slots[cid] += 1
    # never ask a chapter for more questions than it holds
    for cid in sizes:
        slots[cid] = min(slots[cid], sizes[cid])
    return slots


def pick_questions(refs: list[tuple[str, str]], count: int, date_key: str,
                   seed_override: int | None,
                   weighting: str = 'blended') -> list[tuple[str, str]]:
    """Deterministic pick of `count` refs for the day, spread across subjects.

    Two things matter here, and the old round-robin got both wrong:

    * **How big a share each chapter gets.** The old code gave every chapter
      exactly one question, so a chapter holding 10 questions and one holding
      500 competed equally — a subject with the bulk of the bank could never
      take more than its chapter count of the day's slots. Slots are now
      allocated by bank size (`weighting`), so a large bank is represented
      without a small subject being dropped.

    * **Which question of each chapter.** The old code always took `bucket[0]`
      of a freshly shuffled list, so the same small-bank question resurfaced
      every few days. Each chapter now has one fixed order and a cursor that
      advances every competition day, so a chapter's questions are walked in
      turn and a question is not re-picked until its bank wraps.

    The same day always yields the same set (the seed and the cursor are both
    the date), so a re-issued packet does not change the quiz mid-day.
    """
    if weighting not in WEIGHTINGS:
        raise ValueError(f'unknown weighting {weighting!r}; expected one of '
                         f'{WEIGHTINGS}')

    by_chapter: dict[str, list[str]] = {}
    for chapter_id, qid in refs:
        by_chapter.setdefault(chapter_id, []).append(qid)

    # One fixed order per chapter, seeded by the chapter id alone (not the
    # date), so the cursor below walks one stable sequence instead of a list
    # that is reshuffled every day — the reshuffle is what let the same
    # question resurface day after day.
    for chapter_id in sorted(by_chapter):
        random.Random(f'quizbaaz:{chapter_id}').shuffle(by_chapter[chapter_id])

    rng = random.Random(seed_override if seed_override is not None else date_seed(date_key))
    sizes = {chapter_id: len(qs) for chapter_id, qs in by_chapter.items()}
    day = _day_number(date_key)

    if weighting == 'balanced':
        # The historical shape: one question per chapter, across the subjects
        # the date seed brings to the front.
        chapters = sorted(by_chapter)
        rng.shuffle(chapters)
        plan = [(chapter_id, 1) for chapter_id in chapters[:count]]
    else:
        slots = _slots_by_weight(sizes, count, weighting)
        plan = [(chapter_id, slots[chapter_id])
                for chapter_id in sorted(by_chapter)
                if slots.get(chapter_id, 0) > 0]

    chosen: list[tuple[str, str]] = []
    for chapter_id, take in plan:
        bucket = by_chapter[chapter_id]
        width = len(bucket)
        # Advance the window by `take` every competition day, so consecutive
        # days step through the chapter's questions instead of re-picking the
        # same head; a question cannot recur until the whole bank has been
        # walked (width / take days).
        start = (day * take) % width
        for offset in range(take):
            chosen.append((chapter_id, bucket[(start + offset) % width]))

    # Order within the day is not part of the contract (the client presents in
    # packet order, and the packet stores this order) — shuffle so the set is
    # not always grouped by chapter.
    rng.shuffle(chosen)
    return chosen[:count]


# --------------------------------------------------------------------------- #
# visibility (what the app will actually show)
# --------------------------------------------------------------------------- #
def fetch_hidden_content(client) -> tuple[set[str], set[str], set[str]]:
    """(deleted_chapters, deleted_categories, disabled_chapters) from Firestore.

    Mirrors the app's student view: `config/content_deletions` removes chapters
    and whole subjects, and a chapter doc with `is_enabled: false` is dropped by
    `QuizRepository.filterForStudents`. Best-effort — an unreadable registry
    only means we fall back to the bundled view, never that we fail the run.
    """
    deleted_chapters: set[str] = set()
    deleted_categories: set[str] = set()
    disabled_chapters: set[str] = set()

    try:
        snap = client.collection('config').document('content_deletions').get()
        data = snap.to_dict() or {}
        deleted_chapters = {
            str(item).strip()
            for item in (data.get('deleted_chapter_ids') or [])
            if str(item).strip()
        }
        deleted_categories = {
            str(item).strip()
            for item in (data.get('deleted_category_ids') or [])
            if str(item).strip()
        }
    except Exception as exc:  # noqa: BLE001 - best-effort, surfaced as a warning
        print(f'warn: content deletions unreadable — {exc}')

    try:
        for doc in client.collection_group('chapters').get():
            data = doc.to_dict() or {}
            if data.get('is_enabled') is False:
                disabled_chapters.add(doc.id)
    except Exception as exc:  # noqa: BLE001
        print(f'warn: chapter visibility unreadable — {exc}')

    return deleted_chapters, deleted_categories, disabled_chapters


def fetch_deleted_question_ids(client, chapter_ids: set[str]) -> dict[str, set[str]]:
    """chapter_id -> deleted question ids, for the chapters in play only."""
    out: dict[str, set[str]] = {}
    for chapter_id in chapter_ids:
        try:
            snap = client.collection('question_banks').document(chapter_id).get()
            data = snap.to_dict() or {}
            raw = data.get('deleted_question_ids')
            if isinstance(raw, list):
                out[chapter_id] = {
                    str(item).strip() for item in raw if str(item).strip()
                }
        except Exception as exc:  # noqa: BLE001
            print(f'warn: deleted ids unreadable for {chapter_id} — {exc}')
    return out


def visible_refs(refs, chapters, hidden):
    """Drop the refs the app would hide, so a packet always resolves."""
    deleted_chapters, deleted_categories, disabled_chapters, deleted_questions = hidden
    out: list[tuple[str, str]] = []
    for chapter_id, question_id in refs:
        if chapter_id in deleted_chapters or chapter_id in disabled_chapters:
            continue
        category_id = chapters.get(chapter_id, {}).get('category_id', '')
        if category_id and category_id in deleted_categories:
            continue
        if question_id in deleted_questions.get(chapter_id, ()):
            continue
        out.append((chapter_id, question_id))
    return out


# --------------------------------------------------------------------------- #
# Firestore
# --------------------------------------------------------------------------- #
def default_project(root: Path) -> str | None:
    """The default Firebase project from `.firebaserc`, if it has one."""
    try:
        data = json.loads((root / '.firebaserc').read_text(encoding='utf-8'))
        project = data.get('projects', {}).get('default')
        return project if isinstance(project, str) and project else None
    except Exception:  # noqa: BLE001 - missing/broken file -> caller default
        return None


def build_client(service_account: str | None, project: str):
    try:
        from google.cloud import firestore as gcf  # type: ignore
    except ImportError:
        sys.exit(
            'google-cloud-firestore is not installed.\n'
            '  pip install google-cloud-firestore\n'
            '(--dry-run works without it)'
        )

    credentials_path = service_account or os.environ.get(
        'GOOGLE_APPLICATION_CREDENTIALS')
    if service_account:
        os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', service_account)

    # A service account from another project would file packets where no install
    # can read them — the leaderboard would be empty while every run "succeeds".
    # Fail loudly instead.
    if credentials_path and Path(credentials_path).exists():
        try:
            sa = json.loads(Path(credentials_path).read_text(encoding='utf-8'))
            sa_project = sa.get('project_id')
            if sa_project and sa_project != project:
                sys.exit(
                    f'the service account belongs to project "{sa_project}", '
                    f'but the app reads daily_quiz_packets from "{project}". '
                    f'Packets filed under "{sa_project}" are invisible to every '
                    f'install. Use a service account for "{project}".'
                )
        except json.JSONDecodeError:
            sys.exit(f'{credentials_path} is not a service-account JSON file.')

    try:
        return gcf.Client(project=project)
    except Exception as exc:  # noqa: BLE001 - surfaced to the operator verbatim
        sys.exit(f'could not create a Firestore client for {project}: {exc}')


def configured_count(client) -> int:
    """The published config's daily question count, or DEFAULT_COUNT."""
    try:
        snap = client.collection('config').document('app').get()
        data = snap.to_dict() or {}
        value = data.get('daily_question_count')
        if isinstance(value, (int, float)) and int(value) > 0:
            return int(value)
    except Exception:  # noqa: BLE001 - offline/config-missing -> default
        pass
    return DEFAULT_COUNT


def existing_packet(client, date_key: str) -> dict | None:
    """The packet document already filed for a day, or None."""
    try:
        snap = client.collection('daily_quiz_packets').document(date_key).get()
        if not snap.exists:
            return None
        return snap.to_dict() or {}
    except Exception:  # noqa: BLE001 - unreadable old doc -> treat as missing
        return None


def existing_version(client, date_key: str) -> int:
    """The filed packet's version, or 0 so the first publish is version 1."""
    packet = existing_packet(client, date_key)
    if not packet:
        return 0
    version = packet.get('version')
    if isinstance(version, (int, float)) and int(version) > 0:
        return int(version)
    return 0


def packet_still_valid(packet: dict | None, valid_refs: set[tuple[str, str]],
                       count: int) -> bool:
    """True when an already-published packet still resolves on the app.

    A packet is only worth keeping when it is approved, carries the announced
    number of questions and every id it names is still in the visible pool. Any
    other case (unapproved, short, a chapter or question since hidden) has to be
    re-issued, or the whole day silently goes unranked.
    """
    if not packet:
        return False
    if packet.get('approved') is not True:
        return False
    questions = packet.get('questions')
    if not isinstance(questions, list) or len(questions) != count:
        return False
    for entry in questions:
        if not isinstance(entry, dict):
            return False
        key = (str(entry.get('chapter_id', '')), str(entry.get('question_id', '')))
        if key not in valid_refs:
            return False
    return True


def publish(client, document: dict, date_key: str) -> None:
    client.collection('daily_quiz_packets').document(date_key).set(document)


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    parser = argparse.ArgumentParser(
        description='Publish the daily-quiz packet for a competition day.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--repo-root', default=None,
                        help='repo root (default: the parent of tool/)')
    parser.add_argument('--service-account', default=None,
                        help='service-account JSON (or set '
                             'GOOGLE_APPLICATION_CREDENTIALS)')
    parser.add_argument('--project', default=None,
                        help='Firebase project to write (default: the '
                             '.firebaserc default, else ' + DEFAULT_PROJECT + ')')
    parser.add_argument('--date', default=None,
                        help='competition day yyyy-MM-dd (default: today, IST)')
    parser.add_argument('--count', type=int, default=None,
                        help='questions in the packet (default: config/app '
                             'daily_question_count, else 10)')
    parser.add_argument('--chapters', action='append', default=None,
                        help='restrict the pool to these chapter ids (repeatable)')
    parser.add_argument('--seed', type=int, default=None,
                        help='override the date seed (testing only)')
    parser.add_argument('--weighting', choices=WEIGHTINGS, default='blended',
                        help='how the day\'s slots are split across chapters '
                             '(default: blended — slots proportional to '
                             'sqrt(bank size))')
    parser.add_argument('--version', type=int, default=None,
                        help='force the packet version (default: existing + 1)')
    parser.add_argument('--days', type=int, default=1,
                        help='publish this many consecutive competition days, '
                             'starting at --date (default: 1). Days that '
                             'already have a valid packet are skipped.')
    parser.add_argument('--force', action='store_true',
                        help='re-issue days that already have a packet '
                             '(bumps the version so devices re-resolve the '
                             'set)')
    parser.add_argument('--dry-run', action='store_true',
                        help='print the packet and write nothing')
    parser.add_argument('--json-report', default=None,
                        help='write a machine-readable summary here')
    parser.add_argument('-q', '--quiet', action='store_true')
    args = parser.parse_args()

    root = Path(args.repo_root).resolve() if args.repo_root else \
        Path(__file__).resolve().parent.parent
    if not (root / 'assets' / 'data').is_dir():
        sys.exit(f'{root} does not look like the QuizBaaz repo root '
                 f'(no assets/data) — pass --repo-root')

    project = args.project or default_project(root) or DEFAULT_PROJECT

    _, chapters = load_catalog(root)
    only = set(args.chapters) if args.chapters else None
    date_key = args.date or competition_date_key()
    count = args.count

    refs = bundled_refs(root, chapters, only)
    if not refs:
        sys.exit('no bundled questions found — nothing to publish. '
                 'Add questions to a chapter bank first.')

    client = None if args.dry_run else build_client(args.service_account, project)

    # Drop everything the app would hide, so the packet always resolves.
    if client is not None:
        deleted_chapters, deleted_categories, disabled_chapters = \
            fetch_hidden_content(client)
        deleted_questions = fetch_deleted_question_ids(
            client, {chapter_id for chapter_id, _ in refs})
        before = len(refs)
        refs = visible_refs(
            refs,
            chapters,
            (deleted_chapters, deleted_categories, disabled_chapters,
             deleted_questions),
        )
        hidden = before - len(refs)
        if hidden and not args.quiet:
            print(f'excluded {hidden} bundled question(s) hidden by admin '
                  f'deletions/disable')
        if not refs:
            sys.exit('every bundled question is hidden by admin deletions — '
                     'nothing left to publish. Re-enable content or author '
                     'more questions.')

    if count is None:
        count = configured_count(client) if client else DEFAULT_COUNT

    if len(refs) < count:
        sys.exit(f'only {len(refs)} visible bundled question(s) but --count '
                 f'{count}; publish fewer or author more questions.')

    valid_refs = {(chapter_id, question_id) for chapter_id, question_id in refs}

    days = max(1, args.days)
    date_keys = [shift_day(date_key, i) for i in range(days)]

    documents: list[tuple[str, dict]] = []
    for day in date_keys:
        # A day that already has a packet that still *resolves* keeps it:
        # re-issuing bumps the version, which makes every device throw away its
        # resolved set, and a re-pick with the same seed returns the same
        # questions anyway. A packet that no longer resolves (hidden content,
        # short, unapproved) is re-issued instead of skipped — otherwise the
        # day silently goes unranked.
        if client is not None and not args.force:
            existing = existing_packet(client, day)
            if packet_still_valid(existing, valid_refs, count):
                print(f'skip {day}: a valid packet is already published '
                      f'(use --force to re-issue it)')
                continue
            if existing is not None:
                print(f're-issuing {day}: the published packet no longer '
                      f'resolves against the visible pool')

        chosen = pick_questions(refs, count, day, args.seed, args.weighting)
        version = args.version if args.version is not None else (
            1 if args.dry_run else existing_version(client, day) + 1)

        documents.append((day, {
            'date_key': day,
            'version': version,
            'questions': [
                {'chapter_id': cid, 'question_id': qid}
                for cid, qid in chosen
            ],
            'count': len(chosen),
            'deadline_ms': deadline_ms(day),
            'scoring_contract': SCORING_CONTRACT,
            'approved': True,
            'published_at': int(datetime.now(timezone.utc).timestamp() * 1000),
        }))

    if not documents:
        print('nothing to publish — every requested day already has a valid '
              'packet')
        return 0

    if args.json_report:
        payload = documents[0][1] if len(documents) == 1 else [
            document for _, document in documents
        ]
        Path(args.json_report).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + '\n',
            encoding='utf-8',
        )

    if args.dry_run:
        for day, document in documents:
            if len(documents) == 1:
                print(json.dumps(document, ensure_ascii=False, indent=2))
            banned = sorted({q['chapter_id'] for q in document['questions']})
            print(f'{day}: version={document["version"]}, '
                  f'count={document["count"]}, '
                  f'deadline_ms={document["deadline_ms"]}')
            if len(banned) == 1:
                print(f'  note: the whole packet came from one chapter '
                      f'({banned[0]})')
            elif not args.quiet:
                print('  chapters: ' + ', '.join(banned))
        return 0

    for day, document in documents:
        publish(client, document, day)
        print(f'published daily_quiz_packets/{day} '
              f'(version {document["version"]}, '
              f'{document["count"]} questions)')
        if not args.quiet:
            chapters_used = sorted({q['chapter_id']
                                    for q in document['questions']})
            print('chapters: ' + ', '.join(chapters_used))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
