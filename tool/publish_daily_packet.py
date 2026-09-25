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

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/publish_daily_packet.py --dry-run        # show today's packet, write nothing
    python3 tool/publish_daily_packet.py                  # publish today's packet
    python3 tool/publish_daily_packet.py --date 2026-09-22 --count 10
    python3 tool/publish_daily_packet.py --chapters phys_ch_01 bio_ch_01

Publishing several days at once (what the daily cron does, so a missed run
never leaves a competition day without a packet). Days that already have a
packet are left alone unless --force is passed:

    python3 tool/publish_daily_packet.py --days 3         # today + the next two
    python3 tool/publish_daily_packet.py --days 3 --force # re-issue all three

The service account writes one collection (`daily_quiz_packets`); the console's
Owner/Editor or a custom role scoped to Firestore is enough.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

IST = timezone(timedelta(hours=5, minutes=30))
DEFAULT_COUNT = 10
SCORING_CONTRACT = 'v1'


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
def pick_questions(refs: list[tuple[str, str]], count: int, date_key: str,
                   seed_override: int | None) -> list[tuple[str, str]]:
    """Deterministic, subject-balanced pick of `count` refs for the day.

    Chapters are shuffled with the date seed, then their questions are round-
    robined so a competitive set spans subjects instead of pooling one chapter.
    The same day always re-picks the same set (the seed is the date), so a
    re-issued packet does not silently change the quiz mid-day.
    """
    by_chapter: dict[str, list[str]] = {}
    for chapter_id, qid in refs:
        by_chapter.setdefault(chapter_id, []).append(qid)

    rng = random.Random(seed_override if seed_override is not None else date_seed(date_key))
    chapters = list(by_chapter)
    rng.shuffle(chapters)
    for chapter_id in chapters:
        rng.shuffle(by_chapter[chapter_id])

    chosen: list[tuple[str, str]] = []
    index = 0
    while len(chosen) < count:
        progressed = False
        for chapter_id in chapters:
            bucket = by_chapter[chapter_id]
            if index < len(bucket):
                chosen.append((chapter_id, bucket[index]))
                progressed = True
                if len(chosen) >= count:
                    break
        if not progressed:
            break
        index += 1
    return chosen


# --------------------------------------------------------------------------- #
# Firestore
# --------------------------------------------------------------------------- #
def build_client(service_account: str | None, project: str | None):
    try:
        from google.cloud import firestore as gcf  # type: ignore
    except ImportError:
        sys.exit(
            'google-cloud-firestore is not installed.\n'
            '  pip install google-cloud-firestore\n'
            '(--dry-run works without it)'
        )
    if service_account:
        os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', service_account)
    try:
        return gcf.Client(project=project) if project else gcf.Client()
    except Exception as exc:  # noqa: BLE001 - surfaced to the operator verbatim
        sys.exit(f'could not create a Firestore client: {exc}')


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


def existing_version(client, date_key: str) -> int:
    try:
        snap = client.collection('daily_quiz_packets').document(date_key).get()
        data = snap.to_dict() or {}
        version = data.get('version')
        if isinstance(version, (int, float)) and int(version) > 0:
            return int(version)
    except Exception:  # noqa: BLE001 - unreadable old doc -> start at 1
        pass
    return 1


def packet_exists(client, date_key: str) -> bool:
    """True when a packet is already filed for that competition day."""
    try:
        return client.collection('daily_quiz_packets').document(
            date_key).get().exists
    except Exception:  # noqa: BLE001 - unreadable doc -> treat as missing
        return False


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
    parser.add_argument('--project', default=None, help='override the project id')
    parser.add_argument('--date', default=None,
                        help='competition day yyyy-MM-dd (default: today, IST)')
    parser.add_argument('--count', type=int, default=None,
                        help='questions in the packet (default: config/app '
                             'daily_question_count, else 10)')
    parser.add_argument('--chapters', action='append', default=None,
                        help='restrict the pool to these chapter ids (repeatable)')
    parser.add_argument('--seed', type=int, default=None,
                        help='override the date seed (testing only)')
    parser.add_argument('--version', type=int, default=None,
                        help='force the packet version (default: existing + 1)')
    parser.add_argument('--days', type=int, default=1,
                        help='publish this many consecutive competition days, '
                             'starting at --date (default: 1). Days that '
                             'already have a packet are skipped.')
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

    _, chapters = load_catalog(root)
    only = set(args.chapters) if args.chapters else None
    date_key = args.date or competition_date_key()
    count = args.count

    refs = bundled_refs(root, chapters, only)
    if not refs:
        sys.exit('no bundled questions found — nothing to publish. '
                 'Add questions to a chapter bank first.')

    client = None if args.dry_run else build_client(args.service_account, args.project)
    if count is None:
        count = configured_count(client) if client else DEFAULT_COUNT

    if len(refs) < count:
        sys.exit(f'only {len(refs)} bundled question(s) but --count {count}; '
                 f'publish fewer or author more questions.')

    days = max(1, args.days)
    date_keys = [shift_day(date_key, i) for i in range(days)]

    documents: list[tuple[str, dict]] = []
    for day in date_keys:
        # A day that already has a packet keeps it: re-issuing bumps the
        # version, which makes every device throw away its resolved set, and
        # a re-pick with the same seed returns the same questions anyway.
        if client is not None and not args.force and packet_exists(client, day):
            print(f'skip {day}: a packet is already published '
                  f'(use --force to re-issue it)')
            continue

        chosen = pick_questions(refs, count, day, args.seed)
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
        print('nothing to publish — every requested day already has a packet')
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