import '../../l10n/app_strings.dart';

/// In-app changelog keyed by the `pubspec.yaml` version name (not build
/// number). Keep in lockstep with `store_listing/whats_new.yaml` — that YAML
/// is what the Play API uploads as release notes.
class WhatsNewCatalog {
  WhatsNewCatalog._();

  static const Map<String, Map<String, List<String>>> _releases = {
    '1.0.22': {
      'en': [
        'Chapter sets feel smoother — the Start and Revise buttons are now bigger, clearer and easier to tap.',
        'Start stands out with a soft glow, while Revise sits calmly beside it — play first, revise anytime.',
        'History → Retry matches the same polished style.',
        'Small design fixes for a cleaner, calmer study flow.',
      ],
      'bn': [
        'চ্যাপ্টার সেট এখন আরও ঝরঝরে — Start ও Revise বাটন আরও বড়, পরিষ্কার ও সহজে চাপার মতো করা হয়েছে।',
        'Start বাটন হালকা গ্লো নিয়ে চোখে পড়ে, পাশে Revise থাকে শান্ত tinted বাটন হিসেবে — আগে খেলুন, যেকোনো সময় পড়ুন।',
        'History ট্যাবের Retry বাটনও একই পরিষ্কার স্টাইলে সাজানো হয়েছে।',
        'পড়ার অভিজ্ঞতা আরও মসৃণ করতে ছোটখাটো ডিজাইন ঠিক করা হয়েছে।',
      ],
      'hi': [
        'चैप्टर सेट अब और भी सहज — Start और Revise बटन अब बड़े, साफ़ और आसानी से दबाए जा सकते हैं।',
        'Start बटन हल्की चमक के साथ सामने दिखता है, पास में Revise शांत tinted बटन के रूप में — पहले खेलें, कभी भी पढ़ें।',
        'History टैब का Retry बटन भी इसी साफ़ स्टाइल में है।',
        'पढ़ाई के अनुभव को सहज बनाने के लिए छोटे डिज़ाइन सुधार किए गए।',
      ],
    },
    '1.0.21': {
      'en': [
        'New Revise mode — open any chapter set as a read-only revision: every question with the correct answer highlighted and its explanation. Nothing is scored.',
        'Guests can now sign in straight from the home screen to save and sync their progress — no need to open Profile.',
        'Chhaya Prakashani Chemistry grew by 181 questions; the bank now holds 1,880 questions across 48 chapters.',
      ],
      'bn': [
        'নতুন রিভাইজ মোড — যেকোনো চ্যাপ্টার সেট পড়ার মোডে খুলুন: প্রতিটি প্রশ্নের সঠিক উত্তর হাইলাইট করা থাকে, সঙ্গে ব্যাখ্যা। কিছুই স্কোর হয় না।',
        'গেস্টরা এখন হোম স্ক্রিন থেকেই সাইন-ইন করে অগ্রগতি সেভ ও সিঙ্ক করতে পারবেন — প্রোফাইলে যাওয়ার দরকার নেই।',
        'ছায়া প্রকাশনী রসায়নে ১৮১টি নতুন প্রশ্ন যোগ হয়েছে; ব্যাঙ্কে এখন ৪৮টি চ্যাপ্টারে ১,৮৮০টি প্রশ্ন।',
      ],
      'hi': [
        'नया रिवाइज़ मोड — किसी भी चैप्टर सेट को सिर्फ़ पढ़ने के मोड में खोलें: हर सवाल के सही उत्तर हाइलाइट और उसका स्पष्टीकरण। कुछ भी स्कोर नहीं होता।',
        'गेस्ट अब होम स्क्रीन से ही साइन-इन कर अपनी प्रगति सेव और सिंक कर सकते हैं — प्रोफ़ाइल पर जाने की ज़रूरत नहीं।',
        'छाया प्रकाशनी रसायन में 181 नए प्रश्न जुड़े; बैंक में अब 48 चैप्टरों में 1,880 प्रश्न हैं।',
      ],
    },
    '1.0.20': {
      'en': [
        'New subject — Chhaya Prakashani — with 1,200+ fresh questions in Physics, Chemistry and Biology.',
        'Daily Quiz: the competition set for the day is now always ready, so your score always reaches the leaderboard.',
        'New questions and subjects now arrive automatically from the admin panel.',
        'Removed the Dark Mode toggle in Profile — it had no effect; the app is always in dark mode.',
      ],
      'bn': [
        'নতুন সাবজেক্ট — ছায়া প্রকাশনী — পদার্থ, রসায়ন ও জীববিজ্ঞানে ১,২০০+ নতুন প্রশ্ন।',
        'ডেইলি কুইজ: দিনের প্রতিযোগিতার সেট এখন সবসময় প্রস্তুত, তাই আপনার স্কোর সবসময় লিডারবোর্ডে পৌঁছাবে।',
        'নতুন প্রশ্ন ও সাবজেক্ট এখন অ্যাডমিন প্যানেল থেকে নিজে থেকেই চলে আসে।',
        'প্রোফাইল থেকে ডার্ক মোড অপশন সরানো হয়েছে — এটি কোনো কাজ করত না; অ্যাপ সবসময় ডার্ক মোডে থাকে।',
      ],
      'hi': [
        'नया विषय — Chhaya Prakashani — भौतिकी, रसायन और जीव विज्ञान में 1,200+ नए प्रश्न।',
        'डेली क्विज़: दिन का प्रतियोगिता सेट अब हमेशा तैयार रहता है, इसलिए आपका स्कोर हमेशा लीडरबोर्ड तक पहुँचता है।',
        'नए प्रश्न और विषय अब एडमिन पैनल से अपने आप आ जाते हैं।',
        'प्रोफ़ाइल से डार्क मोड विकल्प हटा दिया गया — उसका कोई असर नहीं था; ऐप हमेशा डार्क मोड में रहता है।',
      ],
    },
    '1.0.19': {
      'en': [
        'Smart Weekly Streak Calendar: played days show ✓ and missed days show ✕ on the exact weekday.',
        'Battle Arena and Daily Quiz both count toward your daily streak.',
        'Streak Milestone Rewards: unlock bonus Coins, Gems & Power-Ups at 3, 7, 14 and 30 days.',
        'Mistake Notebook: revise questions you missed — answer right twice in a row to master and clear them.',
        'Admin Question Bank: deleted questions and sets now stay permanently hidden across all devices.',
      ],
      'bn': [
        'স্মার্ট স্ট্রিক ক্যালেন্ডার: সপ্তাহের যেদিন খেলবেন সেদিন টিক (✓) এবং মিস হলে ক্রস (✕) দেখাবে।',
        'Daily Quiz এবং Battle Arena — দুটো খেললেই এখন ডেইলি স্ট্রিক বাড়বে।',
        'স্ট্রিক মাইলস্টোন বোনাস: ৩, ৭, ১৪ ও ৩০ দিনের স্ট্রিকে ফ্রি Coins, Gems ও Power-Ups জিতুন।',
        'ভুল প্রশ্নের খাতা (Mistake Notebook): ভুল হওয়া প্রশ্ন আলাদা প্র্যাকটিস করুন — পরপর ২ বার ঠিক উত্তর দিলে ক্লিয়ার হবে।',
        'Admin Question Bank: মুছে ফেলা প্রশ্ন ও সেট এখন স্থায়ীভাবে সব ডিভাইসে সরানো থাকবে।',
      ],
      'hi': [
        'स्मार्ट वीकली स्ट्रीक कैलेंडर: खेले गए दिन पर टिक (✓) और छूटे हुए दिन पर क्रॉस (✕) दिखेगा।',
        'Daily Quiz और Battle Arena — दोनों खेलने पर अब डेली स्ट्रीक बढ़ेगी।',
        'स्ट्रीक माइलस्टोन इनाम: 3, 7, 14 और 30 दिन की स्ट्रीक पर बोनस Coins, Gems और Power-Ups पाएँ।',
        'गलतियों की नोटबुक (Mistake Notebook): गलत हुए प्रश्नों का अभ्यास करें — लगातार 2 बार सही उत्तर देकर क्लियर करें।',
        'Admin Question Bank: हटाए गए प्रश्न और सेट अब सभी डिवाइस से स्थायी रूप से हटेंगे।',
      ],
    },
    '1.0.18': {
      'en': [
        'Smart Weekly Streak Calendar: played days show ✓ and missed days show ✕ on the exact weekday.',
        'Battle Arena and Daily Quiz both count toward your daily streak.',
        'Streak Milestone Rewards: unlock bonus Coins, Gems & Power-Ups at 3, 7, 14 and 30 days.',
        'Mistake Notebook: revise questions you missed — answer right twice in a row to master and clear them.',
      ],
      'bn': [
        'স্মার্ট স্ট্রিক ক্যালেন্ডার: সপ্তাহের যেদিন খেলবেন সেদিন টিক (✓) এবং মিস হলে ক্রস (✕) দেখাবে।',
        'Daily Quiz এবং Battle Arena — দুটো খেললেই এখন ডেইলি স্ট্রিক বাড়বে।',
        'স্ট্রিক মাইলস্টোন বোনাস: ৩, ৭, ১৪ ও ৩০ দিনের স্ট্রিকে ফ্রি Coins, Gems ও Power-Ups জিতুন।',
        'ভুল প্রশ্নের খাতা (Mistake Notebook): ভুল হওয়া প্রশ্ন আলাদা প্র্যাকটিস করুন — পরপর ২ বার ঠিক উত্তর দিলে ক্লিয়ার হবে।',
      ],
      'hi': [
        'स्मार्ट वीकली स्ट्रीक कैलेंडर: खेले गए दिन पर टिक (✓) और छूटे हुए दिन पर क्रॉस (✕) दिखेगा।',
        'Daily Quiz और Battle Arena — दोनों खेलने पर अब डेली स्ट्रीक बढ़ेगी।',
        'स्ट्रीक माइलस्टोन इनाम: 3, 7, 14 और 30 दिन की स्ट्रीक पर बोनस Coins, Gems और Power-Ups पाएँ।',
        'गलतियों की नोटबुक (Mistake Notebook): गलत हुए प्रश्नों का अभ्यास करें — लगातार 2 बार सही उत्तर देकर क्लियर करें।',
      ],
    },
    '1.0.15': {
      'en': [
        'Create a complete subject and its chapters with AI from Chapter Manager.',
        'Add chapters to an existing subject with the AI syllabus assistant.',
        'Review and select AI-generated English, Bangla and Hindi titles and descriptions.',
        'Duplicate chapters and incomplete translations are caught before saving.',
        'Subject and chapter updates are saved together for safer authoring.',
      ],
      'bn': [
        'Chapter Manager থেকে এখন AI-এর সাহায্যে পুরো subject ও তার chapter তৈরি করা যাবে।',
        'Existing subject-এ নতুন chapter যোগ করার জন্য AI syllabus assistant ব্যবহার করুন।',
        'Save করার আগে AI তৈরি করা English, বাংলা ও Hindi title এবং description দেখে বেছে নিন।',
        'Duplicate chapter ও অসম্পূর্ণ translation save হওয়ার আগেই ধরা পড়বে।',
        'Subject ও chapter-এর পরিবর্তন একসঙ্গে নিরাপদে save হবে।',
      ],
      'hi': [
        'Chapter Manager से AI की मदद से subject और chapters बनाएँ।',
        'मौजूदा subject में नए chapters के लिए AI syllabus assistant का उपयोग करें।',
        'Save से पहले English, Bangla और Hindi titles और descriptions review करें।',
        'Duplicate chapters और अधूरे translations save होने से पहले रुकते हैं।',
        'Subject और chapter changes एक साथ सुरक्षित रूप से save होते हैं।',
      ],
    },
    '1.0.13': {
      'en': [
        'Every question now gets 30 seconds, up from 15 — daily quizzes, chapter sets and battles.',
        'The question and all four options fit on one screen, with no scrolling mid-question.',
        'The daily quiz banner now appears once on the first question, then gets out of your way.',
        'Profile avatars no longer clip the top of your head.',
        'In Bangla and Hindi the question no longer repeats an English line underneath.',
      ],
      'bn': [
        'এখন প্রতি প্রশ্নে ৩০ সেকেন্ড, আগে ছিল ১৫ — ডেইলি কুইজ, চ্যাপ্টার সেট ও ব্যাটল সবখানেই।',
        'প্রশ্ন আর চারটি অপশন এবার এক স্ক্রিনেই ঠিক হয়, মাঝপ্রশ্নে স্ক্রল করতে হয় না।',
        'ডেইলি কুইজের ব্যানার এখন শুধু প্রথম প্রশ্নে দেখায়, তারপর পথ ছেড়ে দেয়।',
        'প্রোফাইল অ্যাভাটারে আর মাথার উপরের অংশ কাটা পড়ে না।',
        'বাংলা ও হিন্দিতে প্রশ্নের নিচে আর ইংরেজি লাইন আলাদা করে দেখায় না।',
      ],
      'hi': [
        'अब हर सवाल के 30 सेकंड मिलते हैं, पहले 15 थे — डेली क्विज़, चैप्टर सेट और बैटल तीनों में।',
        'सवाल और चारों विकल्प अब एक ही स्क्रीन पर आ जाते हैं, बीच में स्क्रॉल नहीं करना पड़ता।',
        'डेली क्विज़ का बैनर अब सिर्फ़ पहले सवाल पर दिखता है, फिर रास्ता छोड़ देता है।',
        'प्रोफ़ाइल अवतार में अब सिर का ऊपरी हिस्सा नहीं कटता।',
        'बंगाली और हिन्दी में सवाल के नीचे अब अंग्रेज़ी लाइन नहीं दिखती।',
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

  /// Notes for a release that is **not installed yet**, published remotely
  /// in the Firestore document `config/app` (`AppConfig.latestReleaseNotes`).
  ///
  /// The bundled [_releases] map can never answer this: a phone on 1.0.20
  /// does not carry 1.0.21's notes inside its binary. Looking the *installed*
  /// version up anyway — the old Update Center behaviour — showed the
  /// previous release's notes under the update prompt, which read as if the
  /// new update changed nothing. Remote notes fix that; when none have been
  /// published this returns empty and the caller must say so instead of
  /// falling back to the installed build's notes.
  ///
  /// Pure and static so the decision is unit-testable without Firestore.
  static List<String> upcomingBullets({
    required String installedVersion,
    required String remoteVersion,
    required Map<String, List<String>> remoteNotes,
  }) {
    final version = remoteVersion.trim();
    if (version.isEmpty || version == installedVersion) return const [];
    if (remoteNotes.isEmpty) return const [];
    return remoteNotes[S.code] ?? remoteNotes['en'] ?? const [];
  }
}
