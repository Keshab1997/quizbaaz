# 19 — Firestore → Bundle: প্রশ্ন অফলাইনে নিয়ে আসা

> **টুল:** `tool/pull_firestore_questions.py` · **যাচাই:** `tool/check_service_account.py`
> **CI:** `.github/workflows/content-and-quality.yml` · **তৈরি:** ২০ সেপ্টেম্বর ২০২৬

## কেন দরকার

প্রশ্নের আসল ভাণ্ডার Firestore-এ — `question_banks/{chapterId}/questions/{qid}` — আর
সেগুলো অ্যাপের admin panel থেকে লেখা হয়। অ্যাপ চালু হওয়ার সময় যা করে:

```
assets/data/questions/*.json   (offline floor — প্রতিটি install-এ থাকে, নেট ছাড়াই)
        +
question_banks/…               (live layer — admin-এর নতুন প্রশ্ন)
        =
merge by id, clash হলে Firestore জেতে  →  Hive-এ ক্যাশ
```

অর্থাৎ প্রশ্ন authoring-এর জন্য Firestore-ই ঠিক, কিন্তু **প্রথমবার অ্যাপ খোলা, নেট নেই,
বা ১৫ মিনিটের ক্যাশ মেয়াদ শেষ** — এই তিন অবস্থায় শিক্ষার্থী যা পায় তা পুরোপুরি
asset ব্যাংক থেকেই আসে। asset খালি থাকলে সে খালি chapter দেখে।

এই টুল সেটাই মেরামত করে: Firestore-এর প্রশ্নগুলো **উল্টো দিকে** নামিয়ে asset ব্যাংকে লেখে।

```
Firestore (live)  ──►  assets/data/questions/*.json  ──►  app bundle  ──►  offline-এও প্রশ্ন
     admin panel লেখে          একদিকের কপি (এই টুল)         flutter build
```

**প্রশ্ন authoring-এর ধারা বদলায় না** — আগের মতোই admin panel থেকে যোগ করা হবে;
শুধু release-এর আগে একবার pull চালালে অফলাইন কপিটাও হালনাগাদ হয়ে যাবে।

---

## ⚠️ দুই নম্বর ফাঁদ: সংখ্যা দুইগুণ দেখানো

`QuizRepository._withLiveCounts()` মিলিয়ে দেখায় `bundled + live Firestore count`।
bundle খালি থাকলে এটাই ঠিক। কিন্তু pull করার পরে একই প্রশ্ন **দুই জায়গাতেই** থাকে
(bundle-এ ও Firestore-এ) → অনলাইনে chapter card দুইগুণ সংখ্যা দেখাবে (যেমন ২৩৩ → ৪৬৬)।

তাই `quiz_repository.dart`-এ একটা guard যোগ করা হয়েছে:

```dart
final remote = remoteCounts[chapter.chapterId] ?? 0;
if (remote == 0) return chapter;
// Already bundled — most likely pulled in by
// tool/pull_firestore_questions.py, so the live count is a
// subset of what the card already shows. Adding it again
// would advertise double.
if (chapter.totalQuestions > 0) return chapter;
return chapter.copyWith(totalQuestions: chapter.totalQuestions + remote);
```

ফল: bundle-এ প্রশ্ন থাকলে bundle-এর সংখ্যাই দেখাবে; না থাকলে আগের মতোই live count।
নতুন প্রশ্ন admin-এ যোগ হলে পরের pull-এ `total_questions` আপডেট হয়ে যাবে।

আর `validate_questions.py` `chapters_list.json`-এর `total_questions` ব্যাংকের সঙ্গে
মিলিয়ে দেখে — তাই pull সবসময় `--update-catalog-counts` সহ চালানো উচিত, নইলে
validator "says total_questions=0 but the bank has N" error দেবে।

---

## চালানোর নিয়ম

```bash
# ১) key-টা যাচাই করো (private key কখনো প্রিন্ট হয় না)
python3 tool/check_service_account.py ~/.secrets/quizbaaz-sa.json

# ২) কী বদলাবে দেখো — কিছুই লেখে না
python3 tool/pull_firestore_questions.py --dry-run

# ৩) লেখো
python3 tool/pull_firestore_questions.py --update-catalog-counts

# ৪) repo-র নিজের gate
python3 tool/validate_questions.py
```

| ফ্ল্যাগ | কাজ |
|---|---|
| `--dry-run` | শুধু দেখায় |
| `--check` | কিছু না লিখে "bundle পুরনো কি না" বলে; পুরনো হলে exit 1 (CI gate) |
| `--chapter X` | একটা চ্যাপ্টার (একাধিকবার দিতে পারে) |
| `--prune` | Firestore-এ মোছে যাওয়া প্রশ্ন bundle থেকেও সরায় (ডিফল্টে বন্ধ) |
| `--require-translations` | অসম্পূর্ণ অনুবাদ বাদ দেয় |
| `--include-invalid` | validation ফেল করা প্রশ্নও লেখে (ডিফল্টে বাদ) |
| `--update-catalog-counts` | `chapters_list.json`-এর `total_questions` আপডেট করে |
| `--fixture FILE` | Firestore ছাড়াই rehearsal (দেখো `fixtures/firestore_dump.demo.json`) |
| `--service-account PATH` | key ফাইল সরাসরি বলে দেওয়া |

ডিফল্টে **কিছুই মোছে না**, Firestore-এ **কিছুই লেখা হয় না**, আর
`assets/data/daily_quiz.json`-এ হাত দেওয়া হয় না।

