#!/usr/bin/env python3
"""
Set the per-question time limit in the remote app config (`config/app`).

Why this exists
---------------
The quiz countdown is NOT a constant in the Dart code:

    QuizProvider.questionTimeSec -> UserProvider.config.secondsPerQuestion

`UserProvider.config` is read from the Hive cache (`qb_cache/app_config`),
which is a mirror of the Firestore document `config/app`. `AppConfig.fromJson`
prefers the document's `seconds_per_question` over the built-in default, so
while that document still says 15 the app shows 15 — even though
`AppConfig.secondsPerQuestion` in lib/data/models/app_config.dart was already
changed to 30, and even with no network (the Hive cache carries the 15 too).

Changing the Dart default is therefore necessary but not sufficient: the remote
document has to agree. `migrate_time_limit_15_to_30.py` fixed the *battle*
side (`question_banks/*/questions.time_limit_sec`); this fixes the quiz side.

What this does:
- Reads `config/app`
- Writes ONLY `seconds_per_question` (merge update — every other key untouched)
- Prints the before/after so the value the devices will actually read is visible

Usage:
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    pip install google-cloud-firestore
    python3 tool/check_service_account.py $GOOGLE_APPLICATION_CREDENTIALS
    python3 tool/set_question_seconds.py --show          # read the doc, write nothing
    python3 tool/set_question_seconds.py --dry-run       # show the change only
    python3 tool/set_question_seconds.py                 # set it to 30
    python3 tool/set_question_seconds.py --seconds 45    # or any other value

Requires Firestore role: roles/datastore.user

After this runs, every device needs an app restart (not just a resume): the
config is pulled once at startup by `SyncService.pullConfig()`, and until that
succeeds the cached 15 is what the timer shows.
"""

from __future__ import annotations

import argparse
import os
import sys

FIELD = 'seconds_per_question'
COLLECTION = 'config'
DOC_ID = 'app'


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
    parser.add_argument('--seconds', type=int, default=30,
                        help=f'value to write into {FIELD} (default: 30)')
    parser.add_argument('--dry-run', action='store_true',
                        help='show the change without writing')
    parser.add_argument('--show', action='store_true',
                        help='print the current document and exit')
    args = parser.parse_args()

    firestore, db = _client()
    if firestore is None or db is None:
        return 1

    ref = db.collection(COLLECTION).doc(DOC_ID)
    snapshot = ref.get()
    if not snapshot.exists:
        print(f'{COLLECTION}/{DOC_ID} does not exist — nothing to update.')
        print('Create it in the Firebase console (or let the app write one) first;')
        print('without the document the app falls back to the built-in Dart defaults.')
        return 1

    data = snapshot.to_dict() or {}
    current = data.get(FIELD)
    print(f'{COLLECTION}/{DOC_ID}: {FIELD} = {current!r}')
    if args.show:
        print('\nFull document:')
        for key in sorted(data):
            print(f'  {key}: {data[key]!r}')
        return 0

    if current == args.seconds:
        print(f'Already {args.seconds} — no write needed.')
        return 0

    if args.dry_run:
        print(f'DRY-RUN would set {FIELD} = {args.seconds}')
        return 0

    ref.update({FIELD: args.seconds, 'updated_at': firestore.SERVER_TIMESTAMP})
    verify = ref.get().to_dict() or {}
    print(f'Written: {FIELD} = {verify.get(FIELD)!r}')
    if verify.get(FIELD) != args.seconds:
        print('Read-back mismatch — a security rule or another writer may be involved.')
        return 1
    print('\nRestart the app on every device so the new value is pulled.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
