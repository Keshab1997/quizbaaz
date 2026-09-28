import '../../l10n/app_strings.dart';

/// In-app changelog keyed by the `pubspec.yaml` version name (not build
/// number). Keep in lockstep with `store_listing/whats_new.yaml` — that YAML
/// is what the Play API uploads as release notes.
class WhatsNewCatalog {
  WhatsNewCatalog._();

  static const Map<String, Map<String, List<String>>> _releases = {
    '1.0.13': {
      'en': [
        '30 seconds per question now, up from 15 — daily quiz, chapter sets and battles.',
        'The question and all four options now fit on one screen, with no scrolling.',
        'The daily quiz banner shows on question 1, then gets out of the way.',
        'Profile avatars no longer clip the top of your head.',
        'In Bangla and Hindi the question no longer repeats an English line underneath.',
      ],
      'bn': [
        'এখন প্রতি প্রশ্নে ৩০ সেকেন্ড, আগে ছিল ১৫ — ডেইলি কুইজ, চ্যাপ্টার সেট ও ব্যাটল সবখানে।',
        'প্রশ্ন আর চারটা অপশন এখন এক স্ক্রিনেই ঠিক হয়, স্ক্রল করতে হয় না।',
        'ডেইলি কুইজের ব্যানার প্রথম প্রশ্নে দেখায়, তারপর আর দেখায় না।',
        'প্রোফাইল অ্যাভাটারে আর মাথার উপরের অংশ কাটা যায় না।',
        'বাংলা ও হিন্দিতে প্রশ্নের নিচে আর ইংরেজি লাইন আলাদা করে দেখায় না।',
      ],
      'hi': [
        'अब हर सवाल में 30 सेकंड, पहले थे 15 — डेली क्विज़, चैप्टर सेट और बैटल, तीनों में।',
        'सवाल और चारों विकल्प अब एक ही स्क्रीन में आ जाते हैं, स्क्रॉल नहीं करना पड़ता।',
        'डेली क्विज़ का बैनर पहले सवाल पर दिखता है, उसके बाद नहीं।',
        'प्रोफ़ाइल अवतार में सिर का ऊपरी हिस्सा अब कटता नहीं।',
        'बंगाली और हिन्दी में सवाल के नीचे अब अलग से अंग्रेज़ी लाइन नहीं दिखती।',
      ],
    },
    '1.0.12': {
      'en': [
        '30 seconds per question now, up from 15 — daily quiz, chapter sets and battles.',
        'The question and all four options now fit on one screen, with no scrolling.',
        'The daily quiz banner shows on question 1, then gets out of the way.',
        'Profile avatars no longer clip the top of your head.',
        'In Bangla and Hindi the question no longer repeats an English line underneath.',
      ],
      'bn': [
        'এখন প্রতি প্রশ্নে ৩০ সেকেন্ড, আগে ছিল ১৫ — ডেইলি কুইজ, চ্যাপ্টার সেট ও ব্যাটল সবখানে।',
        'প্রশ্ন আর চারটা অপশন এখন এক স্ক্রিনেই ঠিক হয়, স্ক্রল করতে হয় না।',
        'ডেইলি কুইজের ব্যানার প্রথম প্রশ্নে দেখায়, তারপর আর দেখায় না।',
        'প্রোফাইল অ্যাভাটারে আর মাথার উপরের অংশ কাটা যায় না।',
        'বাংলা ও হিন্দিতে প্রশ্নের নিচে আর ইংরেজি লাইন আলাদা করে দেখায় না।',
      ],
      'hi': [
        'अब हर सवाल में 30 सेकंड, पहले थे 15 — डेली क्विज़, चैप्टर सेट और बैटल, तीनों में।',
        'सवाल और चारों विकल्प अब एक ही स्क्रीन में आ जाते हैं, स्क्रॉल नहीं करना पड़ता।',
        'डेली क्विज़ का बैनर पहले सवाल पर दिखता है, उसके बाद नहीं।',
        'प्रोफ़ाइल अवतार में सिर का ऊपरी हिस्सा अब कटता नहीं।',
        'बंगाली और हिन्दी में सवाल के नीचे अब अलग से अंग्रेज़ी लाइन नहीं दिखती।',
      ],
    },
    '1.0.11': {
      'en': [
        'Daily quiz: your FIRST run of the day is your leaderboard score.',
        'Later runs on the same day can never change that score.',
        'A Score Shield now buys one retry that replaces today\'s score.',
        'The quiz and result screens tell you up front whether a run counts.',
      ],
      'bn': [
        'ডেইলি কুইজ: দিনের প্রথম রানই আপনার লিডারবোর্ড স্কোর।',
        'একই দিনের পরের রান আর সেই স্কোর বদলাতে পারবে না।',
        'স্কোর শিল্ড এখন একটা রিট্রি দেয় — যা আজকের স্কোর বদলে দেয়।',
        'কুইজ ও রেজাল্ট স্ক্রিন আগেই জানিয়ে দেয় এই রান কাউন্ট হবে কি না।',
      ],
      'hi': [
        'डेली क्विज़: दिन की पहली रन ही आपका लीडरबोर्ड स्कोर है।',
        'उसी दिन की बाद की रन उस स्कोर को नहीं बदल सकतीं।',
        'स्कोर शील्ड अब एक रिट्राय देती है जो आज का स्कोर बदल देती है।',
        'क्विज़ और रिज़ल्ट स्क्रीन पहले ही बताती हैं कि रन गिनी जाएगी या नहीं।',
      ],
    },
    '1.0.6': {
      'en': [
        'Google Sign-In fixed on Play Closed testing builds.',
        'Firebase needs both Play App Signing and upload-key SHA-1.',
        'Profile and splash show the real app version.',
      ],
      'bn': [
        'Play Closed testing-এ Google Sign-In ঠিক করা হয়েছে।',
        'Firebase-এ App Signing ও upload-key দুটো SHA-1 লাগবে।',
        'প্রোফাইল ও স্প্ল্যাশে আসল অ্যাপ ভার্সন দেখাবে।',
      ],
      'hi': [
        'Play Closed testing पर Google Sign-In ठीक किया गया।',
        'Firebase में App Signing और upload-key दोनों SHA-1 जोड़ें।',
        'प्रोफ़ाइल और स्प्लैश पर असली ऐप वर्शन दिखेगा।',
      ],
    },
    '1.0.5': {
      'en': [
        'The app now tells you immediately when a new version is installed.',
        'What\'s new dialog on first open after an update.',
        'Real version number on splash and Profile.',
        'Play in-app update so Closed testing testers get the build without hunting the Store.',
      ],
      'bn': [
        'নতুন ভার্সন ইনস্টল হলে অ্যাপ সাথে সাথে জানাবে।',
        'আপডেটের পর প্রথমবার খুললে What\'s new ডায়লগ।',
        'স্প্ল্যাশ ও প্রোফাইলে আসল ভার্সন নম্বর।',
        'Play ইন-অ্যাপ আপডেট — Closed testing টেস্টাররা Store খুঁজে না পেয়েও নতুন বিল্ড পাবেন।',
      ],
      'hi': [
        'नया वर्शन इंस्टॉल होते ही ऐप तुरंत बताएगा।',
        'अपडेट के बाद पहली बार खोलने पर What\'s new डायलॉग।',
        'स्प्लैश और प्रोफ़ाइल पर असली ऐप वर्शन दिखेगा।',
        'Play इन-ऐप अपडेट — Closed testing टेस्टर स्टोर खोजे बिना नया बिल्ड पाएँगे।',
      ],
    },
  };

  static List<String> bulletsFor(String version) {
    final byLang = _releases[version];
    if (byLang == null) return const [];
    return byLang[S.code] ?? byLang['en'] ?? const [];
  }
}
