/// Game Center (iOS) and Google Play Games (Android) achievements.
///
/// Achievement IDs must be registered in App Store Connect and Play Console
/// before they will actually unlock on device. In debug mode, or when the
/// player is not signed in, unlock calls are silently swallowed.
///
/// ## How to register:
/// - **iOS**: App Store Connect → Your App → Features → Game Center → Achievements
///   Create each achievement and use the exact string IDs below as the identifier.
/// - **Android**: Play Console → Play Games Services → Achievements
///   Create each achievement. The ID will look like `CgkI...` — paste those
///   into the dart-define flags at build time:
///     flutter build appbundle --dart-define=ach_first_clear_android=CgkI...
library;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:shared_preferences/shared_preferences.dart';

/// All achievement identifiers.
///
/// Provide real Android IDs (from Play Console) at build time via --dart-define.
/// iOS uses the string IDs directly (Game Center matches by string).
abstract final class AchievementIds {
  // ── First steps ──────────────────────────────────────────────────────────
  static const firstClearIos = 'ach_first_clear';
  static const firstClearAndroid = String.fromEnvironment(
    'ach_first_clear_android',
    defaultValue: 'ach_first_clear',
  );

  // ── Equation specialist ───────────────────────────────────────────────────
  static const bigEquationIos = 'ach_big_equation';
  static const bigEquationAndroid = String.fromEnvironment(
    'ach_big_equation_android',
    defaultValue: 'ach_big_equation',
  );

  // ── Combos ────────────────────────────────────────────────────────────────
  static const cascadeKingIos = 'ach_cascade_king';
  static const cascadeKingAndroid = String.fromEnvironment(
    'ach_cascade_king_android',
    defaultValue: 'ach_cascade_king',
  );

  // ── Demolition ────────────────────────────────────────────────────────────
  static const demolitionIos = 'ach_demolition';
  static const demolitionAndroid = String.fromEnvironment(
    'ach_demolition_android',
    defaultValue: 'ach_demolition',
  );

  // ── Score milestones ──────────────────────────────────────────────────────
  static const score5kIos = 'ach_score_5000';
  static const score5kAndroid = String.fromEnvironment(
    'ach_score_5000_android',
    defaultValue: 'ach_score_5000',
  );

  static const score10kIos = 'ach_score_10000';
  static const score10kAndroid = String.fromEnvironment(
    'ach_score_10000_android',
    defaultValue: 'ach_score_10000',
  );

  // ── Explorer (saw 3rd background) ────────────────────────────────────────
  static const explorerIos = 'ach_explorer';
  static const explorerAndroid = String.fromEnvironment(
    'ach_explorer_android',
    defaultValue: 'ach_explorer',
  );

  // ── Veteran (played 10 sessions) ─────────────────────────────────────────
  static const veteranIos = 'ach_veteran';
  static const veteranAndroid = String.fromEnvironment(
    'ach_veteran_android',
    defaultValue: 'ach_veteran',
  );
}

class AchievementService {
  static bool _ready = false;

  /// Call once after GamesServices.signIn() succeeds.
  static void markReady() => _ready = true;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Unlocks an achievement silently.
  static Future<void> unlock({
    required String ios,
    required String android,
  }) async {
    if (!isSupported || !_ready) return;
    try {
      await gs.GamesServices.unlock(
        achievement: gs.Achievement(
          androidID: android,
          iOSID: ios,
        ),
      );
    } on Object catch (e) {
      debugPrint('AchievementService: unlock failed ($ios/$android): $e');
    }
  }

  // ── Convenience unlock helpers ───────────────────────────────────────────

  static Future<void> firstClear() => unlock(
        ios: AchievementIds.firstClearIos,
        android: AchievementIds.firstClearAndroid,
      );

  /// Unlock when an equation of [length] tiles is cleared.
  static Future<void> checkBigEquation(int length) async {
    if (length >= 7) {
      await unlock(
        ios: AchievementIds.bigEquationIos,
        android: AchievementIds.bigEquationAndroid,
      );
    }
  }

  /// Unlock when a cascade of [chainLength] steps happens.
  static Future<void> checkCascadeKing(int chainLength) async {
    if (chainLength >= 4) {
      await unlock(
        ios: AchievementIds.cascadeKingIos,
        android: AchievementIds.cascadeKingAndroid,
      );
    }
  }

  /// Unlock when cumulative bombs detonated reaches 3.
  static Future<void> checkDemolition(int bombsDetonated) async {
    if (bombsDetonated >= 3) {
      await unlock(
        ios: AchievementIds.demolitionIos,
        android: AchievementIds.demolitionAndroid,
      );
    }
  }

  /// Unlock score milestones.
  static Future<void> checkScore(int score) async {
    if (score >= 5000) {
      await unlock(
        ios: AchievementIds.score5kIos,
        android: AchievementIds.score5kAndroid,
      );
    }
    if (score >= 10000) {
      await unlock(
        ios: AchievementIds.score10kIos,
        android: AchievementIds.score10kAndroid,
      );
    }
  }

  /// Unlock when the player reaches the 3rd background (≥ 4500 points).
  static Future<void> checkExplorer(int backgroundIndex) async {
    if (backgroundIndex >= 2) {
      await unlock(
        ios: AchievementIds.explorerIos,
        android: AchievementIds.explorerAndroid,
      );
    }
  }

  /// Unlock after 10 sessions.
  static Future<void> checkVeteran() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = (prefs.getInt('veteran_sessions') ?? 0) + 1;
      await prefs.setInt('veteran_sessions', sessions);
      if (sessions >= 10) {
        await unlock(
          ios: AchievementIds.veteranIos,
          android: AchievementIds.veteranAndroid,
        );
      }
    } catch (e) {
      debugPrint('AchievementService: could not check veteran: $e');
    }
  }
}
