#!/usr/bin/env python3
"""Pull admin-authored questions from Firestore into the bundled asset banks.

Why this exists
---------------
QuizBaaz questions live in Firestore (`question_banks/{chapterId}/questions/{qid}`)
and are authored in the admin panel. The bundled JSON banks under
`assets/data/questions/` are the app's *offline floor* — the copy every install
has before any network call. This tool copies the Firestore layer down into that
floor, so a student who has never been online still sees real questions.

    Firestore (live, admin-authored)
            |
            |  this tool  (one-way: Firestore -> repo)
            v
    assets/data/questions/*.json  (bundled, offline, in git)

Nothing here ever writes to Firestore, and nothing is deleted unless you ask
for it with --prune. Bundled questions the admin later corrected are *replaced*
by the Firestore copy, mirroring the app's own merge rule
(`QuizRepository._mergeById`: assets first, Firestore wins on an id clash).

Usage
-----
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 tool/pull_firestore_questions.py --dry-run     # show the diff only
    python3 tool/pull_firestore_questions.py               # write the banks
    python3 tool/pull_firestore_questions.py --check       # CI: non-zero if stale
    python3 tool/pull_firestore_questions.py --chapter math_ch_01

    # no service account handy? rehearse against a saved dump:
    python3 tool/pull_firestore_questions.py --fixture fixtures/firestore_dump.json

The service account needs read access to Firestore only
(role `roles/datastore.viewer` is enough — anything more is unnecessary risk).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

LANGUAGES = ('en', 'bn', 'hi')

#: Firestore fields that describe the *authoring* event, not the question. They
#: stay in Firestore; the bundled bank only carries what the app displays.
METADATA_FIELDS = (
    'fingerprint', 'source', 'model', 'batch_id', 'created_by', 'created_at',
    'updated_at', 'updated_by', 'reviewed', 'chapter_id',
)

#: Field order inside a bundled question — matches QuestionModel.toJson().
QUESTION_FIELDS = (
    'id', 'question', 'options', 'correct_index', 'explanation', 'points',
    'time_limit_sec',
)

DEFAULTS = {'points': 10, 'time_limit_sec': 15}


# --------------------------------------------------------------------------- #
# report
# --------------------------------------------------------------------------- #
class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append(f'{where}: {message}')

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f'{where}: {message}')

    def note(self, message: str) -> None:
        self.notes.append(message)

    @property
    def ok(self) -> bool:
        return not self.errors


# --------------------------------------------------------------------------- #
# bundled banks
# --------------------------------------------------------------------------- #
def load_catalog(root: Path) -> tuple[dict, dict]:
    """Return (catalog_dict, chapters_by_id) from assets/data/chapters_list.json."""
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
                'title': chapter.get('title', {}),
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


# --------------------------------------------------------------------------- #
# sources: Firestore | fixture dump
# --------------------------------------------------------------------------- #
def questions_from_fixture(path: Path) -> dict[str, list[dict]]:
    """A dump keyed by chapter id:

    {"math_ch_01": {"questions": [ {...}, ... ]}, "sci_ch_01": [ {...} ]}
    """
    raw = json.loads(path.read_text(encoding='utf-8'))
    out: dict[str, list[dict]] = {}
    for chapter_id, value in raw.items():
        if chapter_id.startswith('_'):
            continue                      # "_note"-style commentary in a dump
        if isinstance(value, dict):
            rows = value.get('questions', [])
        elif isinstance(value, list):
            rows = value
        else:
            continue
        out[chapter_id] = [dict(row) for row in rows or [] if isinstance(row, dict)]
    return out


def questions_from_firestore(service_account: str | None, project: str | None):
    """Stream `question_banks/{chapter}/questions/*` via the Admin SDK.

    A collection-group query keeps this to one round trip instead of one per
    chapter, and the Admin SDK bypasses security rules — which is why a
    read-only service account is all this needs.
    """
    try:
        from google.cloud import firestore as gcf  # type: ignore
    except ImportError:
        sys.exit(
            'google-cloud-firestore is not installed.\n'
            '  pip install google-cloud-firestore\n'
            '(or rehearse offline with --fixture fixtures/firestore_dump.json)'
        )

    if service_account:
        os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', service_account)

    try:
        client = gcf.Client(project=project) if project else gcf.Client()
    except Exception as exc:  # noqa: BLE001 - surfaced to the operator verbatim
        sys.exit(f'could not create a Firestore client: {exc}')

    try:
        docs = client.collection_group('questions').stream()
    except Exception as exc:  # noqa: BLE001
        sys.exit(
            f'Firestore refused the read: {exc}\n'
            'Check the service account, its IAM role and the project id.'
        )

    out: dict[str, list[dict]] = {}
    for doc in docs:
        parent = doc.reference.parent.parent
        chapter_id = parent.id if parent is not None else ''
        if not chapter_id:
            continue
        out.setdefault(chapter_id, []).append(dict(doc.to_dict() or {}))
    return out


# --------------------------------------------------------------------------- #
# normalisation + validation
# --------------------------------------------------------------------------- #
def normalise(raw: dict) -> dict:
    """Keep the question, drop the bookkeeping, fill the defaults."""
    out = {}
    for field in QUESTION_FIELDS:
        value = raw.get(field)
        if field == 'id':
            out['id'] = str(value if value is not None else '').strip()
        elif field in ('question', 'explanation'):
            out[field] = value if isinstance(value, dict) else {}
        elif field == 'options':
            out[field] = value if isinstance(value, list) else []
        elif field == 'correct_index':
            out[field] = value if isinstance(value, (int, float)) else 0
            out[field] = int(out[field])
        else:
            out[field] = int(value) if isinstance(value, (int, float)) else DEFAULTS[field]
    return out


def check_question(question: dict, where: str, report: Report) -> bool:
    """True when the question is safe to bundle. Hard problems are errors."""
    ok = True

    if not question['id']:
        report.error(where, 'missing "id" — Firestore document has no id field')
        ok = False

    stem = question['question']
    if not isinstance(stem, dict) or not str(stem.get('en', '')).strip():
        report.error(where, '"question.en" is empty — English is the fallback')
        ok = False

    options = question['options']
    if not isinstance(options, list) or len(options) < 2:
        report.error(where, f'{len(options) if isinstance(options, list) else 0} options '
                            '— at least 2 are required')
        ok = False
    else:
        for index, option in enumerate(options):
            if not isinstance(option, dict) or not str(option.get('en', '')).strip():
                report.error(where, f'option {index} has no English text')
                ok = False

    index = question['correct_index']
    if isinstance(options, list) and not (0 <= index < len(options)):
        report.error(where, f'correct_index={index} outside 0..{max(len(options) - 1, 0)}')
        ok = False

    # Translation gaps are warnings: the app falls back, but the repo's own
    # gate (`validate_questions.py --strict`) treats them as failures.
    missing = [
        language for language in LANGUAGES
        if not str((stem or {}).get(language, '')).strip()
    ]
    if missing:
        report.warn(where, 'question missing ' + ', '.join(missing))
        ok = ok  # still bundleable, unless --require-translations
    for index, option in enumerate(options if isinstance(options, list) else []):
        if not isinstance(option, dict):
            continue
        for language in LANGUAGES:
            if not str(option.get(language, '')).strip():
                report.warn(where, f'option {index} missing {language}')

    return ok


def is_fully_translated(question: dict) -> bool:
    stem = question.get('question') or {}
    if any(not str(stem.get(language, '')).strip() for language in LANGUAGES):
        return False
    for option in question.get('options') or []:
        if not isinstance(option, dict):
            return False
        if any(not str(option.get(language, '')).strip() for language in LANGUAGES):
            return False
    return True


# --------------------------------------------------------------------------- #
# merge + write
# --------------------------------------------------------------------------- #
def merge_questions(asset_rows: list[dict], remote_rows: list[dict]) -> tuple[list[dict], int]:
    """Union by id, asset order first, remote overriding; new ids appended.

    Returns (merged, added_count).
    """
    merged: dict[str, dict] = {}
    order: list[str] = []

    def put(row: dict) -> None:
        qid = str(row.get('id', '')).strip()
        if not qid:
            return
        if qid not in merged:
            order.append(qid)
        merged[qid] = row

    for row in asset_rows:
        put(row)
    added = [row for row in remote_rows if str(row.get('id', '')).strip() not in merged]
    for row in added:
        put(row)

    return [merged[qid] for qid in order], len(added)


def dump_json(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + '\n'


def write_json(path: Path, data: dict, current_text: str | None) -> bool:
    """Atomic write; returns True when the file actually changed."""
    text = dump_json(data)
    if current_text is not None and current_text == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text, encoding='utf-8')
    os.replace(tmp, path)
    return True


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    parser = argparse.ArgumentParser(
        description='Copy Firestore questions into the bundled asset banks.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--repo-root', default=None,
                        help='repo root (default: the parent of tool/)')
    parser.add_argument('--service-account', default=None,
                        help='service-account JSON (or set '
                             'GOOGLE_APPLICATION_CREDENTIALS)')
    parser.add_argument('--project', default=None, help='override the project id')
    parser.add_argument('--fixture', default=None,
                        help='read a saved dump instead of Firestore')
    parser.add_argument('--chapter', action='append', default=None,
                        help='only this chapter id (repeatable)')
    parser.add_argument('--dry-run', action='store_true',
                        help='report what would change; write nothing')
    parser.add_argument('--check', action='store_true',
                        help='exit 1 if any bank is out of date (for CI)')
    parser.add_argument('--prune', action='store_true',
                        help='also drop bundled questions that no longer exist '
                             'in Firestore (off by default: never lose a bank')
    parser.add_argument('--require-translations', action='store_true',
                        help='skip questions that are not authored in en+bn+hi')
    parser.add_argument('--include-invalid', action='store_true',
                        help='bundle questions that fail hard validation too')
    parser.add_argument('--update-catalog-counts', action='store_true',
                        help='also refresh total_questions in chapters_list.json '
                             '(read the double-count note in the README first)')
    parser.add_argument('--json-report', default=None,
                        help='write a machine-readable summary here')
    parser.add_argument('-q', '--quiet', action='store_true')
    args = parser.parse_args()

    root = Path(args.repo_root).resolve() if args.repo_root else \
        Path(__file__).resolve().parent.parent
    report = Report()

    if not (root / 'assets' / 'data').is_dir():
        sys.exit(f'{root} does not look like the QuizBaaz repo root '
                 f'(no assets/data) — pass --repo-root')

    catalog, chapters = load_catalog(root)

    # ---------------------------------------------------------------- source
    if args.fixture:
        remote = questions_from_fixture(Path(args.fixture))
        source_label = f'fixture {args.fixture}'
    else:
        remote = questions_from_firestore(args.service_account, args.project)
        source_label = 'Firestore'

    if args.chapter:
        wanted = set(args.chapter)
        remote = {cid: rows for cid, rows in remote.items() if cid in wanted}

    if not remote:
        print(f'{source_label}: no questions found.')
        print('Nothing to do — an empty bank is never written over a bundled one.')
        return 0

    print(f'{source_label}: {sum(len(v) for v in remote.values())} question(s) '
          f'in {len(remote)} chapter(s)\n')

    # ----------------------------------------------------------------- merge
    summary = []
    catalog_counts: dict[str, int] = {}
    changed_files = 0
    stale = False

    for chapter_id in sorted(remote):
        rows = remote[chapter_id]
        info = chapters.get(chapter_id)
        where = chapter_id

        if info is None:
            report.warn(where, 'chapter is not in chapters_list.json — skipped '
                               '(admin-added chapters are served live from '
                               'Firestore; add it to the catalogue to bundle it)')
            continue
        json_file = info.get('json_file') or ''
        if not json_file:
            report.warn(where, 'catalogue entry has no json_file — skipped')
            continue

        bank_path = root / json_file
        current_text = bank_path.read_text(encoding='utf-8') if bank_path.exists() else None
        bank = read_bank(bank_path)
        asset_rows = bank.get('questions') or []

        clean: list[dict] = []
        for raw in rows:
            question = normalise(raw)
            qid = question['id'] or '<no id>'
            valid = check_question(question, f'{chapter_id}/{qid}', report)
            if not valid and not args.include_invalid:
                continue
            if args.require_translations and not is_fully_translated(question):
                report.note(f'{chapter_id}/{qid}: skipped — not fully translated')
                continue
            clean.append(question)

        if not clean:
            report.warn(where, 'no bundleable questions — bank left untouched')
            continue

        if args.prune:
            keep = {q['id'] for q in clean}
            asset_rows = [q for q in asset_rows if str(q.get('id')) in keep]

        merged, added = merge_questions(asset_rows, clean)

        new_bank = dict(bank)          # keep chapter_title, class_standard, …
        new_bank['questions'] = merged
        if 'total_questions' in new_bank:
            new_bank['total_questions'] = len(merged)

        removed = len(asset_rows) - (len(merged) - added)
        changed = current_text != dump_json(new_bank)
        catalog_counts[chapter_id] = len(merged)

        summary.append({
            'chapter_id': chapter_id,
            'file': json_file,
            'bundled_before': len(asset_rows),
            'bundled_after': len(merged),
            'added': added,
            'updated': len(clean) - added,
            'removed': max(removed, 0),
            'changed': changed,
        })

        if args.check:
            if changed:
                stale = True
                report.error(where, f'bank out of date ({added} new) — '
                                    'run without --check to refresh it')
            continue
        if args.dry_run:
            continue
        if write_json(bank_path, new_bank, current_text):
            changed_files += 1

    # ---------------------------------------------------------------- output
    width = max([len(item['chapter_id']) for item in summary], default=10)
    for item in summary:
        flag = '' if item['changed'] else '  (unchanged)'
        print(f"  {item['chapter_id']:<{width}}  "
              f"{item['bundled_before']:>4} -> {item['bundled_after']:<4} "
              f"+{item['added']} new, ~{item['updated']} refreshed, "
              f"-{item['removed']} dropped{flag}")

    if args.update_catalog_counts and catalog_counts and not args.dry_run and not args.check:
        touched = 0
        for category in catalog.get('categories', []):
            for chapter in category.get('chapters', []):
                count = catalog_counts.get(chapter.get('chapter_id'))
                if count is not None and chapter.get('total_questions') != count:
                    chapter['total_questions'] = count
                    touched += 1
        if touched:
            catalog_path = root / 'assets' / 'data' / 'chapters_list.json'
            write_json(catalog_path, catalog,
                       catalog_path.read_text(encoding='utf-8'))
            report.note(f'chapters_list.json: refreshed total_questions for '
                        f'{touched} chapter(s) — the running app adds the live '
                        f'Firestore count on top, so expect double counting '
                        f'until QuizRepository._withLiveCounts is patched')
    elif catalog_counts and args.update_catalog_counts:
        report.note('chapters_list.json left alone (dry-run/check) — the app '
                    'derives live counts itself')
    elif catalog_counts and not args.dry_run and not args.check:
        report.note('chapters_list.json was NOT touched, so validate_questions.py '
                    'will now report "chapters_list says total_questions=0 but the '
                    'bank has N". Re-run with --update-catalog-counts once the '
                    'one-line QuizRepository._withLiveCounts patch from the README '
                    'is applied — otherwise the app would count pulled questions '
                    'twice while the student is online.')

    print()
    for line in report.notes:
        print(f'  note: {line}')
    for line in report.warnings:
        print(f'  warn: {line}')
    for line in report.errors:
        print(f'  ERROR: {line}')

    if args.json_report:
        Path(args.json_report).write_text(dump_json({
            'source': source_label,
            'summary': summary,
            'errors': report.errors,
            'warnings': report.warnings,
            'notes': report.notes,
        }), encoding='utf-8')

    verb = 'would change' if args.dry_run else 'changed'
    print(f'\n{len(summary)} chapter(s) considered, {changed_files} file(s) {verb}'
          f' — {len(report.errors)} error(s), {len(report.warnings)} warning(s)')

    if args.check:
        return 1 if stale else 0          # CI gate: only "is the bundle stale?"
    return 0 if report.ok else 1          # content problems surface as non-zero


if __name__ == '__main__':
    raise SystemExit(main())
