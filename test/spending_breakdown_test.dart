import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/finance_models.dart';
import 'package:mads/finance/spending_breakdown_screen.dart';

void main() {
  final month = DateTime(2026, 11, 14);

  FinanceTransaction expense(String id, String boardId, int amountMinor) =>
      FinanceTransaction(
        id: id,
        boardId: boardId,
        description: id,
        amountMinor: amountMinor,
        occurredAt: month,
      );

  FinanceState stateWith(List<FinanceTransaction> transactions) =>
      FinanceState(
        profile: null,
        boards: const [
          ExpenseBoard(id: 'food', name: 'Food', iconKey: 'food'),
          ExpenseBoard(id: 'fuel', name: 'Fuel', iconKey: 'fuel'),
          ExpenseBoard(id: 'rent', name: 'Rent', iconKey: 'rent'),
        ],
        allocations: const [],
        transactions: transactions,
      );

  Future<void> pump(WidgetTester tester, FinanceState state) async {
    await tester.pumpWidget(
      MaterialApp(home: SpendingBreakdownScreen(state: state, month: month)),
    );
    await tester.pumpAndSettle(); // let the sweep-in animation finish
  }

  testWidgets('tapping a board row shows its amount in the centre', (
    tester,
  ) async {
    await pump(
      tester,
      stateWith([expense('t1', 'food', 1000000), expense('t2', 'fuel', 3000000)]),
    );
    String center() => tester
        .widget<Text>(find.byKey(const Key('breakdown-center-amount')))
        .data!;

    expect(center(), '₹40,000'); // total spent before any selection
    expect(find.text('₹10,000 · 25%'), findsOneWidget);
    expect(find.text('Rent'), findsNothing); // zero spend is skipped

    await tester.tap(find.widgetWithText(ListTile, 'Food'));
    await tester.pumpAndSettle();
    expect(center(), '₹10,000');
    expect(find.text('25%'), findsOneWidget);

    await pump(tester, stateWith(const []));
    expect(
      find.text(
        'Not enough data yet. Add your income and expenses to see your financial insights.',
      ),
      findsOneWidget,
    );
  });
}
