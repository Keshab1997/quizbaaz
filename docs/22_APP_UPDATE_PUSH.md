# 22 — App update push: banner, notification inbox, Update Center

How a new release reaches a player's phone, end to end:

1. **Release lands on Play** — `tool/publish_play.py --aab …` commits the
   edit (docs/20) and, when the broadcast env vars are set, fires the
   OneSignal push automatically.
2. **Push arrives** — trilingual heading + release notes, tap payload
   `{"open": "app_update"}`.
3. **Tap (or the inbox row, or the dashboard banner)** opens the **Update
   Center** (`lib/presentation/screens/update/update_center_screen.dart`):
   current version, what changed (`WhatsNewCatalog`), flexible in-app
   download (`Update now` → `Restart & update`), Play Store fallback.
4. **After install**, a non-blocking dashboard banner offers the same notes
   once — the old surprise modal and the auto `performImmediateUpdate()`
   are gone by design (`AppUpdateService`).

Client files: `app_update_service.dart` (banner decision, ChangeNotifier),
`update_banner.dart` (dashboard slide-in), `update_center_screen.dart`,
`app_update_play_io.dart` (Play availability/download/install, fail-soft),
`app_navigator.dart` (`case 'app_update'`), `whats_new_catalog.dart`
(notes en/bn/hi, lockstep with `store_listing/whats_new.yaml`).

---

## Targeting: OneSignal's native `app_version`

The OneSignal SDK records `app_version` on every subscription — the app
does **not** send a custom tag. The release push uses:

```json
"filters": [
  { "field": "app_version", "relation": "!=", "value": "1.0.15" }
]
```

So devices already on the new build stay quiet, and devices that have not
opened it yet (still reporting the old version) get the nudge. Check the
`recipients` number in the response — if it looks wrong, fall back to
`"include_all": true`.

Language-specific content is picked automatically by OneSignal from the
`language` the SDK sets (`OneSignal.User.setLanguage`, kept in step with
the in-app language switch) — one send covers en/bn/hi.

---

## Manual send (OneSignal dashboard)

1. https://onesignal.com → **Messages → New push**.
2. Headings/contents (examples; use the release's own notes from
   `store_listing/whats_new.yaml` for the body):

   | | |
   |---|---|
   | en | **QuizBaaz 1.0.15 is here 🚀** — *See what's changed and update to the latest version.* |
   | bn | **QuizBaaz 1.0.15 এসেছে 🚀** — *কী নতুন হয়েছে দেখুন আর সর্বশেষ ভার্সনে আপডেট করুন।* |
   | hi | **QuizBaaz 1.0.15 आ गया है 🚀** — *देखिए क्या नया है और सबसे नए वर्शन में अपडेट करिए।* |

3. **Advanced → data** (this is what routes the tap to the Update Center):

   ```json
   { "open": "app_update", "version": "1.0.15" }
   ```

4. **Target → filter**: `app_version` `is not` `<new version>` (or send to
   all — the Update Center says "you're on the latest version" for
   already-updated devices).

---

## Automated send (Cloud Function + publish hook)

One-time deploy setup (owner):

```bash
cd functions && npm install && npm run build
firebase deploy --only functions
firebase functions:secrets:set BROADCAST_HOOK_SECRET   # any long random string
firebase functions:secrets:set ONESIGNAL_REST_KEY      # OneSignal → Settings → Keys & IDs
```

Then point the publish script at it (local shell or GitHub Actions secret):

```bash
export QB_BROADCAST_URL="https://asia-south1-<project>.cloudfunctions.net/broadcastAppUpdate"
export QB_BROADCAST_SECRET="<same value as BROADCAST_HOOK_SECRET>"
python3 tool/publish_play.py --aab app.aab --track alpha
```

The hook is **best-effort**: missing env vars print a skip note, any
failure is a warning, and the Play publish never turns red because of it.
The OneSignal App ID and the notes are read from
`lib/core/constants/onesignal_config.dart` and
`store_listing/whats_new.yaml` — no copy is duplicated here.

Manual curl (same payload the script sends):

```bash
curl -fsS -X POST "$QB_BROADCAST_URL" \
  -H "x-qb-broadcast-secret: $QB_BROADCAST_SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"app_id":"<onesignal-app-id>","version":"1.0.15",
       "notes":{"en":"…","bn":"…","hi":"…"}}'
```

`"include_all": true` in the body bypasses the `app_version` filter.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| HTTP 401 from the function | `BROADCAST_HOOK_SECRET` header vs the deployed secret |
| `recipients: 0` | OneSignal App ID in the payload; subscription state of the app |
| Updated users still nudged | They have not opened the new build yet — its `app_version` only updates when the SDK reports in |
| Tap opens the dashboard, not the Update Center | Missing `"open": "app_update"` in the data payload (check docs/16) |
| No push at all | `ONESIGNAL_REST_KEY` set? OneSignal → delivery logs |
