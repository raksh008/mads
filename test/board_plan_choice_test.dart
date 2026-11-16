import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/board_plan_choices.dart';
import 'package:mads/finance/finance_engine.dart';
import 'package:mads/finance/finance_models.dart';
import 'package:mads/finance/finance_repository.dart';
import 'package:mads/finance/finance_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
const _groceries = ExpenseBoard(
  id: 'groceries',
  name: 'Groceries',
  iconKey: 'basket',
);

String get _period => periodOf(DateTime.now());

FinanceState _state() => FinanceState(
  profile: FinancialProfile(
    monthlyIncomeMinor: 8_000_000,
    balanceMinor: 6_000_000,
    unpaidCommitmentsMinor: 0,
    plannedSavingsMinor: 0,
    balanceAsOf: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  boards: const [_electricity, _groceries],
  allocations: [
    BudgetAllocation(
      boardId: 'electricity',
      periodStart: _period,
      amountMinor: 200_000,
    ),
    BudgetAllocation(
      boardId: 'groceries',
      periodStart: _period,
      amountMinor: 300_000,
    ),
  ],
  transactions: const [],
);

Future<BoardPlanChoices> _openElectricity(WidgetTester tester) async {
  final choices = (await BoardPlanChoices.load())!;
  final repository = _FakeFinanceRepository(_state());
  await tester.pumpWidget(
    MaterialApp(
      home: ExpenseBoardScreen(
        board: _electricity,
        repository: repository,
        initialState: repository.state,
        onStateChanged: (_) {},
        planChoices: choices,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return choices;
}

Future<void> _answer(WidgetTester tester, String answer) async {
  final button = find.descendant(
    of: find.byType(SegmentedButton<bool>),
    matching: find.text(answer),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Yes includes the board and keeps its plan editor', (
    tester,
  ) async {
    final choices = await _openElectricity(tester);
    expect(choices.includedIn('electricity', _period), isNull);

    await _answer(tester, 'Yes');
    expect(choices.includedIn('electricity', _period), isTrue);
    expect(find.text('Still a No?'), findsNothing);
    expect(find.text('Save monthly budget'), findsOneWidget);
  });

  testWidgets('No nudges once; "Still a No" leaves the board out', (
    tester,
  ) async {
    final choices = await _openElectricity(tester);

    await _answer(tester, 'No');
    expect(find.text('Still a No?'), findsOneWidget);
    await tester.tap(find.text('Still a No'));
    await tester.pumpAndSettle();
    expect(choices.includedIn('electricity', _period), isFalse);
    expect(find.text('Save monthly budget'), findsNothing);
    expect(
      find.text("Not in this month's plan. Spending here is still recorded."),
      findsOneWidget,
    );

    // Back to Yes, then No again: the nudge doesn't come back this month.
    await _answer(tester, 'Yes');
    await _answer(tester, 'No');
    expect(find.text('Still a No?'), findsNothing);
    expect(choices.includedIn('electricity', _period), isFalse);
  });

  testWidgets('"Include it" on the nudge answers Yes instead', (tester) async {
    final choices = await _openElectricity(tester);
    await _answer(tester, 'No');
    await tester.tap(find.text('Include it'));
    await tester.pumpAndSettle();
    expect(choices.includedIn('electricity', _period), isTrue);
    expect(find.text('Save monthly budget'), findsOneWidget);
  });

  test('a No board keeps nothing aside in Safe to Spend', () {
    final state = _state();
    final all = computeSafeToSpend(state, DateTime.now());
    final withoutElectricity = computeSafeToSpend(
      state,
      DateTime.now(),
      excludedBoardIds: {'electricity'},
    );
    expect(all.keptForBoardsMinor, 500_000);
    expect(withoutElectricity.keptForBoardsMinor, 300_000);
    expect(withoutElectricity.freeMinor, all.freeMinor! + 200_000);
  });

  testWidgets('the board tile shows "Not in plan" for a No board', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mads_board_plan_${_period}_electricity': 'no',
    });
    final state = _state();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: _FakeFinanceRepository(state),
          initialState: state,
          userName: 'Test User',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boards'));
    await tester.pumpAndSettle();
    expect(find.text('Not in plan'), findsOneWidget);
    // Groceries is still in the plan, shown as a budget.
    expect(find.text('₹3,000 left of ₹3,000'), findsOneWidget);
  });
}
