# 🚀 QuizBaaz 3D - Gamified Flutter Quiz & Learning Platform

<div align="center">

![QuizBaaz 3D Banner](assets/images/characters/quizbaaz_mascot_boy.png)

### **A Next-Gen 3D Gamified Quiz Platform built with Flutter**
*Chapter-Wise Question Bank • Daily 10-Question Live Quiz • Live Leaderboard • Yesterday's Champion & In-Game Rewards • 3D Streaks • Zero-Friction Guest Trial • Central Admin Panel*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Keshab1997/quizbaaz-flutter?style=social)](https://github.com/Keshab1997/quizbaaz-flutter)

</div>

---

## 🌟 Key Highlights & Features

1. **🎨 Glassmorphism & Neon Glow Dark UI:**
   - Futuristic Navy Blue + Purple Gradient aesthetic with realistic glossy glassmorphism cards and neon glowing borders.
2. **🏆 Daily 10-Question Competitive Quiz:**
   - 10 fresh questions every single day with real-time countdown timer, speed-based bonus scoring, and anti-cheat mechanisms.
3. **🥇 Yesterday's Champion & In-Game Rewards Tracker:**
   - Everyone on the home screen sees who won yesterday (#1 Podium with 3D trophy), their score, and what in-game reward they earned (Coins, Gems, Power-Ups, Shop Items).
4. **🔥 3D Daily Streak Fire Flame:**
   - Motivating daily streak system with interactive fire animations and weekly milestone rewards.
5. **📚 Chapter-wise JSON Question Bank:**
   - Modular JSON-driven question banks organized by Categories and Chapters (General Science, Tech, History, Geography, Math, etc.).
6. **🚪 Zero-Friction Guest Trial Onboarding:**
   - Visitors can explore the dashboard and play trial quizzes immediately without forced registration, boosting user acquisition.
7. **🛡️ Dynamic Admin Web Control Panel:**
   - Bulk JSON/Excel question uploader, Daily Quiz scheduler, Yesterday's Winner & in-game reward dispatcher.
8. **🌍 Fully Trilingual (English · বাংলা · हिन्दी):**
   - Interface *and* quiz content in three languages from one switch. Picked automatically from the device locale, changeable any time from **Profile → Settings → Language**, stored locally and kept across restarts. The font swaps to Hind Siliguri for Bangla so no glyph is ever missing.
9. **📚 Trilingual Question Bank:**
   - Every question, option and explanation is authored in all three languages and shipped inside the app — so it works with no network, opens instantly, and uses correct board terminology instead of a machine's guess. `tool/validate_questions.py` refuses to let an incomplete or inconsistent bank reach a build.
10. **⚔️ Real 1-vs-1 Battle Arena:**
   - Live Firestore matchmaking finds a same-difficulty opponent (with a cricket-style VS intro + confetti); no real player found → a smart bot takes over so nobody waits. Every match deals **5 questions mixed from all chapters** and **never repeats a question** until the pool cycles. Symmetric scoring (`base + speed bonus + streak bonus`) keeps it fair for both sides; win by forfeit when the opponent drops. See `docs/12_BATTLE_1V1_REAL_PLAYER_PLAN.md`.
11. **🔔 Daily Quiz reminders (on-device):**
   - Native OS notifications at 7:00 PM local, even if the app is killed. Completely free — scheduled on-device, restored after reboot. Streak copy when a streak is live; silent for the rest of the day once you've played. Toggle in Profile → Settings. The home-screen bell opens a local notification inbox (unread badge is real). See `docs/15_LOCAL_NOTIFICATIONS.md`.
12. **📡 Live push via OneSignal (FCM under the hood):**
   - Admin broadcasts and 1v1 pings when the app is killed. Paste the OneSignal App ID into `lib/core/constants/onesignal_config.dart` after uploading the Firebase service-account JSON to OneSignal. See `docs/16_ONESIGNAL_FCM_SETUP.md`.

---

## 📂 Documentation Directory (`/docs`)

All architectural and step-by-step blueprints are documented in the [`docs/`](./docs) folder:

* 📄 **[`01_PROJECT_ROADMAP.md`](./docs/01_PROJECT_ROADMAP.md)**: Complete Architecture, Tech Stack, and Folder Structure.
* 🖥️ **[`02_ALL_PAGES_AND_SCREENS.md`](./docs/02_ALL_PAGES_AND_SCREENS.md)**: Specifications for all 9 main screens and interactive modals.
* 🗄️ **[`03_JSON_DATA_SCHEMAS.md`](./docs/03_JSON_DATA_SCHEMAS.md)**: JSON Schemas for Chapter questions, Daily Quiz, Leaderboards, and Rewards.
* 🚀 **[`04_PHASE_WISE_EXECUTION_PLAN.md`](./docs/04_PHASE_WISE_EXECUTION_PLAN.md)**: Phase-by-phase implementation checklist (Phase 1 to Phase 7).
* 🛡️ **[`05_ADMIN_PANEL_AND_BACKEND_SPEC.md`](./docs/05_ADMIN_PANEL_AND_BACKEND_SPEC.md)**: Admin Web Dashboard and Backend REST API Design.
* 👤 **[`06_USER_AUTHENTICATION_AND_GUEST_TRIAL_FLOW.md`](./docs/06_USER_AUTHENTICATION_AND_GUEST_TRIAL_FLOW.md)**: Guest Visitor Onboarding & 1-Tap Account Upgrade.
* 🔔 **[`15_LOCAL_NOTIFICATIONS.md`](./docs/15_LOCAL_NOTIFICATIONS.md)**: On-device Daily Quiz reminders.
* 📡 **[`16_ONESIGNAL_FCM_SETUP.md`](./docs/16_ONESIGNAL_FCM_SETUP.md)**: OneSignal + FCM live push.

---

## 🏗️ Project Architecture

```text
quizbaaz-flutter/
├── assets/
│   ├── data/                   # JSON Question Banks, Champions & Daily Quiz
│   ├── icons/                  # 3D Glossy Action Icons (Streak Fire, Sword, Shop, etc.)
│   └── images/
│       ├── avatars/            # 3D Player Profile Avatars
│       └── characters/         # 3D Hero & Champion Characters
│
├── docs/                       # Comprehensive Architecture & Step-by-Step Plans
│
├── lib/
│   ├── core/
│   │   ├── constants/          # App Colors, Theme, Asset Paths, Strings
│   │   └── theme/              # Glassmorphism & Neon Glow Theme Configuration
│   ├── data/
│   │   ├── models/             # Question, Chapter, Champion, User, Leaderboard Models
│   │   └── providers/          # Quiz, User, Auth, and Leaderboard Providers
│   └── presentation/
│       ├── screens/            # Dashboard, Daily Quiz, Chapters, Leaderboard, Admin, etc.
│       └── widgets/            # Reusable GlassCard, NeonButton, StreakFlame, Podium
│
└── pubspec.yaml
```

---

## 📱 Tech Stack & Packages

* **Frontend Framework:** Flutter 3.x (Dart 3.x)
* **State Management:** Provider / Riverpod
* **Localisation:** `flutter_localizations` + hand-written catalogues in `lib/l10n/` (en, bn, hi)
* **Typography:** Google Fonts (`Poppins` for en/hi, `Hind Siliguri` for bn)
* **Visual Effects:** Custom Backdrop Filters, Dual Gradients, Box Shadows
* **Animations:** Lottie, Custom Matrix4 Transformations
* **Audio & Feedback:** `audioplayers`, `haptic_feedback`
* **Local Persistence:** `shared_preferences`

---

## 👨‍💻 Author

* **Developer:** Keshab Sarkar ([@Keshab1997](https://github.com/Keshab1997))
* **Repository:** [https://github.com/Keshab1997/quizbaaz-flutter](https://github.com/Keshab1997/quizbaaz-flutter)