---

## Service account

Firebase Console → ⚙️ Project settings → **Service accounts** → **Generate new private key**।
যে ফাইল নামবে তার ভেতরে `"type": "service_account"` থাকবে — এটাই সঠিক ফাইল
(`google-services.json` নয়!)।

**কোথাও commit করবেন না।** repo-র বাইরে `~/.secrets/`-এ `chmod 600` দিয়ে রাখুন।

> 🔒 **আরও ভালো:** ডিফল্ট `firebase-adminsdk-…` key-তে প্রায় Editor-level ক্ষমতা থাকে।
> শুধু পড়ার জন্য Cloud Console → IAM & Admin → Service Accounts → নতুন অ্যাকাউন্ট
> (`quizbaaz-readonly`) → role **`Cloud Datastore Viewer`** → তার key নিলে
> ফাঁস হলেও কেউ লিখতে/মুছতে পারবে না।

কাজ শেষে key-টা Firebase Console থেকে revoke করে দেওয়াই ভালো অভ্যাস।

---

## GitHub Actions-এ যুক্ত করা (তোমার প্রশ্ন)

হ্যাঁ — CI-তে দরকার, তবে **আলাদা read-only key বানিয়ে** দেবে।

1. উপরের `quizbaaz-readonly` service account-এর JSON নামাও (adminsdk key নয়)।
2. GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `FIREBASE_READONLY_SA`
   - Value: পুরো JSON ফাইলের লেখা (এক লাইনের JSON হলেও চলে)
3. ওই সাহায্যেই `.github/workflows/content-and-quality.yml` কাজ করে:

| Job | কখন | কী করে |
|---|---|---|
| `quality` | প্রতিটি push/PR | `flutter pub get` → `flutter analyze` → `flutter test` → `validate_questions.py` |
| `quality` (drift check) | সাপ্তাহিক/ম্যানুয়াল | `pull_firestore_questions.py --check` — bundle পুরনো হলে job fail |
| `refresh-question-bank` | সাপ্তাহিক/ম্যানুয়াল | Firestore → bundle, তারপর `chore/refresh-question-bank` ব্রাঞ্চে **PR খোলে** |

**নিরাপত্তা:** Secrets শুধু repo-র নিজের workflow-এ পাওয়া যায় — fork-এর PR-এ নয়।
logs-এ GitHub value-টা mask করে দেয়। তবু key-টা read-only রাখলেই সবচেয়ে নিরাপদ।

**স্বয়ংক্রিয় PR কেন (সরাসরি push নয়):** প্রশ্ন শিক্ষার্থীর কাছে যায়, তাই একবার চোখ
বুলিয়ে merge করা ভালো — ভুল প্রশ্ন আটকানোর শেষ সুযোগ সেটাই।

---

## স্বাভাবিক ব্যবহারের ধারা (সুপারিশ)

1. অ্যাপের admin panel থেকে প্রশ্ন যোগ/সম্পাদনা করো (আগের মতোই)।
2. **release-এর আগে** `python3 tool/pull_firestore_questions.py --update-catalog-counts`।
3. `python3 tool/validate_questions.py` — সবুজ হলে commit + push।
4. সাপ্তাহিক CI job নিজে থেকেই প্রশ্ন টেনে PR খুলবে, তাই ভুলে গেলেও কিছু হারাবে না।

---

## যা যা ধরা পড়ে / করতে পারে না

| অবস্থা | আচরণ |
|---|---|
| admin-এ বানানো নতুন চ্যাপ্টার, `chapters_list.json`-এ নেই | warning দিয়ে skip — ওটা অনলাইনে Firestore থেকেই আসে। bundle করতে চাইলে আগে catalogue-এ যোগ করতে হবে |
| প্রশ্নে Bangla/হিন্দি অনুবাদ নেই | warning; `--require-translations` দিলে বাদ |
| option ১টা বা `correct_index` পরিসরের বাইরে | error; বাদ পড়ে (`--include-invalid` ছাড়া), exit code 1 |
| Firestore পড়তে না পারা | পরিষ্কার error, কিছুই লেখা হয় না |
| একই প্রশ্ন দুবার pull | দ্বিতীয়বার `0 file(s) changed` — idempotent, git diff পরিষ্কার |
| প্রশ্নে metadata (`fingerprint`, `created_by`, `batch_id`…) | bundle-এ যায় না — শুধু অ্যাপ যেসব ফিল্ড পড়ে (`QuestionModel.toJson()`) সেগুলোই লেখা হয় |
| প্রশ্নের ক্রম | পুরনো প্রশ্ন আগের জায়গায়, নতুনগুলো শেষে — ছাত্রের তালিকা এলোমেলো হয় না |
| clash (একই id-তে bundle ও Firestore) | Firestore জেতে — অ্যাপের merge নিয়মের সঙ্গে হুবহু |

---

## এতদিনের ফলাফল

প্রথম pull (২০ সেপ্টেম্বর ২০২৬):

```
Firestore: 233 question(s) in 18 chapter(s)   →   18টি ব্যাংক ফাইল আপডেট
validate_questions.py → Question banks are valid ✅
  en 233/233   bn 233/233   hi 233/233   (সব ১০০%)
```

বাকি ৩৮টা চ্যাপ্টার এখনো খালি — ওগুলোতে admin panel থেকে প্রশ্ন যোগ হলে পরের
pull-এই bundle-এ ঢুকে যাবে।
