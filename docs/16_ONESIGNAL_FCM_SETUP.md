# 16 — OneSignal (FCM under the hood)

Live server-push (admin broadcast, 1v1 challenge ping, “you won yesterday”)
needs Android **FCM** and iOS **APNs**. We do **not** add
`firebase_messaging`. OneSignal owns the FCM token and the dashboard.

Local 19:00 Daily Quiz reminders (docs/15) stay. They work offline with
no App ID. OneSignal is extra, and stays off until the App ID is pasted.

---

## What the app does (already in code)

| Moment | Behaviour |
|---|---|
| After `runApp` | `OneSignal.initialize` + click + foreground listeners (unawaited, 8s timeout) |
| Foreground / tap | Row written to the Hive inbox (`NotificationInbox`) |
| Dashboard ready | `login(firebaseUid or Hive userId)` + tags |
| Profile → Notifications off | `pushSubscription.optOut()` **and** cancel local reminders |
| Google sign-in / sign-out | `login` / `logout` |
| Language change | tag `lang` = `en` / `bn` / `hi` |
| Daily Quiz finished | tag `played_today` / `streak` |

Tags you can segment on in the OneSignal dashboard:

- `lang` · `guest` · `streak` · `played_today`

Click payload (`additionalData`):

```json
{ "open": "daily_quiz" }
```

Other `open` values: `battle`, `online_battle`, `leaderboard`, `shop`.

---

## One-time dashboard setup (you must click this)

OneSignal’s App ID cannot be created from the repo. Do this once:

1. https://onesignal.com → **New App/Website** → **QuizBaaz**.
2. **Google Android (FCM)** → upload a Firebase **service account** JSON:
   - Firebase console → project **quizbaaz-740bd**
   - Project settings → **Service accounts** → Generate new private key
   - Upload in OneSignal → Settings → Push & In-App → Google Android
   - **Never commit that JSON.** Delete the file after upload.
3. Copy **App ID** (36-char UUID) from Settings → Keys & IDs.
4. Paste it into `lib/core/constants/onesignal_config.dart` → `appId`.
5. `flutter pub get && flutter run` on a real device (emulators often
   lack Play Services / FCM).
6. OneSignal dashboard → **New Push** → send to this device.

iOS (later, needs a Mac + Apple Developer):

- OneSignal → Apple iOS → upload a p8 APNs key.
- Xcode: Push Notifications + Background Modes → Remote notifications.
- Optional: Notification Service Extension for images / confirmed delivery
  (not wired in this repo yet).

---

## Sending from our backend (later)

REST: `POST https://onesignal.com/api/v1/notifications` with the
**REST API key** (Settings → Keys & IDs). Put the key in a Cloud Function
secret, never in this repo.

Target a signed-in player with `include_aliases: { external_id: [firebaseUid] }`.

---

## What we deliberately did not add

- `firebase_messaging` (OneSignal already talks to FCM)
- OneSignal Gradle plugin (not required on Flutter SDK 5.x)
- Location module
- Committing a service-account JSON or REST API key
