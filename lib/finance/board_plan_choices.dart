import 'package:shared_preferences/shared_preferences.dart';

/// Each board's Yes/No answer to "include in this month's plan?", and
/// whether its one-time "Still a No?" nudge has been shown. Answers are per
/// board per month and are kept on this device only.
class BoardPlanChoices {
  BoardPlanChoices._(this._prefs);

  final SharedPreferences _prefs;

  /// Loads saved answers. Returns null if device storage isn't available,
  /// in which case every board counts as included.
  static Future<BoardPlanChoices?> load() async {
    try {
      return BoardPlanChoices._(await SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  static String _choiceKey(String boardId, String period) =>
      'mads_board_plan_${period}_$boardId';

  static String _nudgeKey(String boardId, String period) =>
      'mads_board_plan_nudged_${period}_$boardId';

  /// true = Yes, false = No, null = not answered yet.
  bool? includedIn(String boardId, String period) =>
      switch (_prefs.getString(_choiceKey(boardId, period))) {
        'yes' => true,
        'no' => false,
        _ => null,
      };

  Future<void> setIncluded(String boardId, String period, bool included) =>
      _prefs.setString(_choiceKey(boardId, period), included ? 'yes' : 'no');

  bool nudgeShown(String boardId, String period) =>
      _prefs.getBool(_nudgeKey(boardId, period)) ?? false;

  Future<void> markNudgeShown(String boardId, String period) =>
      _prefs.setBool(_nudgeKey(boardId, period), true);

  /// The boards answered No for [period].
  Set<String> excludedBoards(Iterable<String> boardIds, String period) => {
    for (final id in boardIds)
      if (includedIn(id, period) == false) id,
  };
}
