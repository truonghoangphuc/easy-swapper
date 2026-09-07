import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/game_session.dart';

/// Orchestrates saving and loading the game state locally and in the cloud.
class SaveGameService {
  static const String _localKey = 'easy_swapper_save';
  static const String _cloudSlot = 'easy_swapper_save_slot_1';

  static bool get isCloudSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Saves the current game state.
  ///
  /// Writes locally first for immediate persistence (e.g. app killed),
  /// then attempts to sync to Game Center/Google Play if available.
  static Future<void> save(GameSession session) async {
    try {
      final jsonStr = jsonEncode(session.toJson());

      // 1. Save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localKey, jsonStr);

      // 2. Try to sync to cloud (fire-and-forget)
      if (isCloudSupported) {
        // games_services requires sign-in, which LeaderboardService tries at startup.
        try {
          await gs.GamesServices.saveGame(data: jsonStr, name: _cloudSlot);
        } catch (e) {
          debugPrint('SaveGameService: cloud save failed (maybe not signed in): $e');
        }
      }
    } catch (e) {
      debugPrint('SaveGameService: failed to save game: $e');
    }
  }

  /// Loads the saved game state.
  ///
  /// Prefers the local save for speed. If no local save is found, attempts to
  /// load from the cloud. Returns a JSON map if found, or null.
  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSave = prefs.getString(_localKey);

      if (localSave != null && localSave.isNotEmpty) {
        return jsonDecode(localSave) as Map<String, dynamic>;
      }

      if (isCloudSupported) {
        try {
          final cloudSave = await gs.GamesServices.loadGame(name: _cloudSlot);
          if (cloudSave != null && cloudSave.isNotEmpty) {
             // Sync it down locally so next startup is fast
             await prefs.setString(_localKey, cloudSave);
             return jsonDecode(cloudSave) as Map<String, dynamic>;
          }
        } catch (e) {
           debugPrint('SaveGameService: cloud load failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SaveGameService: failed to load game: $e');
    }
    return null;
  }
  
  /// Clears the save (e.g., if a run is hopelessly corrupt or user hard resets)
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localKey);
      if (isCloudSupported) {
        try {
          // Some platforms don't support deleting saved games directly from API easily,
          // but we can just overwrite it with an empty string.
          await gs.GamesServices.saveGame(data: '', name: _cloudSlot);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('SaveGameService: failed to clear save: $e');
    }
  }
}
