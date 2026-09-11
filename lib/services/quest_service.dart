/// Daily quests and a persistent bomb inventory.
///
/// Every day at midnight (device-local time) three quests are generated from a
/// fixed pool. Completing a quest adds a "Saved Bomb" to the inventory. The
/// player can drop a Saved Bomb onto the board during gameplay.
///
/// Everything is persisted in SharedPreferences so it survives app restarts.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Quest model ──────────────────────────────────────────────────────────────

enum QuestType {
  /// Clear [target] equations using a specific operator (e.g. '+').
  clearWithOperator,

  /// Clear [target] equations in a single session.
  clearEquations,

  /// Reach a score of [target] in a single session.
  reachScore,

  /// Trigger a cascade of [target] or more steps.
  cascadeCombo,
}

class Quest {
  Quest({
    required this.id,
    required this.type,
    required this.target,
    required this.operatorGlyph,
    required this.label,
    required this.progress,
    required this.completed,
  });

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
        id: json['id'] as String,
        type: QuestType.values.byName(json['type'] as String),
        target: json['target'] as int,
        operatorGlyph: json['operatorGlyph'] as String? ?? '',
        label: json['label'] as String,
        progress: json['progress'] as int,
        completed: json['completed'] as bool,
      );

  final String id;
  final QuestType type;
  final int target;
  final String operatorGlyph;
  final String label;
  int progress;
  bool completed;

  bool get isDone => progress >= target;

  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'target': target,
        'operatorGlyph': operatorGlyph,
        'label': label,
        'progress': progress,
        'completed': completed,
      };
}

// ── Quest pool ───────────────────────────────────────────────────────────────

List<Quest> _buildPool(Random rng) {
  final operators = ['+', '-', '×', '÷'];
  return [
    for (final op in operators)
      Quest(
        id: 'op_$op',
        type: QuestType.clearWithOperator,
        target: 15,
        operatorGlyph: op,
        label: 'Clear 15 "$op" equations',
        progress: 0,
        completed: false,
      ),
    Quest(
      id: 'clear_30',
      type: QuestType.clearEquations,
      target: 30,
      operatorGlyph: '',
      label: 'Clear 30 equations',
      progress: 0,
      completed: false,
    ),
    Quest(
      id: 'score_2000',
      type: QuestType.reachScore,
      target: 2000,
      operatorGlyph: '',
      label: 'Reach 2,000 points',
      progress: 0,
      completed: false,
    ),
    Quest(
      id: 'score_5000',
      type: QuestType.reachScore,
      target: 5000,
      operatorGlyph: '',
      label: 'Reach 5,000 points',
      progress: 0,
      completed: false,
    ),
    Quest(
      id: 'cascade_3',
      type: QuestType.cascadeCombo,
      target: 3,
      operatorGlyph: '',
      label: 'Get a 3-step cascade',
      progress: 0,
      completed: false,
    ),
    Quest(
      id: 'cascade_5',
      type: QuestType.cascadeCombo,
      target: 5,
      operatorGlyph: '',
      label: 'Get a 5-step cascade',
      progress: 0,
      completed: false,
    ),
  ]..shuffle(rng);
}

// ── Service ──────────────────────────────────────────────────────────────────

class QuestService extends ChangeNotifier {
  QuestService._();

  static QuestService? _instance;
  static QuestService get instance => _instance!;

  /// Returns the instance if initialised, null otherwise.
  /// Safe to call before [init] completes (e.g. in tests).
  static QuestService? tryGetInstance() => _instance;

  static const _prefsKeyDate = 'quest_date';
  static const _prefsKeyQuests = 'quest_list';
  static const _prefsKeyBombs = 'saved_bombs';

  List<Quest> _quests = [];
  int _savedBombs = 0;

  List<Quest> get quests => List.unmodifiable(_quests);
  int get savedBombs => _savedBombs;
  int get completedCount => _quests.where((q) => q.completed).length;

  // ── Initialisation ──────────────────────────────────────────────────────

  static Future<QuestService> init() async {
    _instance ??= QuestService._();
    await _instance!._load();
    return _instance!;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _savedBombs = prefs.getInt(_prefsKeyBombs) ?? 0;

    final todayStr = _todayString();
    final savedDate = prefs.getString(_prefsKeyDate) ?? '';

    if (savedDate == todayStr) {
      // Restore today's quests.
      final raw = prefs.getString(_prefsKeyQuests);
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List<dynamic>;
          _quests = list
              .map((e) => Quest.fromJson(e as Map<String, dynamic>))
              .toList();
          return;
        } on Object catch (e) {
          debugPrint('QuestService: failed to parse saved quests: $e');
        }
      }
    }

    // New day (or first launch) — generate fresh quests.
    final pool = _buildPool(Random(todayStr.hashCode));
    _quests = pool.take(3).toList();
    await prefs.setString(_prefsKeyDate, todayStr);
    await _persist(prefs);
  }

  // ── Progress updates ────────────────────────────────────────────────────

  /// Report a single equation clear with the given operator glyph.
  Future<void> onEquationCleared(String operatorGlyph) async {
    bool changed = false;
    for (final q in _quests) {
      if (q.completed) continue;
      if (q.type == QuestType.clearWithOperator &&
          q.operatorGlyph == operatorGlyph) {
        q.progress++;
        changed = true;
      } else if (q.type == QuestType.clearEquations) {
        q.progress++;
        changed = true;
      }
    }
    if (changed) {
      await _checkCompletions();
    }
  }

  /// Report the current session score (called on each score change).
  Future<void> onScoreUpdated(int score) async {
    bool changed = false;
    for (final q in _quests) {
      if (q.completed) continue;
      if (q.type == QuestType.reachScore && score > q.progress) {
        q.progress = score;
        changed = true;
      }
    }
    if (changed) {
      await _checkCompletions();
    }
  }

  /// Report a cascade of [chainLength] steps.
  Future<void> onCascade(int chainLength) async {
    bool changed = false;
    for (final q in _quests) {
      if (q.completed) continue;
      if (q.type == QuestType.cascadeCombo && chainLength > q.progress) {
        q.progress = chainLength;
        changed = true;
      }
    }
    if (changed) {
      await _checkCompletions();
    }
  }

  // ── Bomb inventory ───────────────────────────────────────────────────────

  /// Returns true if a bomb was successfully consumed.
  Future<bool> useSavedBomb() async {
    if (_savedBombs <= 0) return false;
    _savedBombs--;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyBombs, _savedBombs);
    notifyListeners();
    return true;
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _checkCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    int newBombs = 0;
    for (final q in _quests) {
      if (!q.completed && q.isDone) {
        q.completed = true;
        newBombs++;
      }
    }
    if (newBombs > 0) {
      _savedBombs += newBombs;
      await prefs.setInt(_prefsKeyBombs, _savedBombs);
    }
    await _persist(prefs);
    notifyListeners();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    final encoded = jsonEncode(_quests.map((q) => q.toJson()).toList());
    await prefs.setString(_prefsKeyQuests, encoded);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
