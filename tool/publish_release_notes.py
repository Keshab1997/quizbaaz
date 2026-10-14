#!/usr/bin/env python3
"""
Publish the incoming release's notes to remote config (`config/app`).

Why this exists
---------------
The Update Center used to look the *installed* version up in the bundled
`WhatsNewCatalog`. A phone on 1.0.20 with a Play update waiting therefore
showed 1.0.20's notes under the update prompt — the incoming update looked
like the previous one (owner screenshot, 2026-10-14). The old binary cannot
carry the new release's notes, so they are published remotely instead:

    latest_release_version : "1.0.22"
    latest_release_notes   : {en: [...], bn: [...], hi: [...]}

in the Firestore document `config/app`, which every device already pulls at
startup (`SyncService.pullConfig`) and caches in Hive. The Update Center
shows them only while Play reports a newer bundle; after the install, the
bundled catalog of the new build takes over with the same text.

What this does:
- Reads the current release from `store_listing/whats_new.yaml`
  (falls back to `distribution/whatsnew/*` + `pubspec.yaml` without PyYAML)
- Writes ONLY the two fields above (merge update — every other key untouched)
- Prints the before/after so the value devices will actually read is visible

Usage:
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    pip install google-cloud-firestore
    python3 tool/check_service_account.py $GOOGLE_APPLICATION_CREDENTIALS
    python3 tool/publish_release_notes.py --show      # read the doc, write nothing
    python3 tool/publish_release_notes.py --dry-run   # show the payload only
    python3 tool/publish_release_notes.py             # publish current release notes

Requires Firestore role: roles/datastore.user

Run this as part of every release (after the version bump, before or after
the Play upload — devices only show the notes while Play also reports the
newer bundle). Devices pick the values up on their next app start.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
COLLECTION = 'config'
DOC_ID = 'app'
FIELDS = ('latest_release_version', 'latest_release_notes')
LANG_FILES = {'en': 'whatsnew-en-US', 'bn': 'whatsnew-bn-BD', 'hi': 'whatsnew-hi-IN'}


def _bullets(text: str) -> list[str]:
    """Bullet lines of a release-note block (header line skipped)."""
    out = []
    for line in (text or '').splitlines():
        line = line.strip()
        if line.startswith('•'):
            out.append(line.lstrip('•').strip())
    return [b for b in out if b]


def _notes_from_distribution() -> tuple[str, dict[str, list[str]]]:
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+',
                  (REPO_ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    notes = {}
    for lang, name in LANG_FILES.items():
        path = REPO_ROOT / 'distribution' / 'whatsnew' / name
        if path.is_file():
            notes[lang] = _bullets(path.read_text(encoding='utf-8'))
    return (m.group(1) if m else ''), notes


def load_current_notes() -> tuple[str, dict[str, list[str]]]:
    """(version, {lang: bullets}) for the release whats_new.yaml calls current."""
    yaml_path = REPO_ROOT / 'store_listing' / 'whats_new.yaml'
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(yaml_path.read_text(encoding='utf-8')) or {}
        current = str(data.get('current') or '')
        block = (data.get('releases') or {}).get(current) or {}
        notes = {lang: _bullets(str(block.get(lang) or ''))
                 for lang in LANG_FILES}
        if current and any(notes.values()):
            return current, notes
        print('whats_new.yaml has no bullets for its current release — '
              'falling back to distribution/whatsnew/.')
    except ImportError:
        print('PyYAML not installed — reading distribution/whatsnew/ instead.')
    except Exception as exc:  # noqa: BLE001
        print(f'whats_new.yaml unreadable ({exc}) — '
              'falling back to distribution/whatsnew/.')
    return _notes_from_distribution()


def _client():
    try:
        from google.cloud import firestore
    except ImportError:
        print('Missing google-cloud-firestore. Run: pip install google-cloud-firestore')
        return None, None
    creds = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
    if not creds:
        print('GOOGLE_APPLICATION_CREDENTIALS is not set.')
        print('  export GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json')
        print('  python3 tool/check_service_account.py $GOOGLE_APPLICATION_CREDENTIALS')
        return None, None
    if not os.path.exists(creds):
        print(f'Credential file not found: {creds}')
        return None, None
    return firestore, firestore.Client()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true',
                        help='show the payload without writing')
    parser.add_argument('--show', action='store_true',
                        help='print what config/app currently publishes and exit')
    args = parser.parse_args()

    version, notes = load_current_notes()
    if not version or not any(notes.values()):
        print('No release notes found (store_listing/whats_new.yaml / '
              'distribution/whatsnew/) — bump the version and write the '
              'notes first.')
        return 1
    payload = {'latest_release_version': version, 'latest_release_notes': notes}

    firestore, db = _client()
    if firestore is None or db is None:
        return 1

    ref = db.collection(COLLECTION).document(DOC_ID)
    snapshot = ref.get()
    if not snapshot.exists:
        print(f'{COLLECTION}/{DOC_ID} does not exist — nothing to update.')
        print('Create it in the Firebase console (or let the app write one) first;')
        print('without the document the app falls back to the built-in Dart defaults.')
        return 1

    data = snapshot.to_dict() or {}
    print(f'{COLLECTION}/{DOC_ID} currently publishes:')
    print(f'  latest_release_version = {data.get(FIELDS[0])!r}')
    print(f'  latest_release_notes   = {data.get(FIELDS[1])!r}')
    if args.show:
        return 0

    print('\nWould publish:' if args.dry_run else '\nPublishing:')
    print(f'  latest_release_version = {version!r}')
    for lang in LANG_FILES:
        print(f'  {lang}: {len(notes.get(lang) or [])} bullet(s)')
    if args.dry_run:
        print('\nDRY-RUN — nothing written.')
        return 0

    if data.get(FIELDS[0]) == version and data.get(FIELDS[1]) == notes:
        print('\nAlready published — no write needed.')
        return 0

    ref.update({**payload, 'updated_at': firestore.SERVER_TIMESTAMP})
    verify = ref.get().to_dict() or {}
    if verify.get(FIELDS[0]) != version or verify.get(FIELDS[1]) != notes:
        print('Read-back mismatch — a security rule or another writer may be involved.')
        return 1
    print(f'\nWritten: latest_release_version = {verify.get(FIELDS[0])!r}')
    print('Devices pick this up on their next app start; the Update Center '
          'shows it while Play reports the newer bundle.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
