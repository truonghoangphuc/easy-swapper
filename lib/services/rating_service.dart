/// Shows the native iOS / Android "Rate this App" prompt at the right moment.
///
/// Backed by the `in_app_review` package. The OS controls whether the dialog
/// actually appears — it rate-limits requests so over-eager calls are silently
/// ignored. We just need to ask at a moment when the player is happy.
library;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RatingService {
  static const _prefKey = 'rating_requested';
  static const _minSessionsKey = 'sessions_played';

  /// Minimum number of sessions (game starts) before we ever ask.
  static const _minSessions = 3;

  static final _review = InAppReview.instance;

  /// Called after a positive moment (new high score, level complete, etc).
  ///
  /// The service checks:
  ///   1. Not already requested this install.
  ///   2. Player has played at least [_minSessions] sessions.
  ///   3. `in_app_review` reports the store is available.
  ///
  /// If all three pass it shows the native prompt and marks it done.
  static Future<void> maybeAsk() async {
    if (kIsWeb) return; // Web has no app store.
    try {
      final prefs = await SharedPreferences.getInstance();

      // Only ask once per install.
      if (prefs.getBool(_prefKey) ?? false) return;

      // Increment session counter on each call to maybeAsk.
      final sessions = (prefs.getInt(_minSessionsKey) ?? 0) + 1;
      await prefs.setInt(_minSessionsKey, sessions);
      if (sessions < _minSessions) return;

      if (!await _review.isAvailable()) return;

      await _review.requestReview();
      await prefs.setBool(_prefKey, true);
    } on Object catch (e) {
      debugPrint('RatingService: could not request review: $e');
    }
  }

  /// Bump the session counter without showing the dialog (call at game start).
  static Future<void> incrementSession() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = (prefs.getInt(_minSessionsKey) ?? 0) + 1;
      await prefs.setInt(_minSessionsKey, sessions);
    } on Object catch (e) {
      debugPrint('RatingService: could not increment session: $e');
    }
  }
}
