#!/usr/bin/env python3
"""Is this the right JSON file, and can it actually read your Firestore?

Run this BEFORE the pull tool — it answers three questions in one go:

    1. Is this a Firebase *service account* key (and not google-services.json,
       firebase_options.dart or .firebaserc by mistake)?
    2. Which project does it belong to?
    3. Can it read Firestore, and how many questions are in there right now?

    python3 tool/check_service_account.py ~/.secrets/quizbaaz-sa.json

The private key is never printed, logged or copied anywhere — only the fields
that are safe to show (project id, client email, key id).

Exit codes: 0 = usable, 1 = wrong/unsuitable file, 2 = unreadable or no network.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

GREEN, RED, YELLOW, DIM, RESET = '\033[32m', '\033[31m', '\033[33m', '\033[2m', '\033[0m'
if not sys.stdout.isatty() or os.environ.get('NO_COLOR'):
    GREEN = RED = YELLOW = DIM = RESET = ''

REQUIRED = ('type', 'project_id', 'private_key', 'client_email', 'client_id', 'token_uri')
PRIVATE_MARKERS = ('BEGIN PRIVATE KEY', 'BEGIN RSA PRIVATE KEY')

#: Files people mix up with the one they actually need.
LOOKALIKES = {
    'google-services.json': 'Firebase config for the *Android app*. No private key — useless here.',
    'firebase_options.dart': 'FlutterFire config that ships inside the app. Public by design.',
    'GoogleService-Info.plist': 'The iOS twin of google-services.json. Not this either.',
    '.firebaserc': 'Just a list of project aliases for the firebase CLI.',
    'service-account.json': 'Often the right *kind* of file — check it with this script.',
}


def fail(message: str, code: int = 1) -> int:
    print(f'{RED}✗ {message}{RESET}')
    return code


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = Path(os.path.expanduser(sys.argv[1]))

    print(f'checking: {path}\n')

    if not path.exists():
        return fail(f'no such file: {path}')
    if path.is_dir():
        return fail(f'{path} is a folder, not the JSON key file')

    name = path.name
    if name in LOOKALIKES:
        print(f'{YELLOW}!{RESET} {name} — {LOOKALIKES[name]}')

    try:
        raw = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        return fail('not a text/JSON file (a .p12 or .keystore cannot be read)')

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        if name.endswith('.json') and '"type"' not in raw:
            return fail(f'not valid JSON ({exc}) — is it a half-downloaded file?')
        return fail(f'not valid JSON ({exc})')

    if not isinstance(data, dict):
        return fail('JSON root is not an object — this is not a key file')

    kind = data.get('type')
    if kind != 'service_account':
        hint = LOOKALIKES.get(name, '')
        return fail(
            f'"type" is {kind!r}, expected "service_account".\n'
            f'  {hint}\n'
            '  In the console: Settings → Service accounts → Generate new private key'
        )

    missing = [field for field in REQUIRED if not data.get(field)]
    if missing:
        return fail(f'service-account JSON is missing field(s): {", ".join(missing)}')

    private_key = str(data.get('private_key', ''))
    if not any(marker in private_key for marker in PRIVATE_MARKERS):
        return fail('"private_key" does not look like a PEM key')

    # ------------------------------------------------------------------ report
    print(f'{GREEN}✓{RESET} valid service-account key')
    print(f'    project_id   : {data["project_id"]}')
    print(f'    client_email : {data["client_email"]}')
    print(f'    key id       : {data.get("private_key_id", "(none)")}')
    print(f'    private key  : {DIM}present, {len(private_key)} chars — never printed{RESET}')
    if data['project_id'] != 'quizbaaz-740bd':
        print(f'{YELLOW}!{RESET} project is not "quizbaaz-740bd" — '
              'double-check you picked the right project in the console')

    # ------------------------------------------------------------- live probe
    try:
        from google.cloud import firestore as gcf  # type: ignore
    except ImportError:
        print(f'\n{YELLOW}!{RESET} google-cloud-firestore not installed, so the '
              'live read was skipped.\n    pip install google-cloud-firestore')
        print('\nThe file itself is usable ✅')
        return 0

    print('\nreading Firestore (collection group "questions") …')
    os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', str(path))
    try:
        client = gcf.Client(project=data['project_id'])
    except Exception as exc:  # noqa: BLE001 - usually a damaged private_key
        print(f'{RED}✗{RESET} the file is shaped right, but its private key could '
              f'not be loaded: {exc}')
        print('    -> download the key again; a truncated copy cannot be repaired')
        return 2

    try:
        totals: dict[str, int] = {}
        for doc in client.collection_group('questions').stream():
            parent = doc.reference.parent.parent
            chapter = parent.id if parent is not None else '(unknown)'
            totals[chapter] = totals.get(chapter, 0) + 1
    except Exception as exc:  # noqa: BLE001 - the operator needs the raw reason
        print(f'{RED}✗{RESET} the key loaded fine, but the Firestore read failed: {exc}')
        print('    -> give the account the "Cloud Datastore Viewer" role '
              '(IAM & Admin → IAM), or check that the project id is right')
        return 2

    if not totals:
        print(f'{YELLOW}!{RESET} read succeeded, but there are no questions in '
              'Firestore yet.\n    Add some from the admin panel first, then re-run.')
        return 0

    total = sum(totals.values())
    print(f'{GREEN}✓{RESET} read succeeded: {total} question(s) across '
          f'{len(totals)} chapter(s)')
    for chapter in sorted(totals, key=lambda c: (-totals[c], c))[:15]:
        print(f'    {chapter:<24} {totals[chapter]:>5}')
    if len(totals) > 15:
        print(f'    … and {len(totals) - 15} more chapter(s)')

    print(f'\n{GREEN}Everything checks out.{RESET} Now run:')
    print('    python3 tool/pull_firestore_questions.py --dry-run')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
