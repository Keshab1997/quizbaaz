# 15 — Local Daily Reminders (no FCM)

QuizBaaz needs to ping students about the Daily Quiz **even when the
app is swiped away**, without Firebase Cloud Messaging, OneSignal, or
any paid push vendor.

This file is the plan that the code in `lib/data/services/notification_*.dart`
implements. If you change the behaviour, change this file in the same commit.

---

## Why not FCM / OneSignal / "a free push SaaS"

The owner rule: **do not use Firebase FCM**, and do not pay.

Facts that decide the architecture:

| Want | Reality |
|---|---|
| Native notification when the app is killed | On Android the OS only delivers *server-push* through **FCM** (or Huawei HMS). On iOS, only **APNs**. |
| OneSignal / SuprSend / SNS / Expo Push | All of them still send Android traffic through FCM. They are a dashboard on top of FCM, not a replacement. |
| Pushy (MQTT, no FCM) | Not free past 100 devices. |
| SMS | Not free, not an in-app notification. |

So there is **no completely-free service** that can fire a live
"someone challenged you" ping to a killed Android app without FCM.

What *is* free, native, and works while killed: **OS-scheduled local
notifications**.

- Android: `AlarmManager` / `WorkManager` via `flutter_local_notifications`,
  restored after reboot by `BOOT_COMPLETED`.
- iOS: `UNCalendarNotificationTrigger`.
- No Google Cloud project, no OneSignal app key, no extra account.

That matches QuizBaaz's real daily loop: *remind this student to play
today's quiz / protect their streak*. It does **not** match live
server events (admin broadcast, 1v1 challenge). Those stay out of
scope until the owner accepts FCM or a paid FCM-free vendor.

---

## What the student sees

One reminder per day, **19:00 local time**.

| Situation | Title / body (via `S.*`) |
|---|---|
| Streak is 0 | `notifDailyTitle` / `notifDailyBody` |
| Streak ≥ 1 and they have not played today | `notifStreakTitle` / `notifStreakBody` (`{n}` = streak) |
| They already played today | No reminder today; next one is tomorrow 19:00 |

Tap (tray or inbox row) opens Daily Quiz via payload `daily_quiz`.
Profile → Settings → **Notifications** is the kill switch. Default is
**on**.

The dashboard bell opens the on-device inbox
(`NotificationHistoryScreen`). A real unread badge appears only when
Hive has unread rows — never a fake red dot. Local reminder *taps*
and OneSignal displays/taps are captured; a fresh install is empty.

---

## Scheduling rules

`NotificationPlanner` is pure Dart (no plugin) so it can be unit-tested.

- Look at **local** `DateTime`, not UTC. India has no DST; other
  locales still get 19:00 in *their* zone via `timezone` +
  `flutter_timezone`.
- Build a **14-day window** of one-shots, not a repeating
  `matchDateTimeComponents` alarm. Repeating cannot skip "already
  played today" without opening the app.
- If `now < today 19:00` and they have **not** played today → first
  fire is today 19:00. Otherwise first fire is tomorrow 19:00.
- Stable notification id per calendar day:
  `21_000_000 + yyyymmdd`, so a reschedule replaces the same slot.
- Every app start, language change, setting toggle, and finished
  Daily Quiz **cancels and rebuilds** the window. If they don't open
  the app for 14 days the reminders stop — they have churned.

Android schedule mode: **`inexactAllowWhileIdle`**.

- Fires in Doze, usually within a few minutes of 19:00.
- Does **not** need `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`
  (Play Store rejects those for a quiz app).

Reboot: the plugin's `ScheduledNotificationBootReceiver` restates
whatever was persisted. The next app open also rebuilds the window.

---

## Permissions (never before first frame)

Same rule as sounds / AdMob / UMP: **do not `await` this before
`runApp`**. A permission dialog or a missing plugin must not freeze
the splash.

1. Hive is ready → first frame.
2. Dashboard post-frame: `UserProvider.initialize()`, then
   `NotificationService.bootstrap()` (unawaited, 5s timeout).
3. Bootstrap asks Android 13+ `POST_NOTIFICATIONS` / iOS alert+sound
   **only if** the Notifications setting is on.
4. Turning the setting **on** from Profile asks again; if the OS
   denies, the switch stays off and `S.notifPermissionDenied` is shown.
5. Turning it **off** cancels every scheduled reminder.

Manifest extras (Android): `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
`VIBRATE`. No exact-alarm permission. Core library desugaring is
required by the plugin.

iOS: `UNUserNotificationCenter` delegate in `AppDelegate.swift`.
No extra Info.plist usage string.

---

## Code map

| File | Role |
|---|---|
| `lib/data/services/notification_planner.dart` | Pure date math |
| `lib/data/services/notification_service.dart` | Plugin wrapper, Hive sync, permission, tap → inbox |
| `lib/data/services/notification_inbox.dart` | ChangeNotifier inbox, Hive persist |
| `lib/data/models/notification_item.dart` | One inbox row |
| `lib/data/providers/user_provider.dart` | `setSetting` + Daily Quiz finish → resync |
| `lib/data/providers/locale_provider.dart` | Language change → resync (copy language) |
| `lib/presentation/screens/dashboard/dashboard_screen.dart` | Bootstrap after first frame; bell → inbox |
| `lib/presentation/screens/notifications/notification_history_screen.dart` | Inbox UI |
| `lib/presentation/screens/profile/profile_screen.dart` | Toggle asks OS permission |
| `test/notification_planner_test.dart` | Planner only — no plugin |
| `test/notification_inbox_test.dart` | Insert / dedup / Hive round-trip |

Web / desktop: `NotificationService.isSupported == false`, all calls
no-op. Widget tests must not crash if the plugin is missing.

---

## Out of scope for *this* file

- Exact-alarm permission, custom alarm sound (the empty WAVs in
  `assets/sounds/` must never be used here)
- Reconstructing local reminders that fired while the app was killed
  *and were never tapped* (the OS does not give Dart a displayed
  callback). Those rows appear once the student taps them.

Live server-push (admin broadcast, 1v1 challenge) is OneSignal + FCM —
see `docs/16_ONESIGNAL_FCM_SETUP.md`. Do **not** add `firebase_messaging`.
