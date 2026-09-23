import '../../l10n/app_strings.dart';

/// In-app changelog keyed by the `pubspec.yaml` version name (not build
/// number). Keep in lockstep with `store_listing/whats_new.yaml` — that YAML
/// is what the Play API uploads as release notes.
class WhatsNewCatalog {
  WhatsNewCatalog._();

  static const Map<String, Map<String, List<String>>> _releases = {
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
        'स्प्लैश और प्रोफ़ाइल पर असली वर्शन नंबर।',
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
