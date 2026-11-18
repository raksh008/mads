import 'finance_models.dart';

/// The result of [computeSafeToSpend]. Every amount is in minor units
/// (paise). A null amount means "can't be worked out", never zero.
class SafeToSpend {
  /// First day of the budget period (local date).
  final DateTime periodStart;

  /// First day of the next period (exclusive end, local date).
  final DateTime periodEnd;

  /// Days left in the period, counting today. Always at least 1.
  final int daysLeft;

  /// The checked balance, adjusted for entries added after the check
  /// ([FinanceState.safeToSpendMinor]).
  final int? balanceNowMinor;

  /// The monthly savings target, kept aside.
  final int? savingsKeptMinor;

  /// For each board, what's still unspent of this month's allocation
  /// (never below 0 per board), added up.
  final int? keptForBoardsMinor;

  /// Balance now minus savings and board money. Can be negative; screens
  /// should show [freeToSpendMinor] instead.
  final int? freeMinor;

  /// Free money spread evenly over the days left. Can be negative; screens
  /// should show [safeTodayDisplayMinor] instead.
  final int? safeTodayMinor;

  /// Not tracked yet; always null for now.
  final double? savingsProgress;

  const SafeToSpend({
    required this.periodStart,
    required this.periodEnd,
    required this.daysLeft,
    required this.balanceNowMinor,
    required this.savingsKeptMinor,
    required this.keptForBoardsMinor,
    required this.freeMinor,
    required this.safeTodayMinor,
    this.savingsProgress,
  });

  /// Free money for display: never below 0. Use [shortfallMinor] to say how
  /// far below zero it really is.
  int? get freeToSpendMinor => _atLeastZero(freeMinor);

  /// How far past savings and board money the balance is, or null when
  /// there's no shortfall (or it can't be worked out).
  int? get shortfallMinor {
    final free = freeMinor;
    return free == null || free >= 0 ? null : -free;
  }

  /// Safe to spend today for display: never below 0.
  int? get safeTodayDisplayMinor => _atLeastZero(safeTodayMinor);

  /// Money in the account that isn't the savings target. An expense bigger
  /// than this would dip into savings.
  int? get aboveSavingsMinor {
    final balance = balanceNowMinor;
    final savings = savingsKeptMinor;
    return balance == null || savings == null ? null : balance - savings;
  }

  static int? _atLeastZero(int? value) =>
      value == null ? null : (value < 0 ? 0 : value);
}

/// Works out how much free money is safe to spend today in the budget period
/// that contains [now]. A period starts on [startDay] (1–28) of a month and
/// runs to the day before [startDay] of the next month, using local dates.
///
/// Free money = balance now − savings target − what each board still has
/// planned this month (its allocation minus what's been spent, never below
/// 0). Safe today = free money ÷ days left, counting today. Board
/// allocations are per calendar month. Bills aren't included.
///
/// Boards in [excludedBoardIds] were answered No ("not in this month's
/// plan"), so nothing is kept aside for them.
SafeToSpend computeSafeToSpend(
  FinanceState state,
  DateTime now, {
  int startDay = 1,
  Set<String> excludedBoardIds = const {},
}) {
  if (startDay < 1 || startDay > 28) {
    throw ArgumentError.value(startDay, 'startDay', 'must be 1–28');
  }
  final today = _localDate(now);
  final periodStart = today.day >= startDay
      ? DateTime(today.year, today.month, startDay)
      : DateTime(today.year, today.month - 1, startDay);
  final periodEnd = DateTime(periodStart.year, periodStart.month + 1, startDay);
  final daysLeft = _daysBetween(today, periodEnd);

  final profile = state.profile;
  final balanceNow = state.safeToSpendMinor;
  if (profile == null || profile.monthlyIncomeMinor == 0 || balanceNow == null) {
    return SafeToSpend(
      periodStart: periodStart,
      periodEnd: periodEnd,
      daysLeft: daysLeft,
      balanceNowMinor: null,
      savingsKeptMinor: null,
      keptForBoardsMinor: null,
      freeMinor: null,
      safeTodayMinor: null,
    );
  }

  final month = periodOf(today);
  var keptForBoards = 0;
  for (final board in state.boards) {
    if (excludedBoardIds.contains(board.id)) continue;
    final unspent =
        state.allocationFor(board.id, month) -
        state.spentFor(board.id, period: month);
    if (unspent > 0) keptForBoards += unspent;
  }

  final savings = profile.plannedSavingsMinor;
  final free = balanceNow - savings - keptForBoards;
  return SafeToSpend(
    periodStart: periodStart,
    periodEnd: periodEnd,
    daysLeft: daysLeft,
    balanceNowMinor: balanceNow,
    savingsKeptMinor: savings,
    keptForBoardsMinor: keptForBoards,
    freeMinor: free,
    safeTodayMinor: free ~/ daysLeft,
  );
}

DateTime _localDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Whole calendar days from [from] up to [to], at least 1. Counted in UTC so
/// a daylight-saving change can't make a day 23 or 25 hours long.
int _daysBetween(DateTime from, DateTime to) {
  final days = DateTime.utc(to.year, to.month, to.day)
      .difference(DateTime.utc(from.year, from.month, from.day))
      .inDays;
  return days < 1 ? 1 : days;
}
