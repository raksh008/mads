import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/bank_message_parser.dart';
import 'package:mads/finance/bank_messages_screen.dart';
import 'package:mads/finance/finance_models.dart';

const _boards = [
  ExpenseBoard(id: 'food', name: 'Food', iconKey: 'food'),
  ExpenseBoard(id: 'zomato', name: 'Zomato', iconKey: 'food'),
  ExpenseBoard(id: 'salary', name: 'Salary', iconKey: 'work'),
];

const _swiggy =
    'Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 14/11/26 '
    'Ref 612345678901 Not You? Call 18002586161';
const _zomato =
    'Thank you for using HDFC Bank Card XX1234 for Rs. 450.00 at ZOMATO on '
    '14-11-2026 11:32:10.';
const _salary =
    'Your A/C XXXXX1234 Credited INR 80,000.00 on 01/11/26 -Deposit by '
    'transfer from ACME LTD. Avl Bal INR 1,20,000.00-SBI';
const _chai = 'Paid ₹120 to Chai Point via UPI on 14-11-2026';
const _otp = 'Your OTP for login is 482913. Do not share it.';

void main() {
  testWidgets('review, untick, choose boards, skip duplicates, add all', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    List<BankMessageEntry>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<List<BankMessageEntry>>(
                context,
                MaterialPageRoute(
                  builder: (_) => BankMessagesScreen(
                    boards: _boards,
                    existing: [
                      // Zomato was already added earlier: a duplicate.
                      FinanceTransaction(
                        id: 'old',
                        boardId: 'zomato',
                        description: 'ZOMATO',
                        amountMinor: 45000,
                        occurredAt: DateTime(2026, 11, 14, 20),
                      ),
                    ],
                  ),
                ),
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
      find.byType(TextField),
      [_swiggy, _zomato, _salary, _chai, _otp].join('\n\n'),
    );
    await tester.pump();
    await tester.tap(find.text('Read messages'));
    await tester.pumpAndSettle();

    // Five rows: four read, one not.
    expect(find.text('SWIGGY'), findsOneWidget);
    expect(find.text('ACME LTD'), findsOneWidget);
    expect(find.text('Chai Point'), findsOneWidget);
    expect(find.text("Couldn't read this message"), findsOneWidget);
    // The Zomato row is a duplicate: marked and unticked.
    expect(find.text('Already added'), findsOneWidget);
    expect(find.text('Add all (3)'), findsOneWidget);

    // Untick Chai Point.
    final chaiRow = find.ancestor(
      of: find.text('Chai Point'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: chaiRow.first, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add all (2)'), findsOneWidget);

    // Every ticked row needs a board.
    await tester.tap(find.text('Add all (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a board for every ticked row.'), findsOneWidget);
    expect(result, isNull);

    Future<void> choose(String merchant, String board) async {
      final row = find.ancestor(
        of: find.text(merchant),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.text('Choose board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(board).last);
      await tester.pumpAndSettle();
    }

    await choose('SWIGGY', 'Food');
    await choose('ACME LTD', 'Salary');
    await tester.tap(find.text('Add all (2)'));
    await tester.pumpAndSettle();

    final entries = result!;
    expect(entries, hasLength(2));
    final swiggy = entries.firstWhere((e) => e.merchant == 'SWIGGY');
    expect(swiggy.boardId, 'food');
    expect(swiggy.amountMinor, 25000);
    expect(swiggy.isDebit, isTrue);
    expect(swiggy.date, DateTime(2026, 11, 14));
    final salary = entries.firstWhere((e) => e.merchant == 'ACME LTD');
    expect(salary.boardId, 'salary');
    expect(salary.isDebit, isFalse);
    expect(salary.amountMinor, 8000000);

    // Nothing that gets saved carries the message text.
    for (final entry in entries) {
      for (final field in [entry.merchant, entry.duplicateKey]) {
        expect(field, isNot(contains('Ref')));
        expect(field, isNot(contains('A/C')));
        expect(field.length, lessThan(60));
      }
    }
  });

  test('an SMS entry dated before the balance check leaves Balance now', () {
    final state = FinanceState(
      profile: FinancialProfile(
        monthlyIncomeMinor: 8000000,
        balanceMinor: 6000000,
        unpaidCommitmentsMinor: 0,
        plannedSavingsMinor: 0,
        balanceAsOf: DateTime(2026, 11, 14, 10),
      ),
      boards: _boards,
      allocations: const [],
      transactions: [
        // Message dated 13 Nov (no time): before the 14 Nov check.
        FinanceTransaction(
          id: 'sms-before',
          boardId: 'food',
          description: 'SWIGGY',
          amountMinor: 25000,
          occurredAt: DateTime(2026, 11, 13),
          source: 'bank_sms',
          externalId: bankDuplicateKey(25000, 'SWIGGY', DateTime(2026, 11, 13)),
        ),
        // Message from after the check still comes off.
        FinanceTransaction(
          id: 'sms-after',
          boardId: 'food',
          description: 'ZOMATO',
          amountMinor: 45000,
          occurredAt: DateTime(2026, 11, 14, 11, 32),
          source: 'bank_sms',
        ),
      ],
    );
    expect(state.safeToSpendMinor, 6000000 - 45000);
    expect(state.spentFor('food', period: '2026-11-01'), 70000);
  });
}
