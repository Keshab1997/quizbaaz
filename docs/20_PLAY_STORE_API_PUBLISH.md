# 20 — Publish the store listing + AAB via the Play Developer API

The Play Console forms were a manual, re-typed chore: title, short/full
descriptions, images and the AAB itself all had to be re-entered by hand. This
document describes the automation that replaces that. **Anything in this doc is
a repeatable step — you set it up once, and every release after that is one
workflow run.**

## What becomes automatic

| Step | Before | After |
|---|---|---|
| Store listing (title, descriptions, per-language) | typed in Console | `store_listing/listing.yaml` → API |
| Feature graphic + icon | drag-and-drop in Console | API upload |
| Phone screenshots | drag-and-drop in Console | API upload from `store_listing/screenshots/` |
| AAB upload + track assignment | drag-and-drop in Console | `gh release download` → API |
| Version collision on a track | discovered in Console | refused up front |

**Still manual (Play API has no field for them):** Data safety, content rating,
target audience and App access forms (one-time, `docs/18` Phase 7), and the
closed-test requirement for new personal accounts (`docs/18` Phase 10).

## Files introduced

- `store_listing/listing.yaml` — the **single source of truth** for the
  listing. Character limits: title ≤ 30, short description ≤ 80, full
  description ≤ 4000. Language codes use the region form Play requires
  (`en-US`, `hi-IN`, `bn-BD`); a bare `bn` makes the API 404 — check the exact
  codes under *Store presence → Main store listing → Manage translations*.
- `store_listing/screenshots/` — real captures of the submitted build, PNG or
  JPEG, portrait, 1080×1920 recommended, **min 2 / max 8**. Validation refuses
  to publish without them.
- `tool/publish_play.py` — validate and publish (`--validate`/`--listing`/
  `--aab`, `--dry-run`, `--track`, `--release-note`, `--service-account`).
- `.github/workflows/publish-play-store.yml` — the no-local-Python path.

## One-time setup (Google side)

**The old Play Console "API access" page is deprecated.** The current (2025+)
flow is to invite the service account like any other Play Console user:

1. Create the service account in **Google Cloud Console → IAM & Admin →
   Service accounts** for the linked Cloud project (here: `quizbaaz-740bd`).
   Name it `play-publisher`; the email becomes
   `play-publisher@<project>.iam.gserviceaccount.com`.
2. Make sure the **Play Developer API (`androidpublisher.googleapis.com`) is
   enabled** on that project (APIs & Services → Library).
3. In **Play Console → Users and permissions → Invite new users**, add the
   service-account email, pick the app you publish (here: `QuizBaaz: Play and
   Learn`, `com.keshabstudios.quizbaaz`) and grant it access under it. The
   tool only needs listing/AAB privileges — **Release manager** is the
   least-powerful preset that covers all four steps; scoped
   `Restricted manager → Release` also works. A dedicated machine account
   granted **Admin** for a single app is acceptable if the console form makes
   finer scoping awkward. Send the invite; service-account invites are
   auto-accepted and the row flips to **Active**.
4. Generate a **JSON key** for the account (Cloud Console → service account →
   Keys → Add key). Keep it locally; never commit it. The project is only the
   project of the key — the Play permissions come from the invite in step 3.
5. Verify locally with `docs/18`-style checks before wiring CI:

```bash
pip install google-auth requests pyyaml
GOOGLE_APPLICATION_CREDENTIALS=$HOME/.secrets/play-sa.json \
  python3 tool/publish_play.py --validate
GOOGLE_APPLICATION_CREDENTIALS=$HOME/.secrets/play-sa.json \
  python3 tool/publish_play.py --listing --dry-run
```

## Store it as a GitHub secret

`Settings → Secrets and variables → Actions → New repository secret`:

```text
PLAY_SERVICE_ACCOUNT_JSON   the full JSON of the key (one line)
```

The workflow checks the secret exists before touching the API and never prints
it.

## Local usage

```bash
python3 tool/publish_play.py                      # validate only (no API)
python3 tool/publish_play.py --validate
python3 tool/publish_play.py --listing            # update listing + images
python3 tool/publish_play.py --aab app-release.aab --track alpha
# Closed testing == the `alpha` track. `closedtesting` is accepted as an alias.
python3 tool/publish_play.py --aab app-release.aab --track production \
    --release-note "Class 10 mock sets refreshed"
GOOGLE_APPLICATION_CREDENTIALS=~/.secrets/play-sa.json \
  python3 tool/publish_play.py --listing --aab app-release.aab --track beta
```

`--dry-run` validates and prints the plan without calling the API. The script
is idempotent for images (existing sets are cleared before upload) and refuses
to re-add a version code that is already on the target track.

## GitHub Actions usage

Run **Play Store — Publish Listing & AAB**:

1. `mode: listing only` — update the listing from `listing.yaml`. No other
   inputs needed. Safe to run at any time.
2. `mode: listing + aab` or `aab only` — first run **Publish Android Release**
   (`publish-release.yml`) for the version you want to ship, note its tag
   (`v1.2.3`), then here choose the track (`internal` is the safe default),
   past the tag and optionally a release note. The workflow downloads the
   signed AAB from that release and uploads it.

`dry-run` runs the validate + plan gate without publishing, so you can prove
the pipeline end-to-end before a real run. `concurrency` ensures two manual
runs cannot commit overlapping edits.

Release flow reminder (`docs/18` Phase 8–12): bump `version:` in
`pubspec.yaml`, build AAB via **Publish Android Release**, test on **Internal
testing**, then promote. `production` track via the API goes to the same
review queue as a Console upload.

## Troubleshooting

- **`Play API 404 on .../apps` or `defaultLanguage`** — Play API v3 has no
  `edits/*/apps` endpoint and no way to set the default language over the API.
  It is chosen once in the Play Console when the app is created; the tool does
  not touch it.
- **`404` on image routes** — image routes take the image type as the *last*
  path segment (`.../listings/{lang}/icon`), no `images/` or `imageTypes/`
  in between, and binary uploads must go to the `/upload/` host. The tool
  handles both; re-run it rather than hand-crafting curl calls.
- **`Play API 404` on a language** — the code is not accepted for this app.
  Read the supported tags in *Manage translations* and fix `listing.yaml`.
- **"version code already on the track"** — your build number did not change.
  Bump `+N` in `pubspec.yaml` and re-cut the release.
- **`403`** — the service account lacks a Play role on this app. Fix it in
  Play Console → Users and permissions (invite/edit the account and grant it
  access under the app), or the JSON key is from a different project than the
  one the Play Developer API is enabled on.
- **Screenshots rejected** — Play enforces min 2 / max 8 and width ≥ 320px for
  phone screenshots; the validator catches these before the API call.