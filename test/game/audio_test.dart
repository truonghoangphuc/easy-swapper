import 'package:easy_swapper/game/audio/audio_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('clip manifest', () {
    test('every clip the game names is declared as an asset', () async {
      // The manager silently disables itself when a clip is missing, which is
      // the right runtime behaviour and a terrible way to find out in testing.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();

      for (final clip in Sfx.all) {
        expect(
          assets,
          contains('assets/audio/$clip'),
          reason: '$clip is referenced in code but not shipped',
        );
      }
    });

    test('the roles map to distinct clips where it matters', () {
      expect(Sfx.all.toSet(), hasLength(Sfx.all.length),
          reason: 'two roles sharing a clip is probably a copy-paste slip');
    });
  });

  group('sound preference', () {
    test('defaults to on', () async {
      final audio = AudioManager();
      await audio.loadPrefs();
      expect(audio.soundEnabled, isTrue);
    });

    test('toggling flips and persists', () async {
      final audio = AudioManager();
      await audio.loadPrefs();

      expect(await audio.toggleSound(), isFalse);
      expect(audio.soundEnabled, isFalse);

      // A fresh manager reads back what the last one wrote.
      final reopened = AudioManager();
      await reopened.loadPrefs();
      expect(reopened.soundEnabled, isFalse);
    });

    test('a stored preference is honoured on load', () async {
      SharedPreferences.setMockInitialValues({'sound_enabled': false});
      final audio = AudioManager();
      await audio.loadPrefs();
      expect(audio.soundEnabled, isFalse);
    });
  });

  group('degrading to silence', () {
    test('playing before init does nothing and does not throw', () {
      final audio = AudioManager();
      expect(audio.isReady, isFalse);
      expect(() => audio.play(Sfx.clear), returnsNormally);
    });

    test('playing an unknown clip does not throw', () async {
      final audio = AudioManager();
      await audio.loadPrefs();
      expect(() => audio.play('does-not-exist.mp3'), returnsNormally);
    });

    test('a muted manager stays quiet', () async {
      final audio = AudioManager();
      await audio.loadPrefs();
      await audio.toggleSound();
      expect(audio.soundEnabled, isFalse);
      expect(() => audio.play(Sfx.clear), returnsNormally);
    });
  });
}
