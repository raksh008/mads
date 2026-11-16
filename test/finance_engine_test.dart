import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/finance_engine.dart';
import 'package:mads/finance/finance_models.dart';

FinancialProfile _profile({
  int income = 8000000,
  int balance = 6000000,
  int savings = 0,
  DateTime? checkedOn,
}) => FinancialProfile(
  monthlyIncomeMinor: income,
  balanceMinor: balance,
  unpaidCommitmentsMinor: 0,
  plannedSavingsMinor: savings,
  balanceAsOf: checkedOn ?? DateTime(2026, 11, 14, 20), // 14 Nov, 8 pm
);

var _nextId = 0;

FinanceTransaction _txn(
  DateTime when,
  int amountMinor, {
  String boardId = 'food',
  TransactionKind kind = TransactionKind.expense,
  TransactionStatus status = TransactionStatus.posted,
  String source = 'manual',
}) => FinanceTransaction(
  id: 't${_nextId++}',
  boardId: boardId,
  description: 'test',
  amountMinor: amountMinor,
  occurredAt: when,
  kind: kind,
  status: status,
  source: source,
);

const _boards = [
  ExpenseBoard(id: 'food', name: 'Food', iconKey: 'food'),
  ExpenseBoard(id: 'shop', name: 'Shopping', iconKey: 'shop'),
  ExpenseBoard(id: 'fuel', name: 'Fuel', iconKey: 'fuel'),
];

BudgetAllocation _plan(String boardId, int amountMinor, {String? month}) =>
    BudgetAllocation(
      boardId: boardId,
      periodStart: month ?? '2026-11-01',
      amountMinor: amountMinor,
    );

FinanceState _state(
  FinancialProfile? profile, {
  List<FinanceTransaction> transactions = const [],
  List<BudgetAllocation> allocations = const [],
}) => FinanceState(
  profile: profile,
  boards: _boards,
  allocations: allocations,
  transactions: transactions,
);

final _now = DateTime(2026, 11, 14, 21); // 17 days left in November

