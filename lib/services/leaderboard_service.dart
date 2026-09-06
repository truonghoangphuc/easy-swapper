/// Game Center and Google Play Games leaderboards.
///
/// Same library and shape as `easy-mathriss/lib/services/ranking_service.dart`,
/// minus the Firestore half. easy-mathriss falls back to Firestore on web and
/// desktop because it ships there; this keeps the platform leaderboards only,
/// and simply reports "unavailable" elsewhere. That decision is worth revisiting
/// if the web build is ever published.
///
/// **The leaderboard ids below are placeholders.** They must be replaced with
/// the real ones before the first submission, and they come from two different
/// places: Play Console mints an Android id that looks like `CgkI...`, and App
/// Store Connect uses whatever string you type into Game Center. Nothing here
/// works until both exist. See RELEASE.md.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

/// Leaderboard identifiers, overridable at build time so the placeholders never
/// have to be edited into source.
abstract final class LeaderboardIds {
  /// From Play Console → Play Games Services → Leaderboards.
  static const android = String.fromEnvironment(
    'leaderboard_android',
    defaultValue: 'REPLACE_WITH_PLAY_LEADERBOARD_ID',
  );

  /// From App Store Connect → Game Center → Leaderboards.
  static const ios = String.fromEnvironment(
    'leaderboard_ios',
    defaultValue: 'easy_swapper_high_score',
  );

  static bool get configured => !android.startsWith('REPLACE_WITH');
}

class LeaderboardService {
  static bool _signedIn = false;

  /// games_services covers Android and iOS only.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isSignedIn => _signedIn;

  /// Signs in, quietly.
  ///
  /// Deliberately fire-and-forget and never rethrown: a player who declines the
  /// Game Center prompt, or has no Play Games account, must still get a game.
  static Future<void> signIn() async {
    if (!isSupported) return;
    try {
      await gs.GamesServices.signIn();
      _signedIn = true;
    } on Object catch (e) {
      debugPrint('LeaderboardService: sign-in declined or failed: $e');
      _signedIn = false;
    }
  }

  /// Submits [score] to the platform leaderboard.
  static Future<void> submitScore(int score) async {
    if (!isSupported || score <= 0) return;
    if (!LeaderboardIds.configured) {
      debugPrint(
        'LeaderboardService: no leaderboard id configured, score not submitted',
      );
      return;
    }
    try {
      await gs.GamesServices.submitScore(
        score: gs.Score(
          androidLeaderboardID: LeaderboardIds.android,
          iOSLeaderboardID: LeaderboardIds.ios,
          value: score,
        ),
      );
    } on Object catch (e) {
      debugPrint('LeaderboardService: submit failed: $e');
    }
  }

  /// Opens the native leaderboard UI.
  ///
  /// Returns false when it could not be shown, so the caller can say something
  /// rather than appearing to do nothing.
  static Future<bool> showLeaderboard() async {
    if (!isSupported || !LeaderboardIds.configured) return false;
    if (!_signedIn) await signIn();
    if (!_signedIn) return false;
    try {
      await gs.GamesServices.showLeaderboards(
        androidLeaderboardID: LeaderboardIds.android,
        iOSLeaderboardID: LeaderboardIds.ios,
      );
      return true;
    } on Object catch (e) {
      debugPrint('LeaderboardService: could not show leaderboards: $e');
      return false;
    }
  }
}
