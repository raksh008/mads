import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/branding.dart';
import 'package:mads/finance/finance_models.dart';
import 'package:mads/finance/finance_repository.dart';
import 'package:mads/finance/finance_screens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeFinanceRepository implements FinanceRepository {
  _FakeFinanceRepository(this.state);

  FinanceState state;

  @override
  bool cloudReady = true;

  @override
  String get userId => 'test-user';

  @override
  SupabaseClient get client => throw UnimplementedError();

  @override
  Future<FinanceState> load() async => state;

  @override
  Future<void> save(FinanceState value) async {
    state = value;
  }

  @override
  Future<CatalogResolution> resolveCatalogItem(String name) async =>
      CatalogResolution.fallback(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _electricity = ExpenseBoard(
  id: 'electricity',
  name: 'Electricity',
  iconKey: 'bolt',
);

FinanceState _baseState() => FinanceState(
  profile: FinancialProfile(
    monthlyIncomeMinor: 8_000_000,
    balanceMinor: 6_000_000,
    unpaidCommitmentsMinor: 0,
    plannedSavingsMinor: 0,
    balanceAsOf: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  boards: const [_electricity],
  allocations: const [],
  transactions: const [],
);

/// Opens the Electricity board, plans ₹1,000 and saves it.
Future<_FakeFinanceRepository> _planElectricity(WidgetTester tester) async {
  final repository = _FakeFinanceRepository(_baseState());
  await tester.pumpWidget(
    MaterialApp(
      home: ExpenseBoardScreen(
        board: _electricity,
        repository: repository,
        initialState: repository.state,
        onStateChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Monthly amount'),
    '1000',
  );
  final save = find.text('Save monthly budget');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(find.text('Already paid / spent this?'), findsOneWidget);
  return repository;
}

void main() {
  testWidgets('Yes: the amount paid is saved as an expense on the board', (
    tester,
  ) async {
    final repository = await _planElectricity(tester);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    // Asks how much was paid, starting from the planned amount.
    expect(find.text('How much did you pay?'), findsOneWidget);
    final amountField = find.widgetWithText(TextFormField, 'Amount paid');
    expect(
      tester.widget<TextFormField>(amountField).controller!.text,
      '1000',
    );
    await tester.enterText(amountField, '950');
    await tester.tap(find.text('Save payment'));
    await tester.pumpAndSettle();

    final period = periodOf(DateTime.now());
    expect(repository.state.allocationFor('electricity', period), 100_000);
    expect(repository.state.transactions, hasLength(1));
    final expense = repository.state.transactions.single;
    expect(expense.boardId, 'electricity');
    expect(expense.kind, TransactionKind.expense);
    expect(expense.amountMinor, 95_000);
    expect(expense.source, alreadyPaidSource);
    // Spending on the board, but Balance now is unchanged.
    expect(repository.state.spentFor('electricity', period: period), 95_000);
    expect(
      repository.state.safeToSpendMinor,
      repository.state.profile!.balanceMinor,
    );
  });

  testWidgets('No: nothing is saved besides the plan, which stays due', (
    tester,
  ) async {
    final repository = await _planElectricity(tester);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(find.text('How much did you pay?'), findsNothing);
    final period = periodOf(DateTime.now());
    expect(repository.state.allocationFor('electricity', period), 100_000);
    expect(repository.state.transactions, isEmpty);
  });

  testWidgets('bill tiles show Paid ✓ or Due; budget tiles show left/over', (
    tester,
  ) async {
    final now = DateTime.now();
    final period = periodOf(now);
    FinanceTransaction spend(String board, int amount) => FinanceTransaction(
      id: 'spend-$board',
      boardId: board,
      description: board,
      amountMinor: amount,
      occurredAt: now,
    );
    final state = _baseState().copyWith(
      boards: const [
        ExpenseBoard(
          id: 'rent',
          name: 'Rent',
          iconKey: 'home',
          type: BoardType.bill,
          dueDay: 1,
        ),
        ExpenseBoard(
          id: 'subs',
          name: 'Subscriptions',
          iconKey: 'tv',
          type: BoardType.bill,
          dueDay: 31, // moves to the month's last day when it's shorter
        ),
        ExpenseBoard(id: 'shop', name: 'Shopping', iconKey: 'bag'),
        ExpenseBoard(id: 'fuel', name: 'Fuel', iconKey: 'fuel'),
      ],
      allocations: [
        BudgetAllocation(boardId: 'rent', periodStart: period, amountMinor: 1_050_000),
        BudgetAllocation(boardId: 'subs', periodStart: period, amountMinor: 400_000),
        BudgetAllocation(boardId: 'shop', periodStart: period, amountMinor: 500_000),
      ],
      transactions: [
        spend('rent', 1_050_000), // paid in full
        spend('subs', 100_000), // ₹3,000 still due
        spend('shop', 700_000), // spent past the plan: paid
      ],
    );
    final repository = _FakeFinanceRepository(state);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          initialState: state,
          userName: 'Test User',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boards'));
    await tester.pumpAndSettle();

    Finder tileStatus(String board, String status) => find.descendant(
      of: find.ancestor(of: find.text(board), matching: find.byType(Column)).first,
      matching: find.text(status),
    );
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    expect(tileStatus('Rent', 'Paid ✓'), findsOneWidget);
    expect(
      tileStatus(
        'Subscriptions',
        'Due ₹3,000 · $lastDay ${months[now.month - 1]}',
      ),
      findsOneWidget,
    );
    final over = tester.widget<Text>(
      tileStatus('Shopping', 'Over budget by ₹2,000'),
    );
    expect(over.style!.color, madsDanger); // red
    expect(tileStatus('Fuel', 'Budget not set'), findsOneWidget);
  });
}
