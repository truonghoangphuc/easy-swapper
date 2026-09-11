/// Manages the rotating background images shown behind the game board.
///
/// Backgrounds rotate automatically based on cumulative score so the game
/// feels fresh across a long session, without any player action required.
library;

import 'package:flutter/foundation.dart';

/// All available backgrounds, in the order they cycle.
const List<String> _backgrounds = [
  'assets/images/bg.jpg',       // Math/geometry (default)
  'assets/images/bg_space.jpg', // Space nebula
  'assets/images/bg_ocean.jpg', // Deep ocean
  'assets/images/bg_lava.jpg',  // Lava cave
  'assets/images/bg_forest.jpg',// Enchanted forest
  'assets/images/bg_circuit.jpg',// Cyberpunk circuit
];

/// Score points to accumulate before the background rotates to the next one.
const int _rotationInterval = 1500;

class BackgroundService extends ChangeNotifier {
  BackgroundService();

  int _score = 0;
  int _index = 0;

  /// The currently active background asset path.
  String get current => _backgrounds[_index];

  /// Total number of backgrounds available.
  int get count => _backgrounds.length;

  /// Index of the current background (0-based).
  int get index => _index;

  /// Update the score and rotate the background if a milestone is crossed.
  ///
  /// This is cheap to call on every score update: it just checks an integer
  /// quotient rather than subscribing to a timer.
  void onScoreChanged(int newScore) {
    final previousSlot = _score ~/ _rotationInterval;
    final newSlot = newScore ~/ _rotationInterval;

    _score = newScore;

    if (newSlot != previousSlot) {
      _index = newSlot % _backgrounds.length;
      notifyListeners();
    }
  }

  /// Jump directly to a specific background by index (e.g. for testing or
  /// a future settings screen).
  void jumpTo(int index) {
    assert(index >= 0 && index < _backgrounds.length);
    _index = index;
    notifyListeners();
  }

  /// Reset score and return to the first background (e.g. on new run).
  void reset() {
    _score = 0;
    _index = 0;
    notifyListeners();
  }
}
