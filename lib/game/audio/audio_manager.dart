/// Sound effects, and the preference that mutes them.
///
/// Ported from `easy-mathriss/lib/game/audio_manager.dart`, including the part
/// that matters most: every clip is checked against the asset manifest before
/// `loadAll` runs. Without that check a missing file throws inside the audio
/// cache - loudly on web - and takes the rest of the load with it. Here the
/// manager simply stays silent instead.
library;

import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The clips the game plays, by role.
abstract final class Sfx {
  /// A tile sliding into place.
  static const swap = 'move.mp3';

  /// A swap that completed nothing and bounced back.
  static const reject = 'rotate.mp3';

  /// Refilled tiles landing.
  static const drop = 'drop.mp3';

  /// An equation resolving.
  static const clear = 'clear.mp3';

  /// A deep cascade, or a bomb going off.
  static const boom = 'levelup.mp3';

  /// An electric discharging across the board.
  static const zap = 'zap.mp3';

  /// The board deadlocked and the run was wiped.
  static const gameOver = 'gameover.mp3';

  static const all = [swap, reject, drop, clear, boom, zap, gameOver];
}

class AudioManager {
  static const String _prefSfxKey = 'sound_enabled';
  static const String _prefMusicKey = 'music_enabled';

  /// Players kept alive per clip.
  ///
  /// `FlameAudio.play` builds and tears down a player per call, which a
  /// cascading match-three does dozens of times in a second - on Windows that
  /// showed up as a flood of platform-channel churn. A pool reuses its players,
  /// so repeats overlap cleanly and cost nothing to start.
  static const int _maxPlayersPerClip = 4;

  final Map<String, AudioPool> _pools = {};

  bool _ready = false;

  /// Whether sound effects play. Defaults to on, and persists.
  bool soundEnabled = true;

  /// Whether background music plays. Defaults to on, and persists.
  bool musicEnabled = true;

  /// True once the clips are loaded and playable.
  bool get isReady => _ready;

  /// Background music tracks, located in assets/audio/background.
  static const List<String> bgmTracks = [
    'background/sound_1.mp3',
    'background/sound_2.mp3',
    'background/sound_3.mp3',
    'background/sound_4.mp3',
  ];

  Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      soundEnabled = prefs.getBool(_prefSfxKey) ?? true;
      musicEnabled = prefs.getBool(_prefMusicKey) ?? true;
    } on Object catch (e) {
      // No preferences plugin (a plain unit test, say) is not a reason to fail.
      debugPrint('AudioManager: could not read preferences: $e');
    }
  }

  /// Flips the SFX mute state, persists it, and returns the new value.
  Future<bool> toggleSound() async {
    soundEnabled = !soundEnabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSfxKey, soundEnabled);
    } on Object catch (e) {
      debugPrint('AudioManager: could not save SFX preference: $e');
    }
    return soundEnabled;
  }

  /// Flips the Music mute state, persists it, returns the new value.
  Future<bool> toggleMusic() async {
    musicEnabled = !musicEnabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMusicKey, musicEnabled);
      if (musicEnabled) {
        unawaited(FlameAudio.bgm.resume());
      } else {
        unawaited(FlameAudio.bgm.pause());
      }
    } on Object catch (e) {
      debugPrint('AudioManager: could not save Music preference: $e');
    }
    return musicEnabled;
  }

  /// Plays a background music track, stopping any previous one.
  ///
  /// `FlameAudio.bgm` manages its own internal player; pre-caching the tracks
  /// into `audioCache` actually conflicts with it on web (the cached URL and the
  /// BGM player's own load end up racing). Let bgm.play load the file itself.
  void playBgm(int index) {
    if (!_ready) return;
    final track = bgmTracks[index % bgmTracks.length];
    unawaited(
      FlameAudio.bgm.play(track, volume: 0.4).then((_) {
        // If music was toggled off while the track was loading, pause immediately.
        if (!musicEnabled) unawaited(FlameAudio.bgm.pause());
      }).catchError((Object e) {
        // Web may reject certain audio formats — log and continue silently.
        debugPrint('AudioManager: BGM unavailable ($track): $e');
      }),
    );
  }

  void stopBgm() {
    unawaited(FlameAudio.bgm.stop().catchError((Object e) {
      debugPrint('AudioManager: could not stop BGM: $e');
    }));
  }

  Future<void> init() async {
    await loadPrefs();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();

      final missing = [
        for (final clip in Sfx.all)
          if (!assets.contains('assets/audio/$clip')) clip,
      ];
      if (missing.isNotEmpty) {
        debugPrint(
          'AudioManager: staying silent, missing clips: ${missing.join(", ")}',
        );
        return;
      }

      // Only pre-cache SFX pools. BGM tracks are loaded on demand by bgm.play.
      await FlameAudio.audioCache.loadAll(Sfx.all);
      for (final clip in Sfx.all) {
        _pools[clip] = await FlameAudio.createPool(
          clip,
          maxPlayers: _maxPlayersPerClip,
        );
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('AudioManager: audio unavailable, staying silent: $e');
    }
  }

  /// Plays [clip], if audio loaded and sound is on.
  ///
  /// Fire and forget: a sound effect that fails is never worth interrupting a
  /// turn for, so the future is swallowed rather than awaited.
  void play(String clip, {double volume = 0.5}) {
    if (!_ready || !soundEnabled) return;
    final pool = _pools[clip];
    if (pool == null) return;
    unawaited(
      pool.start(volume: volume.clamp(0.0, 1.0)).catchError((Object e) {
        debugPrint('AudioManager: could not play $clip: $e');
        return () async {};
      }),
    );
  }

  /// Releases the pooled players.
  Future<void> dispose() async {
    for (final pool in _pools.values) {
      try {
        await pool.dispose();
      } on Object catch (e) {
        debugPrint('AudioManager: could not dispose a pool: $e');
      }
    }
    _pools.clear();
    _ready = false;
  }
}
