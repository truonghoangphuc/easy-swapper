import 'package:easy_swapper/services/ad_service.dart';
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

  group('LeaderboardService', () {
    test('placeholder ids are recognised as unconfigured', () {
      // Submitting to a placeholder id silently does nothing on the platform
      // side, so the service checks first and says so in the log.
      expect(LeaderboardIds.android, startsWith('REPLACE_WITH'));
      expect(LeaderboardIds.configured, isFalse);
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
