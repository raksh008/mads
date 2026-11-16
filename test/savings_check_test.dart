import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/finance_engine.dart';
import 'package:mads/finance/finance_models.dart';
import 'package:mads/finance/finance_screens.dart';

const _confirmText = 'This goes into your savings. Spend from savings?';

void main() {
  // Balance ₹60,000 minus a ₹20,000 savings target leaves ₹40,000.
  final now = DateTime(2026, 11, 14);
  final left = computeSafeToSpend(
    FinanceState(
      profile: FinancialProfile(
        monthlyIncomeMinor: 8000000,
        balanceMinor: 6000000,
        unpaidCommitmentsMinor: 0,
        plannedSavingsMinor: 2000000,
        balanceAsOf: now,
      ),
      boards: const [],
      allocations: const [],
      transactions: const [],
    ),
    now,
  ).aboveSavingsMinor;

  testWidgets('an expense past what is left asks before spending savings', (
    tester,
  ) async {
    expect(left, 4000000);
    Object? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Object>(
                context: context,
                builder: (_) => AddTransactionDialog(
                  boardName: 'Shopping',
                  leftThisMonthMinor: left,
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AddTransactionDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.first, 'Phone');

    // ₹45,000 is more than the ₹40,000 left: confirm first.
    await tester.enterText(fields.last, '45000');
    await tester.tap(find.text('Save transaction'));
    await tester.pumpAndSettle();
    expect(find.text(_confirmText), findsOneWidget);

    // Cancel saves nothing and keeps the form open.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(AlertDialog, _confirmText),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_confirmText), findsNothing);
    expect(find.byType(AddTransactionDialog), findsOneWidget);
    expect(closed, isFalse);

    // ₹5,000 fits in what's left: saved straight away, no question.
    await tester.enterText(fields.last, '5000');
    await tester.tap(find.text('Save transaction'));
    await tester.pumpAndSettle();
    expect(find.text(_confirmText), findsNothing);
    expect(closed, isTrue);
    expect(result, isNotNull);
  });
}
