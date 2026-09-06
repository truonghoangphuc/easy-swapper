/// AdMob, structured the same way as
/// `easy-mathriss/lib/services/ad_service.dart`.
///
/// **Every unit here is one of Google's public demo IDs.** Nothing in this file
/// earns anything, and nothing needs to be hidden. Swapping in the real units
/// is a release step - see RELEASE.md - and the shape below is built for it: the
/// production id sits beside the demo one in each getter, chosen by
/// [kReleaseMode], so a debug build can never spend a real impression and a
/// release build can never accidentally serve a test ad.
///
/// easy-mathriss hardcoded its live unit ids in source. Do not copy that part.
/// Pass them at build time instead:
///
///     flutter build appbundle --dart-define=admob_banner_android=ca-app-pub-…
library;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's documented test units. Safe to commit, safe to ship by accident.
abstract final class DemoAdUnits {
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  static const androidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const iosBanner = 'ca-app-pub-3940256099942544/2934735716';

  static const androidRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const iosRewarded = 'ca-app-pub-3940256099942544/1712485313';
}

/// Real units, supplied at build time. Empty means "fall back to the demo unit",
/// which is what keeps a half-configured release from crashing.
abstract final class _LiveAdUnits {
  static const androidBanner =
      String.fromEnvironment('admob_banner_android');
  static const iosBanner = String.fromEnvironment('admob_banner_ios');
  static const androidRewarded =
      String.fromEnvironment('admob_rewarded_android');
  static const iosRewarded = String.fromEnvironment('admob_rewarded_ios');
}

class AdService {
  static BannerAd? _bannerAd;
  static RewardedAd? _rewardedAd;
  static bool _initialised = false;

  /// google_mobile_ads supports Android and iOS only. Windows, macOS, Linux and
  /// web must all skip it, or initialising throws on a platform channel that is
  /// not there.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isReady => _initialised;

  /// True while the demo units are in use, so the UI can say so rather than
  /// letting a tester wonder why the banner reads "Test Ad".
  static bool get usingDemoUnits => _bannerUnitId == _demoBannerUnitId;

  static String get _demoBannerUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? DemoAdUnits.iosBanner
          : DemoAdUnits.androidBanner;

  static String get _bannerUnitId {
    final live = defaultTargetPlatform == TargetPlatform.iOS
        ? _LiveAdUnits.iosBanner
        : _LiveAdUnits.androidBanner;
    return kReleaseMode && live.isNotEmpty ? live : _demoBannerUnitId;
  }

  static String get _rewardedUnitId {
    final live = defaultTargetPlatform == TargetPlatform.iOS
        ? _LiveAdUnits.iosRewarded
        : _LiveAdUnits.androidRewarded;
    if (kReleaseMode && live.isNotEmpty) return live;
    return defaultTargetPlatform == TargetPlatform.iOS
        ? DemoAdUnits.iosRewarded
        : DemoAdUnits.androidRewarded;
  }

  static Future<void> init() async {
    if (!isSupported || _initialised) return;
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      loadRewardedAd();
    } on Object catch (e) {
      debugPrint('AdService: initialise failed, running without ads: $e');
    }
  }

  /// The banner, loaded once and reused.
  ///
  /// [onLoaded] fires when it is ready to show; until then the caller should
  /// reserve no space, or the layout jumps.
  static BannerAd? banner(VoidCallback onLoaded) {
    if (!isSupported || !_initialised) return null;
    if (_bannerAd != null) return _bannerAd;

    _bannerAd = BannerAd(
      adUnitId: _bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdService: banner failed to load: $error');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();

    return _bannerAd;
  }

  static void loadRewardedAd() {
    if (!isSupported || !_initialised) return;
    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('AdService: rewarded failed to load: $error');
          _rewardedAd = null;
        },
      ),
    );
  }

  static bool get hasRewardedAd => _rewardedAd != null;

  /// Shows the rewarded ad, then calls [onReward] if it was watched and
  /// [onDismissed] either way.
  ///
  /// When no ad is available the reward is granted anyway. A missing ad is the
  /// app's problem, not the player's, and easy-mathriss takes the same line -
  /// never let a failed fill block progress.
  static void showRewardedAd({
    required VoidCallback onReward,
    required VoidCallback onDismissed,
  }) {
    final ad = _rewardedAd;
    if (!isSupported || ad == null) {
      onReward();
      onDismissed();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdService: rewarded failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onReward();
        onDismissed();
      },
    );
    ad.show(onUserEarnedReward: (_, _) => onReward());
  }

  static void disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
  }
}
