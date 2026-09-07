import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static int get highestUnlockedLevel => _prefs.getInt('highest_unlocked_level') ?? 1;

  static void unlockNextLevel(int currentLevelId) {
    if (currentLevelId <= 0) return; // endless mode or invalid
    final currentUnlocked = highestUnlockedLevel;
    if (currentLevelId >= currentUnlocked) {
      _prefs.setInt('highest_unlocked_level', currentLevelId + 1);
    }
  }

  static int getStarsForLevel(int levelId) {
    return _prefs.getInt('stars_for_level_$levelId') ?? 0;
  }

  static void saveStars(int levelId, int stars) {
    if (levelId <= 0) return;
    final currentStars = getStarsForLevel(levelId);
    if (stars > currentStars) {
      _prefs.setInt('stars_for_level_$levelId', stars);
    }
  }
}
