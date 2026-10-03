// Release broadcast — the push that tells players a new app version shipped.
//
// One HTTP entry point, guarded by a shared secret instead of App Check:
// the caller is the publish pipeline (tool/publish_play.py) or a manual
// curl from the owner's terminal, neither of which carries an App Check
// token. Both secrets live in Secret Manager, never in the repo:
//
//   firebase functions:secrets:set BROADCAST_HOOK_SECRET
//   firebase functions:secrets:set ONESIGNAL_REST_KEY
//
//   POST  https://<region>-<project>.cloudfunctions.net/broadcastAppUpdate
//   headers: { 'x-qb-broadcast-secret': <BROADCAST_HOOK_SECRET> }
//   body:    { 'app_id': '<onesignal app id>', 'version': '1.0.14',
//              'notes': { 'en': '…', 'bn': '…', 'hi': '…' },
//              'include_all': false }
//
// Targeting leans on OneSignal's *native* `app_version` field (recorded on
// every subscription by the SDK itself — no custom tag needed):
// `app_version != <version>` reaches everyone who has not opened the new
// build yet, while already-updated devices stay quiet. `include_all: true`
// bypasses the filter for a deliberate blast.
//
// The tap payload is `data.open = 'app_update'`, which AppNavigator routes
// to the Update Center (changelog + in-app update) on cold start too.
import { timingSafeEqual } from 'crypto';

import { logger, runWith } from 'firebase-functions/v1';
import { defineSecret } from 'firebase-functions/params';

import { REGION } from './options';

const broadcastHookSecret = defineSecret('BROADCAST_HOOK_SECRET');
const oneSignalRestKey = defineSecret('ONESIGNAL_REST_KEY');

const VERSION_RE = /^\d+\.\d+\.\d+$/;
const APP_ID_RE = /^[0-9a-fA-F-]{36}$/;
const LANGS = ['en', 'bn', 'hi'] as const;
type Lang = (typeof LANGS)[number];

interface BroadcastBody {
  app_id?: unknown;
  version?: unknown;
  notes?: unknown;
  include_all?: unknown;
}

/** Headings are version-templated; contents fall back to per-language copy. */
const HEADINGS: Record<Lang, (v: string) => string> = {
  en: (v) => `QuizBaaz ${v} is here 🚀`,
  bn: (v) => `QuizBaaz ${v} এসেছে 🚀`,
  hi: (v) => `QuizBaaz ${v} आ गया है 🚀`,
};

const CONTENT_FALLBACK: Record<Lang, string> = {
  en: "See what's changed and update to the latest version.",
  bn: 'কী নতুন হয়েছে দেখুন আর সর্বশেষ ভার্সনে আপডেট করুন।',
  hi: 'देखिए क्या नया है और सबसे नए वर्शन में अपडेट करिए।',
};

/** Release notes are short — trim hard so no locale hits a wall. */
function contentFor(notes: Record<string, unknown>, lang: Lang): string {
  const raw = (notes[lang] ?? '').toString().trim();
  if (!raw) return CONTENT_FALLBACK[lang];
  return raw.length > 480 ? `${raw.slice(0, 477)}…` : raw;
}

function secretMatches(provided: string | undefined, expected: string): boolean {
  if (!expected) return false;
  const a = Buffer.from(provided ?? '', 'utf8');
  const b = Buffer.from(expected, 'utf8');
  // A length leak is irrelevant for a shared hook secret; keep it simple and
  // constant-time for equal lengths.
  return a.length === b.length && timingSafeEqual(a, b);
}

export const broadcastAppUpdate = runWith({
  secrets: [broadcastHookSecret, oneSignalRestKey],
  memory: '256MB',
  timeoutSeconds: 60,
  maxInstances: 2,
})
  .region(REGION)
  .https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'POST only' });
      return;
    }
    const provided = req.get('x-qb-broadcast-secret') ?? undefined;
    if (!secretMatches(provided, broadcastHookSecret.value())) {
      logger.warn('broadcastAppUpdate: bad or missing secret');
      res.status(401).json({ error: 'unauthorized' });
      return;
    }

    const body = (req.body ?? {}) as BroadcastBody;
    const appId = typeof body.app_id === 'string' ? body.app_id.trim() : '';
    const version = typeof body.version === 'string' ? body.version.trim() : '';
    if (!APP_ID_RE.test(appId)) {
      res.status(400).json({ error: 'app_id must be the OneSignal App ID UUID' });
      return;
    }
    if (!VERSION_RE.test(version)) {
      res.status(400).json({ error: 'version must look like 1.0.14' });
      return;
    }
    const notes = (body.notes ?? {}) as Record<string, unknown>;

    const filters: Array<Record<string, string>> = body.include_all === true
        ? []
        : [{ field: 'app_version', relation: '!=', value: version }];

    const payload: Record<string, unknown> = {
      app_id: appId,
      headings: {
        en: HEADINGS.en(version),
        bn: HEADINGS.bn(version),
        hi: HEADINGS.hi(version),
      },
      contents: {
        en: contentFor(notes, 'en'),
        bn: contentFor(notes, 'bn'),
        hi: contentFor(notes, 'hi'),
      },
      data: { open: 'app_update', version },
      // A release push is worth a day of queueing on a killed app.
      ttl: 86400,
      ...(filters.length > 0 ? { filters } : {}),
    };

    try {
      const resp = await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: {
          Authorization: `Key ${oneSignalRestKey.value()}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      const result = (await resp.json().catch(() => ({}))) as Record<string, unknown>;
      logger.info('broadcastAppUpdate', {
        version,
        status: resp.status,
        recipients: result.recipients ?? 0,
        id: result.id ?? null,
      });
      res.status(resp.ok ? 200 : 502).json({ ok: resp.ok, ...result });
    } catch (err) {
      logger.error('broadcastAppUpdate: OneSignal call failed', err);
      res.status(502).json({ error: 'onesignal request failed' });
    }
  });
