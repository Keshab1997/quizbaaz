#!/usr/bin/env python3
"""Publish the Play Store listing + signed AAB through the Play Developer API.

Why this exists
---------------
Until now the store listing lived only inside the Play Console web forms and
was therefore a hand-typed, one-off task nobody could re-run consistently:
title, short description, full description, feature graphic, icon and
screenshots all had to be re-entered, and the AAB was always uploaded by hand
from a GitHub Release. This tool makes the *listing itself a checked-in file*
and the *publish action a command* — the same content is uploaded every time,
with no manual form filling.

The content lives in `store_listing/listing.yaml` (the single source of truth).
Even with this script you still have to do the one-time Play Console setup
(invite the service account via Users and permissions and grant it access
under the app — docs/20) and the App-content forms once — those are outside
the store-listing API — but the repeatable part is gone.

Usage
-----
    python3 tool/publish_play.py                     # validate locally, no API
    python3 tool/publish_play.py --listing           # update listing + images, commit
    python3 tool/publish_play.py --aab app.aab --track internal
    python3 tool/publish_play.py --listing --aab app.aab --track production \
        --release-note "Class 10 mock sets refreshed"
    python3 tool/publish_play.py --listing --dry-run # validate + show the plan

Credentials
-----------
A Play service-account key (JSON); the account must have been invited in Play
Console → Users and permissions and granted access under the app (Release
manager is enough for listing + AAB). Reach the key via `--service-account
PATH` or the `GOOGLE_APPLICATION_CREDENTIALS` env var — the same convention
the Firestore tools use. Store that JSON as the GitHub secret
`PLAY_SERVICE_ACCOUNT_JSON` for the workflow (docs/20).

Exit codes: 0 = done, 1 = config/validation error, 2 = API/network failure.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import sys
from pathlib import Path

GREEN, RED, YELLOW, DIM, RESET = '\033[32m', '\033[31m', '\033[33m', '\033[2m', '\033[0m'
if not sys.stdout.isatty() or os.environ.get('NO_COLOR'):
    GREEN = RED = YELLOW = DIM = RESET = ''

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = REPO_ROOT / 'store_listing' / 'listing.yaml'

API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3'
PUBLISHER_SCOPE = 'https://www.googleapis.com/auth/androidpublisher'

LIMITS = {'title': 30, 'short_description': 80, 'full_description': 4000}
IMAGE_TYPES = ('featureGraphic', 'icon', 'phoneScreenshots')
ALLOWED_TRACKS = ('production', 'internal', 'alpha', 'beta')

LANG_RE = re.compile(r'^[a-z]{2}([-_][A-Z]{2})?$')
PACKAGE_RE = re.compile(r'^[a-z][a-z0-9_]{0,100}(\.[a-z][a-z0-9_]{0,100}){1,}$')


# --------------------------------------------------------------------------- #
# local helpers
# --------------------------------------------------------------------------- #
def fail(message: str) -> None:
    print(f'{RED}✗ {message}{RESET}')


def ok(message: str) -> None:
    print(f'{GREEN}✓ {message}{RESET}')


def note(message: str) -> None:
    print(f'{YELLOW}!{RESET} {message}')


def image_size(path: Path) -> tuple[int, int] | None:
    """(width, height) for PNG/JPEG/WebP with the standard library only.

    Play cares about the actual pixels, so we parse the headers instead of
    trusting a filename that says "1080x1920".
    """
    data = path.read_bytes()
    if data[:8] == b'\x89PNG\r\n\x1a\n' and len(data) > 24:
        return struct.unpack('>II', data[16:24])
    if data[:2] == b'\xff\xd8':
        # JPEG SOF0-F stores height then width, unlike PNG. Normalise to
        # (width, height) so callers can check features like 1024x500.
        pos = 2
        while pos + 9 < len(data):
            if data[pos] != 0xFF:
                return None
            marker = data[pos + 1]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack('>HH', data[pos + 5:pos + 9])
                return (width, height)
            pos += 2 + struct.unpack('>H', data[pos + 2:pos + 4])[0]
        return None
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP' and len(data) > 30:
        if data[12:16] == b'VP8X':
            # 24-bit "width - 1" / "height - 1" little-endian fields.
            w = (data[24] | (data[25] << 8) | (data[26] << 16)) & 0xFFFFFF
            h = (data[27] | (data[28] << 8) | (data[29] << 16)) & 0xFFFFFF
            return (1 + w, 1 + h)
        if data[12:16] in (b'VP8 ', b'VP8L'):
            note(f'{path.name}: VP8 dimensions unsupported — treat as a warning only')
    return None


def image_content_type(path: Path) -> str:
    ext = path.suffix.lower()
    return {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
            'webp': 'image/webp'}.get(ext, 'application/octet-stream')


def load_config(path: Path) -> dict:
    try:
        import yaml
    except ImportError as exc:
        fail('PyYAML is required to read listing.yaml.\n    pip install pyyaml')
        raise SystemExit(1) from exc
    try:
        cfg = yaml.safe_load(path.read_text(encoding='utf-8'))
    except yaml.YAMLError as exc:
        fail(f'{path.name} is not valid YAML: {exc}')
        raise SystemExit(2) from exc
    if not isinstance(cfg, dict):
        fail(f'{path.name} must be a YAML mapping')
        raise SystemExit(1) from None
    return cfg


def absolute(path: str | Path) -> Path:
    p = Path(os.path.expanduser(str(path)))
    return p if p.is_absolute() else (REPO_ROOT / p)


# --------------------------------------------------------------------------- #
# validation (no network)
# --------------------------------------------------------------------------- #
def validate(cfg: dict, config_path: Path) -> list[str]:
    problems: list[str] = []

    package = cfg.get('package', '')
    if not PACKAGE_RE.match(str(package)):
        problems.append(f'package "{package}" does not look like a Play application id')
    default_lang = cfg.get('default_language', '')
    if not LANG_RE.match(str(default_lang)):
        problems.append(f'default_language "{default_lang}" is not a BCP-47 tag')

    languages = cfg.get('languages')
    if not isinstance(languages, dict) or not languages:
        problems.append('languages: needs at least one language map')
    else:
        if default_lang not in languages:
            problems.append(f'default_language "{default_lang}" has no entry in languages')
        for lang, data in languages.items():
            if not LANG_RE.match(str(lang)):
                problems.append(f'language "{lang}" is not a BCP-47 tag')
                continue
            for field, limit in LIMITS.items():
                value = data.get(field, '') if isinstance(data, dict) else ''
                if not value or not str(value).strip():
                    problems.append(f'{lang}/{field}: empty')
                elif len(str(value)) > limit:
                    problems.append(f'{lang}/{field}: {len(str(value))} chars > {limit}')

    contact = cfg.get('contact') or {}
    email = str(contact.get('email', ''))
    if not email or '@' not in email:
        problems.append('contact.email: missing or invalid')

    assets = cfg.get('assets') or {}
    icon = absolute(assets.get('icon', ''))
    feature = absolute(assets.get('feature_graphic', ''))
    if not icon.is_file():
        problems.append(f'assets.icon: no file at {icon.relative_to(REPO_ROOT)}')
    else:
        size = image_size(icon)
        if size != (512, 512):
            problems.append(f'assets.icon: must be exactly 512x512, got {size}')
    if not feature.is_file():
        problems.append(f'assets.feature_graphic: no file at {feature.relative_to(REPO_ROOT)}')
    else:
        size = image_size(feature)
        if size != (1024, 500):
            note(f'assets.feature_graphic is {size}; Play expects exactly 1024x500')

    screens = screenshot_list(cfg)
    if len(screens) < 2:
        problems.append(f'need at least 2 phone screenshots (have {len(screens)}) — '
                        f'put real captures in {assets.get("screenshots_dir", "store_listing/screenshots")}')
    elif len(screens) > 8:
        problems.append(f'max 8 phone screenshots, have {len(screens)}')
    for shot in screens:
        size = image_size(shot)
        if size is None:
            problems.append(f'{shot.name}: not a readable PNG/JPEG/WebP')
        elif size[0] < 320:
            problems.append(f'{shot.name}: width {size[0]} is below Play minimum 320px')

    return problems


def screenshot_list(cfg: dict) -> list[Path]:
    assets = cfg.get('assets') or {}
    explicit = assets.get('screenshots')
    if isinstance(explicit, list) and explicit:
        return sorted(absolute(p) for p in explicit)
    directory = absolute(assets.get('screenshots_dir', 'store_listing/screenshots'))
    if not directory.is_dir():
        return []
    return sorted(
        p for p in directory.iterdir()
        if p.is_file() and not p.name.startswith('.')
        and p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp'}
    )


# --------------------------------------------------------------------------- #
# API client (lazy deps)
# --------------------------------------------------------------------------- #
def auth_token(credentials_path: Path | None) -> str:
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
        import requests  # noqa: F401  (used later, listed here for a single error)
    except ImportError as exc:
        fail('google-auth and requests are required for publish operations.\n'
             '    pip install google-auth requests')
        raise SystemExit(2) from exc

    path = credentials_path or os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
    if not path or not Path(path).is_file():
        fail('no service account key — pass --service-account PATH or set '
             'GOOGLE_APPLICATION_CREDENTIALS (docs/20, one-time setup)')
        raise SystemExit(2) from None

    try:
        creds = service_account.Credentials.from_service_account_file(
            str(path), scopes=[PUBLISHER_SCOPE])
        creds.refresh(Request())
    except Exception as exc:  # noqa: BLE001 - surface the raw reason for the operator
        fail(f'could not authenticate with {path}: {exc}')
        raise SystemExit(2) from exc
    return str(creds.token)


class PlayClient:
    def __init__(self, token: str, package: str) -> None:
        import requests
        self.requests = requests
        self.package = package
        self.headers = {'Authorization': f'Bearer {token}'}

    def _url(self, edit_id: str | None = None, suffix: str = '') -> str:
        parts = f'{API_BASE}/applications/{self.package}/edits'
        if edit_id:
            parts += f'/{edit_id}'
        return parts + suffix

    def _request(self, method: str, url: str, **kwargs) -> dict:
        kwargs.setdefault('headers', {})
        kwargs['headers'].update(self.headers)
        resp = self.requests.request(method, url, timeout=900, **kwargs)
        if resp.status_code >= 400:
            body = resp.text[:2000] or '(empty body)'
            fail(f'Play API {resp.status_code} on {method} {url.split("/v3/")[-1]}:\n  {body}')
            raise SystemExit(2) from None
        return resp.json() if resp.content else {}

    def create_edit(self) -> str:
        return self._request('POST', self._url())['id']

    def set_default_language(self, edit_id: str, language: str) -> None:
        self._request('PATCH', self._url(edit_id, '/apps'),
                      json={'defaultLanguage': language})

    def put_listing(self, edit_id: str, language: str, data: dict) -> None:
        body = {
            'language': language,
            'title': data['title'],
            'shortDescription': data['short_description'],
            'fullDescription': data['full_description'],
        }
        contact = data.get('contact') or {}
        if contact.get('email'):
            body['contactEmail'] = contact['email']
        if contact.get('website'):
            body['contactWebsite'] = contact['website']
        if contact.get('phone'):
            body['contactPhone'] = contact['phone']
        self._request('PUT', self._url(edit_id, f'/listings/{language}'), json=body)

    def list_images(self, edit_id: str, language: str, image_type: str) -> list[dict]:
        resp = self._request('GET', self._url(edit_id, f'/listings/{language}/imageTypes/{image_type}'))
        return resp.get('images', [])

    def delete_image(self, edit_id: str, language: str, image_type: str, image_id: str) -> None:
        self._request('DELETE', self._url(edit_id, f'/listings/{language}/images/{image_type}/{image_id}'))

    def upload_image(self, edit_id: str, language: str, image_type: str, path: Path) -> None:
        # Uploads are NOT idempotent — one POST per image — so callers must clear
        # the existing set first via list_images/delete_image.
        self._request(
            'POST',
            self._url(edit_id, f'/listings/{language}/images/{image_type}'),
            data=path.read_bytes(),
            headers={'Content-Type': image_content_type(path)},
        )

    def upload_bundle(self, edit_id: str, path: Path) -> int:
        resp = self._request(
            'POST',
            self._url(edit_id, '/bundles?ackBundleInstallationWarning=true'),
            data=path.read_bytes(),
            headers={'Content-Type': 'application/octet-stream'},
        )
        return int(resp['versionCode'])

    def track_releases(self, edit_id: str, track: str) -> list[dict]:
        resp = self._request('GET', self._url(edit_id, f'/tracks/{track}'))
        return resp.get('releases', [])

    def set_track(self, edit_id: str, track: str, name: str, version_code: int,
                  release_notes: str = '') -> None:
        release: dict = {'name': name, 'versionCodes': [version_code], 'status': 'completed'}
        if release_notes:
            release['releaseNotes'] = [{'language': 'en-US', 'text': release_notes}]
        self._request('PUT', self._url(edit_id, f'/tracks/{track}'),
                      json={'releases': [release]})

    def commit(self, edit_id: str) -> None:
        self._request('POST', self._url(edit_id, ':commit'))


# --------------------------------------------------------------------------- #
# publish steps
# --------------------------------------------------------------------------- #
def publish_listing(client: PlayClient, cfg: dict, edit_id: str) -> None:
    default_lang = cfg['default_language']
    client.set_default_language(edit_id, default_lang)

    for lang, data in cfg['languages'].items():
        client.put_listing(edit_id, lang, data)
        ok(f'listing {lang}: {data["title"]}')

    assets = cfg.get('assets') or {}
    # Icons and the feature graphic are app-wide; the API keys them under the
    # default language. Screenshots fall back to the default listing for any
    # localized language that does not set its own list.
    for image_type, path in (('icon', assets.get('icon')),
                             ('featureGraphic', assets.get('feature_graphic'))):
        if path and absolute(path).is_file():
            for old in client.list_images(edit_id, default_lang, image_type):
                client.delete_image(edit_id, default_lang, image_type, old['id'])
            client.upload_image(edit_id, default_lang, image_type, absolute(path))
            ok(f'uploaded {image_type}')

    screens = screenshot_list(cfg)
    for old in client.list_images(edit_id, default_lang, 'phoneScreenshots'):
        client.delete_image(edit_id, default_lang, 'phoneScreenshots', old['id'])
    for shot in screens:
        client.upload_image(edit_id, default_lang, 'phoneScreenshots', shot)
    ok(f'uploaded {len(screens)} phone screenshots')


def publish_bundle(client: PlayClient, cfg: dict, edit_id: str, aab: Path,
                   track: str, release_note: str) -> None:
    version_code = client.upload_bundle(edit_id, aab)
    ok(f'uploaded AAB {aab.name} (version code {version_code})')

    for release in client.track_releases(edit_id, track):
        if version_code in [int(vc) for vc in release.get('versionCodes', [])]:
            fail(f'version code {version_code} is already on the {track} track — '
                 f'bump the build number in pubspec.yaml first (docs/17, "Every release")')
            raise SystemExit(1) from None

    client.set_track(edit_id, track, cfg.get('release_name', 'via API'), version_code,
                     release_note)
    ok(f'added release to the {track} track (version code {version_code})')


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog='publish_play.py',
        description='Publish the Play Store listing and/or a signed AAB '
                    '(docs/20_PLAY_STORE_API_PUBLISH.md).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--config', default=str(DEFAULT_CONFIG),
                        help=f'listing YAML (default: {DEFAULT_CONFIG.relative_to(REPO_ROOT)})')
    parser.add_argument('--listing', action='store_true',
                        help='publish the listing + images (may be combined with --aab)')
    parser.add_argument('--aab', metavar='FILE',
                        help='upload a signed AAB and set its track (may be combined with --listing)')
    parser.add_argument('--validate', action='store_true',
                        help='validate the listing only, even if --listing/--aab is given')
    parser.add_argument('--track', default='internal', choices=ALLOWED_TRACKS,
                        help='track for the AAB release (default: internal)')
    parser.add_argument('--release-note', default='', help='optional en-US release note for the AAB track')
    parser.add_argument('--service-account', metavar='JSON', default=None,
                        help='Play service-account key (default: GOOGLE_APPLICATION_CREDENTIALS)')
    parser.add_argument('--dry-run', action='store_true',
                        help='validate and print the plan without calling the API')
    return parser.parse_args(argv)


def print_plan(cfg: dict, args: argparse.Namespace) -> None:
    print('\nplan (dry run):')
    if args.listing:
        print(f'  • update listings for {", ".join(cfg["languages"])}')
        print('  • upload icon, feature graphic, phone screenshots'
              f' ({len(screenshot_list(cfg))} files), then commit')
    if args.aab:
        print(f'  • upload {args.aab}, add to the {args.track} track, then commit')


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    config_path = absolute(args.config)
    if not config_path.is_file():
        fail(f'no listing config at {config_path.relative_to(REPO_ROOT)}')
        return 1

    cfg = load_config(config_path)
    problems = validate(cfg, config_path)
    print(f'\nvalidating {config_path.relative_to(REPO_ROOT)} …')
    if problems:
        for problem in problems:
            fail(problem)
        return 1
    ok('listing.yaml is fit to publish')
    site_urls_warn(cfg)

    if args.dry_run:
        print_plan(cfg, args)
        return 0

    has_api_work = not args.validate and bool(args.listing or args.aab)
    if not has_api_work:
        note('validate-only run — pass --listing and/or --aab to publish')
        return 0

    client = PlayClient(auth_token(Path(args.service_account) if args.service_account else None),
                        cfg['package'])
    edit_id = client.create_edit()
    ok(f'opened edit {edit_id} for {cfg["package"]}')

    if args.listing:
        publish_listing(client, cfg, edit_id)
    if args.aab:
        aab = absolute(args.aab)
        if not aab.is_file():
            fail(f'no AAB at {aab.relative_to(REPO_ROOT)}')
            return 1
        publish_bundle(client, cfg, edit_id, aab, args.track, args.release_note)

    client.commit(edit_id)
    ok(f'committed edit {edit_id}')
    note('the listing appears in the Play Console; App content forms (Data '
         'safety, content rating, etc.) are still manual — docs/20')
    return 0


def site_urls_warn(cfg: dict) -> None:
    contact = cfg.get('contact') or {}
    if not contact.get('website') and not contact.get('phone'):
        note('no contact website/phone configured — only email will be published')
    if 'privacy_policy' in str(contact.get('website', '')):
        note('contact.website points at the privacy page, not a developer '
             'website — Play shows this as the contact website')


if __name__ == '__main__':
    raise SystemExit(main())