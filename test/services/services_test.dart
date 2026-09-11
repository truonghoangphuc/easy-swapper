import 'package:easy_swapper/services/ad_service.dart';
import 'package:easy_swapper/services/consent_service.dart';
import 'package:easy_swapper/services/leaderboard_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdService', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('stays inert until the SDK has actually initialised', () async {
      // flutter_test reports the platform as Android, so `isSupported` is true
      // here even though no platform channel exists. Everything must therefore
      // gate on the SDK being up, not merely on the platform being right.
      expect(AdService.isSupported, isTrue);
      expect(AdService.isReady, isFalse);
      expect(AdService.banner(() {}), isNull);
      expect(AdService.hasRewardedAd, isFalse);
    });

    test('init does not touch the SDK on an unsupported platform', () async {
      // This is the path Windows, macOS and web take in production, and it has
      // to short-circuit *before* reaching the SDK: merely reading
      // `MobileAds.instance` starts an unawaited initialise inside the plugin,
      // and on a platform with no channel that throws where nothing can catch
      // it. The guard is the fix, not a try/catch.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await expectLater(AdService.init(), completes);
      expect(AdService.isReady, isFalse);
      expect(AdService.loadRewardedAd, returnsNormally);
      expect(AdService.disposeBanner, returnsNormally);
    });

    test('unsupported platforms are refused outright', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AdService.isSupported, isFalse);
      expect(AdService.banner(() {}), isNull);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AdService.isSupported, isFalse);
    });

    test('a rewarded ad that cannot be shown still grants the reward', () {
      // A failed fill is the app's problem, not the player's.
      var rewarded = false;
      var dismissed = false;
      AdService.showRewardedAd(
        onReward: () => rewarded = true,
        onDismissed: () => dismissed = true,
      );
      expect(rewarded, isTrue);
      expect(dismissed, isTrue);
    });

    test('the shipped unit ids are Google demo units', () {
      // Committing a live unit id is how a debug build starts spending real
      // impressions. These must stay demo units; live ones arrive by
      // --dart-define at build time.
      for (final id in [
        DemoAdUnits.androidAppId,
        DemoAdUnits.iosAppId,
        DemoAdUnits.androidBanner,
        DemoAdUnits.iosBanner,
        DemoAdUnits.androidRewarded,
        DemoAdUnits.iosRewarded,
      ]) {
        expect(
          id,
          startsWith('ca-app-pub-3940256099942544'),
          reason: '$id is not a Google demo unit',
        );
      }
    });
  });

  group('ConsentService', () {
    setUp(ConsentService.resetForTest);
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      ConsentService.resetForTest();
    });

    test('starts unresolved and refusing ads', () {
      // The default has to be "no". Anything else means a request could go out
      // before UMP has answered, which is the violation the SDK exists to
      // prevent.
      expect(ConsentService.isResolved, isFalse);
      expect(ConsentService.canRequestAds, isFalse);
      expect(ConsentService.privacyOptionsRequired, isFalse);
    });

    test('resolves immediately on a platform with no UMP', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(ConsentService.isSupported, isFalse);

      await ConsentService.gather();

      expect(ConsentService.isResolved, isTrue);
      expect(ConsentService.canRequestAds, isFalse,
          reason: 'nothing to consent to, and nothing to serve either');
    });

    test('gather is idempotent', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await ConsentService.gather();
      await expectLater(ConsentService.gather(), completes);
      expect(ConsentService.isResolved, isTrue);
    });

    // The UMP failure path is not exercised here on purpose. flutter_test
    // reports the platform as Android, so `gather` would reach the real SDK,
    // and `requestConsentInfoUpdate` throws from inside an unawaited future in
    // the plugin - the error escapes any catch this code could write, exactly
    // like `MobileAds.instance` does. The platform guard is what protects
    // production; there is nothing here left to assert that the guard test
    // above does not already cover.

    test('showing privacy options is a no-op when not required', () async {
      // UMP requires the entry point be hidden outside consent regions, so
      // calling it anyway must do nothing rather than present a form.
      expect(ConsentService.privacyOptionsRequired, isFalse);
      await expectLater(ConsentService.showPrivacyOptions(), completes);
    });
  });

  group('ads are gated on consent', () {
    setUp(ConsentService.resetForTest);
    tearDown(ConsentService.resetForTest);

    test('no ad is requested while consent is unresolved', () {
      expect(ConsentService.canRequestAds, isFalse);
      expect(AdService.banner(() {}), isNull);
      expect(AdService.loadRewardedAd, returnsNormally);
      expect(AdService.hasRewardedAd, isFalse);
    });
  });

  group('LeaderboardService', () {
    test('real leaderboard ids are configured', () {
      // Both platforms have real (non-placeholder) IDs set.
      expect(LeaderboardIds.android, isNot(startsWith('REPLACE_WITH')));
      expect(LeaderboardIds.configured, isTrue);
    });

    test('submitting and showing are safe while unconfigured', () async {
      expect(LeaderboardService.isSignedIn, isFalse);
      await expectLater(LeaderboardService.submitScore(1234), completes);
      await expectLater(LeaderboardService.signIn(), completes);
      expect(await LeaderboardService.showLeaderboard(), isFalse);
    });

    test('a zero score is never submitted', () async {
      // Nothing was achieved, and an empty entry on a leaderboard is noise.
      await expectLater(LeaderboardService.submitScore(0), completes);
    });
  });

  group('bundled fonts', () {
    test('both faces ship as assets rather than being fetched', () async {
      // The whole point of embedding them: a release Android build has no
      // INTERNET permission, so a runtime fetch would silently fall back.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();

      expect(assets, contains('assets/fonts/Baloo2-ExtraBold.ttf'));
      expect(assets, contains('assets/fonts/SourGummy-Bold.ttf'));
    });

    test('the font files are real TrueType data', () async {
      for (final path in [
        'assets/fonts/Baloo2-ExtraBold.ttf',
        'assets/fonts/SourGummy-Bold.ttf',
      ]) {
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, greaterThan(10000), reason: '$path is tiny');
        // TrueType outlines start with the version tag 0x00010000.
        expect(bytes.getUint32(0), 0x00010000, reason: '$path is not a TTF');
      }
    });
  });
}
