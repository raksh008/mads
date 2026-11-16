import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('boards saved before types existed read as budgets', () {
    final board = ExpenseBoard.fromJson({
      'id': 'old',
      'name': 'Groceries',
      'iconKey': 'basket',
    });
    expect(board.type, BoardType.budget);
    expect(board.dueDay, isNull);
  });

  test('a bill keeps its type and due day when saved and read back', () {
    const bill = ExpenseBoard(
      id: 'rent',
      name: 'Rent',
      iconKey: 'home',
      type: BoardType.bill,
      dueDay: 5,
    );
    final copy = ExpenseBoard.fromJson(bill.toJson());
    expect(copy.type, BoardType.bill);
    expect(copy.dueDay, 5);
    expect(copy.dueDateIn(DateTime(2026, 11, 14)), DateTime(2026, 11, 5));
    // A 31st due day falls on the last day of shorter months.
    expect(
      bill.copyWith(dueDay: 31).dueDateIn(DateTime(2026, 2, 1)),
      DateTime(2026, 2, 28),
    );
  });

  testWidgets('Add board lets you pick Bill with a due day', (tester) async {
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<NewBoardDetails>(
                context,
                MaterialPageRoute(builder: (_) => const AddExpenseBoardScreen()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Board name'),
      'Internet',
    );
    // Budget is the default; switching to Bill asks for a due day.
    expect(find.text('Due day of the month'), findsNothing);
    await tester.tap(find.text('Bill'));
    await tester.pumpAndSettle();
    final dueDay = find.widgetWithText(TextFormField, 'Due day of the month');
    await tester.enterText(dueDay, '40');
    final addButton = find.widgetWithText(FilledButton, 'Add board');
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('Enter a day from 1 to 31.'), findsOneWidget);

    await tester.enterText(dueDay, '7');
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    final details = result! as NewBoardDetails;
    expect(details.name, 'Internet');
    expect(details.type, BoardType.bill);
    expect(details.dueDay, 7);
  });

  testWidgets('a board can switch from Budget to Bill on its screen', (
    tester,
  ) async {
    const board = ExpenseBoard(id: 'rent', name: 'Rent', iconKey: 'home');
    final repository = _FakeFinanceRepository(
      FinanceState(
        profile: null,
        boards: const [board],
        allocations: const [],
        transactions: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseBoardScreen(
          board: board,
          repository: repository,
          initialState: repository.state,
          onStateChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bill'));
    await tester.pumpAndSettle();
    expect(find.text('When is this bill due?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '1');
    await tester.tap(find.text('Make it a bill'));
    await tester.pumpAndSettle();

    final saved = repository.state.boards.single;
    expect(saved.type, BoardType.bill);
    expect(saved.dueDay, 1);
    expect(find.textContaining('each month'), findsOneWidget);

    // And back to Budget, which drops the due day.
    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(repository.state.boards.single.type, BoardType.budget);
    expect(repository.state.boards.single.dueDay, isNull);
  });
}
