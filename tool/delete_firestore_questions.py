#!/usr/bin/env python3
"""Delete specific admin-authored questions from Firestore.

An escape hatch for broken questions — an untranslated option, a wrong answer
key, a duplicate — that should be removed rather than shipped. The normal way
to remove a question is the admin panel; this tool exists so the same delete can
be run from CI, against a fixed list of ids, when the panel is not at hand.

It touches exactly the ids you give it and nothing else. Dry run by default:
with no `--apply` it only reports what it *would* delete, with the question's
English stem, so the target can be eyeballed before anything is destroyed.

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/delete_firestore_questions.py \\
        --ids chhaya_prakashani_ch_01/chhaya_prakashani_ch_01_q417
    python3 tool/delete_firestore_questions.py --ids-file ids.txt --apply

    # several ids at once, comma or newline separated:
    python3 tool/delete_firestore_questions.py --ids "a_ch_01/a_ch_01_q001,b_ch_02/b_ch_02_q058"

An id is `chapter_id/question_id`; the document lives at
`question_banks/{chapter_id}/questions/{question_id}`.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_PROJECT = 'quizbaaz-740bd'
BANKS_COLLECTION = 'question_banks'
QUESTIONS_SUBCOLLECTION = 'questions'


def default_project(root: Path) -> str | None:
    try:
        data = json.loads((root / '.firebaserc').read_text(encoding='utf-8'))
        project = data.get('projects', {}).get('default')
        return project if isinstance(project, str) and project else None
    except Exception:  # noqa: BLE001
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
    if credentials_path and Path(credentials_path).exists():
        try:
            sa = json.loads(Path(credentials_path).read_text(encoding='utf-8'))
            sa_project = sa.get('project_id')
            if sa_project and sa_project != project:
                sys.exit(
                    f'the service account belongs to project "{sa_project}", '
                    f'but the app reads content from "{project}". Use a service '
                    f'account for "{project}".'
                )
        except json.JSONDecodeError:
            sys.exit(f'{credentials_path} is not a service-account JSON file.')
    try:
        return gcf.Client(project=project)
    except Exception as exc:  # noqa: BLE001
        sys.exit(f'could not create a Firestore client for {project}: {exc}')


def parse_ids(raw_values: list[str], ids_file: str | None) -> list[tuple[str, str]]:
    chunks: list[str] = list(raw_values)
    if ids_file:
        chunks.append(Path(ids_file).read_text(encoding='utf-8'))
    out: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for chunk in chunks:
        for piece in chunk.replace('\n', ',').split(','):
            piece = piece.strip()
            if not piece:
                continue
            if '/' not in piece:
                sys.exit(f'bad id "{piece}" — expected chapter_id/question_id')
            chapter_id, _, question_id = piece.partition('/')
            chapter_id, question_id = chapter_id.strip(), question_id.strip()
            if not chapter_id or not question_id:
                sys.exit(f'bad id "{piece}" — expected chapter_id/question_id')
            key = (chapter_id, question_id)
            if key not in seen:
                seen.add(key)
                out.append(key)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Delete specific admin-authored questions from Firestore.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--repo-root', default=None)
    parser.add_argument('--service-account', default=None)
    parser.add_argument('--project', default=None)
    parser.add_argument('--ids', action='append', default=[],
                        help='chapter_id/question_id (comma or newline '
                             'separated; repeatable)')
    parser.add_argument('--ids-file', default=None,
                        help='a file of chapter_id/question_id lines')
    parser.add_argument('--apply', action='store_true',
                        help='actually delete (default: dry run)')
    parser.add_argument('-q', '--quiet', action='store_true')
    args = parser.parse_args()

    root = Path(args.repo_root).resolve() if args.repo_root else \
        Path(__file__).resolve().parent.parent
    project = args.project or default_project(root) or DEFAULT_PROJECT

    targets = parse_ids(args.ids, args.ids_file)
    if not targets:
        sys.exit('no ids given — pass --ids or --ids-file')

    client = build_client(args.service_account, project)

    deleted = 0
    missing = 0
    for chapter_id, question_id in targets:
        doc = (client.collection(BANKS_COLLECTION).document(chapter_id)
               .collection(QUESTIONS_SUBCOLLECTION).document(question_id))
        snap = doc.get()
        if not snap.exists:
            print(f'  missing   {chapter_id}/{question_id}')
            missing += 1
            continue
        data = snap.to_dict() or {}
        stem = (data.get('question') or {})
        stem_en = stem.get('en') if isinstance(stem, dict) else ''
        stem_en = (stem_en or '').strip().replace('\n', ' ')[:70]
        if args.apply:
            doc.delete()
            deleted += 1
            print(f'  DELETED   {chapter_id}/{question_id}  :: {stem_en}')
        else:
            print(f'  would del {chapter_id}/{question_id}  :: {stem_en}')

    if args.apply:
        print(f'\nDeleted {deleted} question(s); {missing} not found.')
    else:
        print(f'\nDry run — {len(targets) - missing} question(s) found, '
              f'{missing} missing. Re-run with --apply to delete.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
