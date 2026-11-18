import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/finance_engine.dart';
import 'package:mads/finance/finance_models.dart';

const _boards = [
  ExpenseBoard(id: 'rent', name: 'Rent', iconKey: 'home'),
  ExpenseBoard(id: 'food', name: 'Food', iconKey: 'food'),
];

BudgetAllocation _plan(String id, int amount, String month) =>
    BudgetAllocation(boardId: id, periodStart: month, amountMinor: amount);

FinanceState _state({
  List<BudgetAllocation> plans = const [],
  int balance = 5000000,
  int savings = 1000000,
}) => FinanceState(
  profile: FinancialProfile(
    monthlyIncomeMinor: 6000000,
    balanceMinor: balance,
    unpaidCommitmentsMinor: 0,
    plannedSavingsMinor: savings,
    balanceAsOf: DateTime(2026, 11, 1),
  ),
  boards: _boards,
  allocations: plans,
  transactions: const [],
);

void main() {
  group('carry allocations forward', () {
    final dec = DateTime(2026, 12, 1, 9);

    test('copies last month into the new month', () {
      final s = _state(
        plans: [
          _plan('rent', 2000000, '2026-11-01'),
          _plan('food', 800000, '2026-11-01'),
        ],
      ).withAllocationsCarriedForward(dec);
      expect(s.allocationFor('rent', '2026-12-01'), 2000000);
      expect(s.allocationFor('food', '2026-12-01'), 800000);
      // November is untouched.
      expect(s.allocationFor('rent', '2026-11-01'), 2000000);
    });

    test('keeps what the user already set for the new month, even ₹0', () {
      final s = _state(
        plans: [
          _plan('rent', 2000000, '2026-11-01'),
          _plan('rent', 2200000, '2026-12-01'),
          _plan('food', 800000, '2026-11-01'),
          _plan('food', 0, '2026-12-01'),
        ],
      ).withAllocationsCarriedForward(dec);
      expect(s.allocationFor('rent', '2026-12-01'), 2200000);
      expect(s.allocationFor('food', '2026-12-01'), 0);
    });

    test('is a no-op when run twice or there is nothing to copy', () {
      final once = _state(
        plans: [_plan('rent', 2000000, '2026-11-01')],
      ).withAllocationsCarriedForward(dec);
      expect(identical(once.withAllocationsCarriedForward(dec), once), isTrue);
      final empty = _state();
      expect(identical(empty.withAllocationsCarriedForward(dec), empty), isTrue);
    });

    test('uses the most recent earlier month when a month was skipped', () {
      final s = _state(
        plans: [
          _plan('rent', 1900000, '2026-09-01'),
          _plan('rent', 2000000, '2026-10-01'),
        ],
      ).withAllocationsCarriedForward(dec);
      expect(s.allocationFor('rent', '2026-12-01'), 2000000);
    });

    test('rolls over a year boundary', () {
      final s = _state(
        plans: [_plan('rent', 2000000, '2026-12-01')],
      ).withAllocationsCarriedForward(DateTime(2027, 1, 1));
      expect(s.allocationFor('rent', '2027-01-01'), 2000000);
    });

    test('keeps Safe to Spend steady at the start of a month', () {
      final base = _state(
        plans: [
          _plan('rent', 2000000, '2026-11-01'),
          _plan('food', 800000, '2026-11-01'),
        ],
      );
      final carried = base.withAllocationsCarriedForward(dec);
      final free = computeSafeToSpend(carried, dec).freeMinor;
      expect(free, 5000000 - 1000000 - 2800000);
      // Without carry-forward the free money would balloon.
      expect(computeSafeToSpend(base, dec).freeMinor, 4000000);
    });
  });

  group('shortfall', () {
    final now = DateTime(2026, 11, 18, 12);
    final plans = [
      _plan('rent', 2000000, '2026-11-01'),
      _plan('food', 800000, '2026-11-01'),
    ];

    test('is the real amount, while display stays at zero', () {
      final r = computeSafeToSpend(_state(plans: plans, balance: 2000000), now);
      expect(r.freeMinor, -1800000);
      expect(r.freeToSpendMinor, 0);
      expect(r.shortfallMinor, 1800000);
    });

    test('is null with no shortfall or no profile', () {
      expect(computeSafeToSpend(_state(plans: plans), now).shortfallMinor, isNull);
      final noProfile = FinanceState(
        profile: null,
        boards: _boards,
        allocations: const [],
        transactions: const [],
      );
      expect(computeSafeToSpend(noProfile, now).shortfallMinor, isNull);
    });
  });
}
