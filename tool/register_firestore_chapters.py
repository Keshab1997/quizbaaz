#!/usr/bin/env python3
"""Register admin-created subjects and chapters in the bundled catalogue.

Why this exists
---------------
The admin panel writes subjects and chapters to Firestore
(`question_categories/{categoryId}` and its `chapters` subcollection). The app
merges those into the catalogue it shows, so a new subject appears for students
immediately — but the *bundled* catalogue (`assets/data/chapters_list.json`) and
its bank files do not know about it.

That is fine for live play, but two things only ever read the bundle:

* `tool/pull_firestore_questions.py` skips any chapter that is not in
  `chapters_list.json` ("add it to the catalogue to bundle it"), and
* `tool/publish_daily_packet.py` builds the daily competition packet from the
  bundle alone.

So a subject created in the admin panel never reaches the bundle, never gets its
questions pulled, and never appears in the daily packet. This tool is the bridge:

    Firestore question_categories (+ chapters)   (the admin's subject/chapter)
              |
              |  this tool  (Firestore -> repo)
              v
    assets/data/chapters_list.json    entry added (subject and chapter)
    assets/data/questions/<id>.json   skeleton bank created (questions: [])

It only ever *adds* what is missing and fills a missing `json_file`. Existing
catalogue entries keep their hand-authored titles, icons and order. Run
`tool/pull_firestore_questions.py` afterwards to fill the new banks.

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/register_firestore_chapters.py            # dry run (default)
    python3 tool/register_firestore_chapters.py --apply    # write the catalogue
    python3 tool/register_firestore_chapters.py --check    # exit 1 if pending

The service account needs read access to Firestore only
(role `roles/datastore.viewer` is enough).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_PROJECT = 'quizbaaz-740bd'
CATALOG_REL = 'assets/data/chapters_list.json'
BANKS_REL = 'assets/data/questions'
CATEGORIES_COLLECTION = 'question_categories'
CHAPTERS_SUBCOLLECTION = 'chapters'
CONFIG_COLLECTION = 'config'
DELETIONS_DOC = 'content_deletions'


# --------------------------------------------------------------------------- #
# helpers
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
    except Exception as exc:  # noqa: BLE001 - surfaced to the operator verbatim
        sys.exit(f'could not create a Firestore client for {project}: {exc}')


def localized(raw: object) -> dict:
    """A `{en, bn, hi}` text map from a Firestore value, blanks for the rest."""
    out = {'en': '', 'bn': '', 'hi': ''}
    if isinstance(raw, dict):
        for key in out:
            value = raw.get(key)
            if isinstance(value, str):
                out[key] = value
    elif isinstance(raw, str):
        out['en'] = raw
    return out


def load_catalog(root: Path) -> dict:
    path = root / CATALOG_REL
    if not path.exists():
        sys.exit(f'catalogue not found: {path}')
    return json.loads(path.read_text(encoding='utf-8'))


def read_deletions(client) -> tuple[set[str], set[str]]:
    """(deleted_chapter_ids, deleted_category_ids) from the registry."""
    try:
        snap = client.collection(CONFIG_COLLECTION).document(DELETIONS_DOC).get()
        data = snap.to_dict() or {}
        chapters = {
            str(i).strip() for i in (data.get('deleted_chapter_ids') or [])
            if str(i).strip()
        }
        categories = {
            str(i).strip() for i in (data.get('deleted_category_ids') or [])
            if str(i).strip()
        }
        return chapters, categories
    except Exception as exc:  # noqa: BLE001 - best-effort
        print(f'warn: deletion registry unreadable — {exc}')
        return set(), set()


def read_firestore_catalog(client) -> list[dict]:
    """Every Firestore subject with its chapters, as plain dicts."""
    categories: list[dict] = []
    snap = client.collection(CATEGORIES_COLLECTION).get()
    for doc in snap:
        data = doc.to_dict() or {}
        chapters: list[dict] = []
        for chapter in doc.reference.collection(CHAPTERS_SUBCOLLECTION).get():
            cdata = chapter.to_dict() or {}
            chapters.append({
                'chapter_id': cdata.get('chapter_id') or chapter.id,
                'title': localized(cdata.get('title')),
                'description': localized(cdata.get('description')),
                'chapter_number': cdata.get('chapter_number') or 0,
                'is_unlocked': cdata.get('is_unlocked', True),
                'is_enabled': cdata.get('is_enabled', True),
                'json_file': cdata.get('json_file') or '',
            })
        categories.append({
            'category_id': data.get('category_id') or doc.id,
            'category_name': localized(data.get('category_name')),
            'category_icon': data.get('category_icon') or '',
            'color_hex': data.get('color_hex') or '',
            'priority': data.get('priority') or 0,
            'chapters': chapters,
        })
    return categories


def write_json(path: Path, obj: dict, previous_text: str | None) -> bool:
    text = json.dumps(obj, ensure_ascii=False, indent=2) + '\n'
    if previous_text is not None and previous_text == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text, encoding='utf-8')
    os.replace(tmp, path)
    return True


# --------------------------------------------------------------------------- #
# merge
# --------------------------------------------------------------------------- #
def merge_catalog(catalog: dict, remote_categories: list[dict],
                  deleted_chapters: set[str], deleted_categories: set[str],
                  root: Path) -> tuple[dict, list[str], list[str]]:
    """Add missing subjects/chapters; return (catalog, added_chapters, added_categories)."""
    by_id: dict[str, dict] = {
        c.get('category_id'): c for c in catalog.get('categories', [])
    }
    known_chapters = {
        ch.get('chapter_id')
        for c in catalog.get('categories', [])
        for ch in c.get('chapters', [])
    }

    added_categories: list[str] = []
    added_chapters: list[str] = []

    for remote in remote_categories:
        category_id = remote['category_id']
        if category_id in deleted_categories:
            continue

        category = by_id.get(category_id)
        if category is None:
            category = {
                'category_id': category_id,
                'category_name': remote['category_name'],
                'category_icon': remote['category_icon'],
                'color_hex': remote['color_hex'] or '#3B82F6',
                'total_chapters': 0,
                'chapters': [],
            }
            catalog.setdefault('categories', []).append(category)
            by_id[category_id] = category
            added_categories.append(category_id)

        for chapter in remote['chapters']:
            chapter_id = chapter['chapter_id']
            if chapter_id in deleted_chapters or chapter_id in known_chapters:
                continue
            json_file = chapter['json_file'] or f'{BANKS_REL}/{chapter_id}.json'
            category['chapters'].append({
                'chapter_id': chapter_id,
                'chapter_number': chapter['chapter_number'] or (
                    len(category['chapters']) + 1),
                'title': chapter['title'],
                'description': chapter['description'],
                'total_questions': 0,
                'json_file': json_file,
                'is_unlocked': chapter['is_unlocked'],
                'stars': 0,
                'best_score': 0,
            })
            known_chapters.add(chapter_id)
            added_chapters.append(chapter_id)

            # A skeleton bank so the pull tool has somewhere to write.
            bank_path = root / json_file
            if not bank_path.exists():
                bank_path.parent.mkdir(parents=True, exist_ok=True)
                bank_path.write_text(json.dumps({
                    'chapter_id': chapter_id,
                    'chapter_title': chapter['title'],
                    'class_standard': 'Class 10',
                    'questions': [],
                }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    for category in catalog.get('categories', []):
        category['chapters'].sort(key=lambda c: c.get('chapter_number') or 0)
        category['total_chapters'] = len(category.get('chapters', []))

    return catalog, added_chapters, added_categories


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    parser = argparse.ArgumentParser(
        description='Register Firestore subjects/chapters in the bundled '
                    'catalogue.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--repo-root', default=None,
                        help='repo root (default: the parent of tool/)')
    parser.add_argument('--service-account', default=None,
                        help='service-account JSON (or set '
                             'GOOGLE_APPLICATION_CREDENTIALS)')
    parser.add_argument('--project', default=None,
                        help='Firebase project to read (default: the '
                             '.firebaserc default, else ' + DEFAULT_PROJECT + ')')
    parser.add_argument('--apply', action='store_true',
                        help='write the catalogue (default: dry run)')
    parser.add_argument('--check', action='store_true',
                        help='exit 1 if anything is missing (for CI)')
    parser.add_argument('-q', '--quiet', action='store_true')
    args = parser.parse_args()

    root = Path(args.repo_root).resolve() if args.repo_root else \
        Path(__file__).resolve().parent.parent
    if not (root / 'assets' / 'data').is_dir():
        sys.exit(f'{root} does not look like the QuizBaaz repo root '
                 f'(no assets/data) — pass --repo-root')

    project = args.project or default_project(root) or DEFAULT_PROJECT
    catalog_path = root / CATALOG_REL
    catalog = load_catalog(root)
    previous_text = catalog_path.read_text(encoding='utf-8')

    client = build_client(args.service_account, project)
    deleted_chapters, deleted_categories = read_deletions(client)
    remote_categories = read_firestore_catalog(client)

    print(f'Firestore: {len(remote_categories)} subject(s), '
          f'{sum(len(c["chapters"]) for c in remote_categories)} chapter(s)')

    catalog, added_chapters, added_categories = merge_catalog(
        catalog, remote_categories, deleted_chapters, deleted_categories, root)

    if not added_categories and not added_chapters:
        print('Bundle catalogue is up to date — nothing to add.')
        return 0

    for category_id in added_categories:
        print(f'  + subject  {category_id}')
    for chapter_id in added_chapters:
        print(f'  + chapter  {chapter_id}')
    print(f'\n{len(added_categories)} subject(s) and {len(added_chapters)} '
          f'chapter(s) missing from the bundle.')

    if args.check:
        print('\nStale: run with --apply to fix.')
        return 1
    if not args.apply:
        print('\nDry run — nothing written. Re-run with --apply.')
        return 0

    if write_json(catalog_path, catalog, previous_text):
        print(f'\nWrote {CATALOG_REL}.')
    print('Next: python3 tool/pull_firestore_questions.py '
          '--update-catalog-counts')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
