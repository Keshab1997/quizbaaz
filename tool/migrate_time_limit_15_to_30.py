#!/usr/bin/env python3
"""
Migrate all Firestore questions from 15s to 30s.

Why needed:
- Old banks were authored with time_limit_sec=15
- AppConfig default is now 30, but Firestore docs still hold 15
- QuizRepository merges: Firestore wins over bundled assets, so fixing assets alone is not enough

What this does:
- Scans collection question_banks/{chapterId}/questions
- Updates every doc where time_limit_sec == 15 to 30

Usage:
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    pip install google-cloud-firestore
    python3 tool/migrate_time_limit_15_to_30.py --dry-run   # show what would change
    python3 tool/migrate_time_limit_15_to_30.py             # actually update

Requires Firestore role: roles/datastore.user
"""

import argparse
from pathlib import Path

def run_firestore(dry_run: bool):
    try:
        from google.cloud import firestore
    except ImportError:
        print("Missing google-cloud-firestore. Run: pip install google-cloud-firestore")
        return 1

    db = firestore.Client()
    banks_ref = db.collection("question_banks")
    banks = list(banks_ref.list_documents())
    print(f"Found {len(banks)} chapter banks")

    total_scanned = 0
    total_to_update = 0
    total_updated = 0

    for bank_doc in banks:
        chapter_id = bank_doc.id
        questions_ref = bank_doc.collection("questions")
        # Query only where time_limit_sec == 15 to be fast
        try:
            docs = list(questions_ref.where("time_limit_sec", "==", 15).stream())
        except Exception as e:
            print(f"[{chapter_id}] query failed (maybe no index): {e} - falling back to full scan")
            docs = []
            for qdoc in questions_ref.stream():
                total_scanned += 1
                data = qdoc.to_dict() or {}
                if data.get("time_limit_sec") == 15:
                    docs.append(qdoc)
            # reset counters for this branch already counted
        else:
            total_scanned += len(docs)  # approximate when using where

        if not docs:
            continue

        print(f"[{chapter_id}] {len(docs)} docs with 15s")
        total_to_update += len(docs)

        if dry_run:
            for d in docs[:5]:
                print(f"  DRY-RUN would update: {d.id}")
            if len(docs) > 5:
                print(f"  ... and {len(docs)-5} more")
            continue

        # Batch update (max 500 per batch)
        batch = db.batch()
        batch_count = 0
        for qdoc in docs:
            batch.update(qdoc.reference, {"time_limit_sec": 30, "updated_at": firestore.SERVER_TIMESTAMP})
            batch_count += 1
            if batch_count == 400:
                batch.commit()
                total_updated += batch_count
                batch = db.batch()
                batch_count = 0
        if batch_count:
            batch.commit()
            total_updated += batch_count

    print(f"\nDone. Scanned ~{total_scanned}, to_update={total_to_update}, updated={total_updated}, dry_run={dry_run}")
    return 0


def run_local_assets(dry_run: bool, root: Path):
    """Also ensure local assets are 30 (should already be done)."""
    import json
    count_fixed = 0
    for path in (root / "assets" / "data" / "questions").glob("*.json"):
        text = path.read_text(encoding="utf-8")
        if '"time_limit_sec": 15' in text:
            if dry_run:
                print(f"DRY-RUN asset {path.name} still has 15")
            else:
                path.write_text(text.replace('"time_limit_sec": 15', '"time_limit_sec": 30'), encoding="utf-8")
                count_fixed += 1
    if count_fixed:
        print(f"Fixed {count_fixed} local asset files")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="show what would change")
    parser.add_argument("--assets-only", action="store_true", help="only fix local assets, skip Firestore")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    if args.assets_only:
        run_local_assets(args.dry_run, root)
    else:
        # fix assets first
        run_local_assets(args.dry_run, root)
        run_firestore(args.dry_run)
