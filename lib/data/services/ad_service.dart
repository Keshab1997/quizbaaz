import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/constants/ad_config.dart';
import 'consent_service.dart';
import 'hive_service.dart';

/// App-wide AdMob helper.
///
/// * One banner after initialisation, reused everywhere it is mounted.
/// * Interstitials are preloaded and shown after quiz completion, capped at
///   once every [AdConfig.interstitialFrequency] quizzes.
/// * Ads stay optional: if the SDK fails to load (offline, no Google Play
///   services, etc.) the app silently continues without them.
/// * **Consent-aware:** every ad request is gated on
///   [ConsentService.instance.canRequestAds], so EU/EEA/UK users never see an
///   ad before they have answered Google's UMP consent form (GDPR).
class AdService extends ChangeNotifier {
  AdService._();

  static final AdService instance = AdService._();

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _initialized = false;
  bool _loadingInterstitial = false;

  /// True once the banner ad has loaded and has a real size.
  ///
  /// Before that the platform view reports an unbounded size, which crashes
  /// layout with "given an infinite size" when mounted under the
  /// bottom-navigation Column — and floods every frame with follow-on
  /// semantics assertions. So [banner] stays collapsed until this flips.
  bool _bannerReady = false;

  bool get isInitialized => _initialized;

  /// Call once at app start (after [ConsentService.initialize]). Never throws.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await MobileAds.instance
          .initialize()
          .timeout(const Duration(seconds: 8));
      _initialized = true;
      debugPrint('AdService: initialised');
    } catch (e) {
      debugPrint('AdService: init failed – $e');
    }
  }

  /// Banner widget for the dashboard. Shows [SizedBox.shrink] until the ad is
  /// ready, so the layout never jumps or breaks.
  Widget banner() {
    if (!_initialized || !ConsentService.instance.canRequestAds) {
      return const SizedBox.shrink();
    }

    if (_bannerAd == null) {
      final ad = BannerAd(
        adUnitId: AdConfig.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('AdService: banner loaded');
            if (_bannerAd == ad && !_bannerReady) {
              _bannerReady = true;
              notifyListeners();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('AdService: banner failed – ${error.message}');
            ad.dispose();
            if (_bannerAd == ad) {
              _bannerAd = null;
              if (_bannerReady) {
                _bannerReady = false;
                notifyListeners();
              }
            }
          },
          onAdImpression: (ad) {},
          onAdClicked: (ad) {},
        ),
      );
      _bannerAd = ad;
      ad.load();
      // Not ready yet — mounting the platform view now would hand layout an
      // unbounded (infinite) size and crash every frame until the load lands.
      return const SizedBox.shrink();
    }

    if (!_bannerReady) return const SizedBox.shrink();

    // Fixed 320×50: the platform view must never size itself under the
    // unbounded height of the bottom-navigation Column.
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.25),
        child: SizedBox(
          width: AdSize.banner.width.toDouble(),
          height: AdSize.banner.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }

  /// Preloads the next interstitial so it is ready when a quiz ends.
  /// Safe to call repeatedly. No-op until consent allows ads.
  void preloadInterstitial() {
    if (!_initialized || !ConsentService.instance.canRequestAds) return;
    if (_loadingInterstitial) return;
    if (_interstitialAd != null) return;
    _loadingInterstitial = true;

    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _loadingInterstitial = false;
          debugPrint('AdService: interstitial loaded');
        },
        // google_mobile_ads 9.x: the failure callback carries only the
        // LoadAdError — there is no ad object to dispose here.
        onAdFailedToLoad: (error) {
          debugPrint('AdService: interstitial failed – ${error.message}');
          _interstitialAd = null;
          _loadingInterstitial = false;
        },
      ),
    );
  }

  /// Shows the interstitial after a finished quiz, honouring the frequency
  /// cap. Call from the quiz result screen's first frame.
  Future<void> showInterstitialAfterQuiz() async {
    if (!_initialized || !ConsentService.instance.canRequestAds) return;

    // Count completions in Hive so the cap survives restarts.
    var count = HiveService.getMeta<int>(AdConfig.quizCounterKey) ?? 0;
    count++;
    await HiveService.setMeta(AdConfig.quizCounterKey, count);
    if (count % AdConfig.interstitialFrequency != 0) return;

    if (_interstitialAd == null) {
      preloadInterstitial();
      // Give the load a moment; if it is not ready, skip this quiz.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final ad = _interstitialAd;
    if (ad == null) return;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('AdService: interstitial dismissed');
        ad.dispose();
        _interstitialAd = null;
        preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdService: interstitial show failed – ${error.message}');
        ad.dispose();
        _interstitialAd = null;
      },
      onAdShowedFullScreenContent: (ad) =>
          debugPrint('AdService: interstitial shown'),
    );

    try {
      await ad.show();
    } catch (e) {
      debugPrint('AdService: show error – $e');
    }
  }

  /// Frees the banner (used when leaving the dashboard).
  void disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    if (_bannerReady) {
      _bannerReady = false;
      notifyListeners();
    }
  }
}