void main() {
  test('balance 60,000, savings 0, 17 days left gives about 3,529 today', () {
    final result = computeSafeToSpend(_state(_profile()), _now);
    expect(result.daysLeft, 17);
    expect(result.balanceNowMinor, 6000000);
    expect(result.freeMinor, 6000000);
    expect(result.safeTodayMinor, 6000000 ~/ 17); // ₹3,529.41
    expect(result.safeTodayMinor! ~/ 100, 3529);
    expect(result.savingsProgress, isNull);
  });

  test('savings and unspent board money are kept aside', () {
    final result = computeSafeToSpend(
      _state(
        _profile(savings: 2000000),
        allocations: [
          _plan('food', 500000), // 3,000 spent → 2,000 still kept
          _plan('shop', 500000), // 7,000 spent → over, keeps 0 (not −2,000)
          _plan('fuel', 300000, month: '2026-10-01'), // last month: ignored
        ],
        // Added before the 8 pm check, so already in the ₹60,000 balance.
        transactions: [
          _txn(DateTime(2026, 11, 14, 9), 300000, boardId: 'food'),
          _txn(DateTime(2026, 11, 14, 9), 700000, boardId: 'shop'),
        ],
      ),
      _now,
    );
    expect(result.balanceNowMinor, 6000000);
    expect(result.savingsKeptMinor, 2000000);
    expect(result.keptForBoardsMinor, 200000);
    expect(result.freeMinor, 6000000 - 2000000 - 200000);
    expect(result.safeTodayMinor, 3800000 ~/ 17);
  });

  test('nothing free shows 0, never a negative amount', () {
    final result = computeSafeToSpend(
      _state(
        _profile(balance: 1000000, savings: 1000000),
        allocations: [_plan('food', 500000)],
      ),
      _now,
    );
    expect(result.freeMinor, -500000);
    expect(result.freeToSpendMinor, 0);
    expect(result.safeTodayDisplayMinor, 0);
  });

  test('last day of the period allows all free money today', () {
    final result = computeSafeToSpend(
      _state(_profile(savings: 1000000)),
      DateTime(2026, 11, 30, 23, 59),
    );
    expect(result.daysLeft, 1);
    expect(result.safeTodayMinor, 5000000);
  });

  test('startDay 15 runs the period from the 15th to the 14th', () {
    final result = computeSafeToSpend(
      _state(_profile(checkedOn: DateTime(2026, 11, 10))),
      DateTime(2026, 11, 10, 12),
      startDay: 15,
    );
    expect(result.periodStart, DateTime(2026, 10, 15));
    expect(result.periodEnd, DateTime(2026, 11, 15));
    expect(result.daysLeft, 5); // 10th to 14th
    expect(result.safeTodayMinor, 1200000);
  });

  test('no profile or zero income gives null results, never zero', () {
    for (final state in [_state(null), _state(_profile(income: 0))]) {
      final result = computeSafeToSpend(state, _now);
      expect(result.balanceNowMinor, isNull);
      expect(result.freeMinor, isNull);
      expect(result.freeToSpendMinor, isNull);
      expect(result.safeTodayMinor, isNull);
      expect(result.aboveSavingsMinor, isNull);
    }
  });

  test('balance now: expenses out; refunds and income in; transfers not', () {
    final state = _state(
      _profile(checkedOn: DateTime(2026, 11, 1)),
      transactions: [
        _txn(DateTime(2026, 11, 3), 1000000),
        _txn(DateTime(2026, 11, 4), 400000, kind: TransactionKind.refund),
        _txn(DateTime(2026, 11, 5), 2000000, kind: TransactionKind.income),
        _txn(DateTime(2026, 11, 6), 2500000, kind: TransactionKind.transfer),
        _txn(DateTime(2026, 11, 7), 300000, status: TransactionStatus.pending),
      ],
    );
    // 60,000 − 10,000 + 4,000 + 20,000
    expect(state.safeToSpendMinor, 7400000);
    final result = computeSafeToSpend(state, _now);
    expect(result.balanceNowMinor, 7400000); // Safe to Spend uses balance now
    expect(result.freeMinor, 7400000);
  });

  test('same-day entries count only if added after the check time', () {
    final state = _state(
      _profile(checkedOn: DateTime(2026, 11, 14, 10)),
      transactions: [
        _txn(DateTime(2026, 11, 14, 9, 59), 500000), // before: already in bank
        _txn(DateTime(2026, 11, 14, 10, 30), 170000), // after: counts
      ],
    );
    expect(state.transactionsSinceBalanceSnapshotMinor, 170000);
    final result = computeSafeToSpend(state, _now);
    expect(result.balanceNowMinor, 6000000 - 170000);
    expect(result.safeTodayMinor, 5830000 ~/ 17);
  });

  test('above-savings money is balance now minus the savings target', () {
    final result = computeSafeToSpend(
      _state(_profile(savings: 2000000), allocations: [_plan('food', 500000)]),
      _now,
    );
    // Board money isn't savings, so it doesn't reduce this.
    expect(result.aboveSavingsMinor, 4000000);
  });

  test('already-paid entries count on the board but not in Balance now', () {
    final state = _state(
      _profile(checkedOn: DateTime(2026, 11, 14, 10)),
      allocations: [_plan('food', 500000)],
      transactions: [
        // Recorded via "Already paid?" after the check: already in the bank.
        _txn(DateTime(2026, 11, 14, 11), 300000, source: alreadyPaidSource),
        // A normal expense added later still comes off the balance.
        _txn(DateTime(2026, 11, 14, 12), 100000),
      ],
    );
    expect(state.spentFor('food', period: '2026-11-01'), 400000);
    expect(state.transactionsSinceBalanceSnapshotMinor, 100000);
    expect(state.safeToSpendMinor, 6000000 - 100000);
    final result = computeSafeToSpend(state, _now);
    expect(result.balanceNowMinor, 5900000);
    expect(result.keptForBoardsMinor, 100000); // 5,000 plan − 4,000 spent
  });
}
