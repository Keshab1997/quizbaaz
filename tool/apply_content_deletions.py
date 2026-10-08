#!/usr/bin/env python3
"""Drop deleted content from the bundled assets.

Why this exists
---------------
The admin panel can delete a chapter or a subject, and that delete is recorded
in Firestore (`config/content_deletions`) — see `ChapterCatalogService`. Every
running app reads that registry and stops showing the deleted content, which
works even for bundled chapters, whose JSON no installed app can remove from
its own asset bundle.

What Firestore cannot do is rewrite the *repo*. The shipped JSON under
`assets/data/questions/` (and the chapter's entry in `chapters_list.json`) is
still there, so a fresh install — or an app that has not synced yet — would
keep the deleted chapter. This tool is the missing half:

    config/content_deletions        (the admin's delete, one record)
              |
              |  this tool  (Firestore -> repo)
              v
    assets/data/questions/*.json     gone, and the catalogue entry with it
    assets/data/chapters_list.json

It only ever removes what the registry names. A bank file shared by a chapter
that is *not* deleted is left alone, and a chapter deleted alone keeps its
subject (with one chapter fewer) so the admin can decide what happens to the
rest.

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/apply_content_deletions.py                  # dry run (default)
    python3 tool/apply_content_deletions.py --apply          # write the bundle
    python3 tool/apply_content_deletions.py --check          # exit 1 if pending

    # rehearse offline, or apply ids the registry has not been read for:
    python3 tool/apply_content_deletions.py --fixture fixtures/deletions.json
    python3 tool/apply_content_deletions.py --chapter sci_ch_02 --apply

The service account needs read access to Firestore only
(role `roles/datastore.viewer` is enough).

After `--apply`, run the validator before committing:

    python3 tool/validate_questions.py --strict
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'assets' / 'data' / 'chapters_list.json'
BANKS = ROOT / 'assets' / 'data' / 'questions'

DELETIONS_COLLECTION = 'config'
DELETIONS_DOC = 'content_deletions'


# --------------------------------------------------------------------------- #
# the registry
# --------------------------------------------------------------------------- #
def registry_from_fixture(path: Path) -> tuple[set[str], set[str]]:
    """A saved copy of the registry document."""
    raw = json.loads(path.read_text(encoding='utf-8'))
    return (
        {str(i) for i in raw.get('deleted_chapter_ids', [])},
        {str(i) for i in raw.get('deleted_category_ids', [])},
    )


def registry_from_firestore(
    service_account: str | None, project: str | None
) -> tuple[set[str], set[str]]:
    """Read `config/content_deletions` with the Admin SDK.

    The Admin SDK bypasses security rules, which is why a read-only service
    account is all this needs.
    """
    try:
        from google.cloud import firestore as gcf  # type: ignore
    except ImportError:
        sys.exit(
            'google-cloud-firestore is not installed.\n'
            '  pip install google-cloud-firestore\n'
            '(or rehearse offline with --fixture, or name ids with --chapter/--category)'
        )

    if service_account:
        os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', service_account)

    try:
        client = gcf.Client(project=project) if project else gcf.Client()
        snapshot = (
            client.collection(DELETIONS_COLLECTION).document(DELETIONS_DOC).get()
        )
    except Exception as exc:  # noqa: BLE001 - surfaced to the operator verbatim
        sys.exit(
            f'Firestore refused the read: {exc}\n'
            'Check the service account, its IAM role and the project id.'
        )

    if not snapshot.exists:
        return set(), set()

    data = snapshot.to_dict() or {}
    return (
        {str(i) for i in data.get('deleted_chapter_ids', [])},
        {str(i) for i in data.get('deleted_category_ids', [])},
    )


# --------------------------------------------------------------------------- #
# the bundle
# --------------------------------------------------------------------------- #
def load_catalog() -> dict:
    if not CATALOG.exists():
        sys.exit(f'catalogue not found: {CATALOG}')
    try:
        return json.loads(CATALOG.read_text(encoding='utf-8'))
    except json.JSONDecodeError as exc:
        sys.exit(f'broken JSON in {CATALOG}: {exc}')


def plan(catalog: dict, deleted_chapters: set[str], deleted_categories: set[str]):
    """Work out what leaves the bundle.

    Returns (kept_categories, dropped_chapters, bank_files_to_delete).
    """
    kept: list[dict] = []
    dropped_chapters: list[tuple[str, str, str]] = []   # (chapter, subject, file)

    for category in catalog.get('categories', []):
        category_id = category.get('category_id', '?')
        if category_id in deleted_categories:
            for chapter in category.get('chapters', []):
                dropped_chapters.append(
                    (chapter.get('chapter_id', '?'), category_id,
                     chapter.get('json_file', ''))
                )
            continue

        chapters = [
            chapter
            for chapter in category.get('chapters', [])
            if chapter.get('chapter_id') not in deleted_chapters
        ]
        for chapter in category.get('chapters', []):
            if chapter.get('chapter_id') in deleted_chapters:
                dropped_chapters.append(
                    (chapter.get('chapter_id', '?'), category_id,
                     chapter.get('json_file', ''))
                )

        kept_category = dict(category)
        kept_category['chapters'] = chapters
        kept_category['total_chapters'] = len(chapters)
        kept.append(kept_category)

    # A bank file goes only if no *kept* chapter still points at it — two
    # chapters can share one file, and deleting both is the only case where
    # the file itself is dead weight.
    still_referenced = {
        chapter.get('json_file', '')
        for category in kept
        for chapter in category.get('chapters', [])
    }
    bank_files = [
        path
        for _, _, path in dropped_chapters
        if path and path not in still_referenced
    ]

    return kept, dropped_chapters, sorted(set(bank_files))


def write_catalog(catalog: dict, kept: list[dict]) -> None:
    updated = dict(catalog)
    updated['categories'] = kept
    CATALOG.write_text(
        json.dumps(updated, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true',
                        help='write the changes (default: dry run)')
    parser.add_argument('--check', action='store_true',
                        help='write nothing; exit 1 when the bundle is stale')
    parser.add_argument('--fixture',
                        help='read the registry from a saved JSON copy instead '
                             'of Firestore')
    parser.add_argument('--service-account',
                        help='service-account JSON (else the '
                             'GOOGLE_APPLICATION_CREDENTIALS env var)')
    parser.add_argument('--project', help='Firebase/GCP project id')
    parser.add_argument('--chapter', action='append', default=[],
                        help='extra chapter id to treat as deleted (repeatable)')
    parser.add_argument('--category', action='append', default=[],
                        help='extra subject id to treat as deleted (repeatable)')
    args = parser.parse_args()

    if args.fixture:
        deleted_chapters, deleted_categories = registry_from_fixture(
            Path(args.fixture)
        )
        source = f'fixture {args.fixture}'
    else:
        deleted_chapters, deleted_categories = registry_from_firestore(
            args.service_account, args.project
        )
        source = f'Firestore {DELETIONS_COLLECTION}/{DELETIONS_DOC}'

    deleted_chapters |= {c for c in args.chapter if c}
    deleted_categories |= {c for c in args.category if c}

    catalog = load_catalog()
    kept, dropped_chapters, bank_files = plan(
        catalog, deleted_chapters, deleted_categories
    )

    print(f'Registry      : {source}')
    print(f'Deleted ids   : {len(deleted_chapters)} chapter(s), '
          f'{len(deleted_categories)} subject(s)')
    print(f'In the bundle : {len(dropped_chapters)} chapter(s), '
          f'{len(bank_files)} bank file(s)')

    if not dropped_chapters:
        print('\nBundle is up to date — nothing to remove.')
        return 0

    for chapter_id, category_id, path in dropped_chapters:
        print(f'  - {category_id}/{chapter_id}  {path or "(no json_file)"}')
    for path in bank_files:
        target = ROOT / path
        mark = '' if target.exists() else '  (already gone)'
        print(f'  x {path}{mark}')

    if args.check:
        print('\nStale: run without --check and with --apply to fix.')
        return 1

    if not args.apply:
        print('\nDry run — nothing written. Re-run with --apply.')
        return 0

    for path in bank_files:
        target = ROOT / path
        if target.exists():
            target.unlink()
    write_catalog(catalog, kept)

    print(f"\nRemoved {len(bank_files)} bank file(s) and "
          f"{len(dropped_chapters)} catalogue entr"
          f"{'y' if len(dropped_chapters) == 1 else 'ies'}.")
    print('Now run:  python3 tool/validate_questions.py --strict')
    print('Then commit both the catalogue and the removed banks.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
