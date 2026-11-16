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

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Balance ₹60,000 checked [checkedAgo] ago, then a ₹5,000 expense added a
/// minute after the check.
FinanceState _state(Duration checkedAgo) {
  final checkedAt = DateTime.now().subtract(checkedAgo);
  final base = FinanceState.defaults();
  return base.copyWith(
    profile: FinancialProfile(
      monthlyIncomeMinor: 8_000_000,
      balanceMinor: 6_000_000,
      unpaidCommitmentsMinor: 0,
      plannedSavingsMinor: 1_000_000,
      balanceAsOf: checkedAt,
    ),
    transactions: [
      FinanceTransaction(
        id: 'after-check',
        boardId: base.boards.first.id,
        description: 'After the check',
        amountMinor: 500_000,
        occurredAt: checkedAt.add(const Duration(minutes: 1)),
      ),
    ],
  );
}

Future<void> _pumpHome(WidgetTester tester, FinanceState state) async {
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
  await tester.scrollUntilVisible(
    find.text('Update from bank'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder _rowValue(String label, String value) => find.descendant(
  of: find.widgetWithText(Row, label),
  matching: find.text(value),
);

void main() {
  testWidgets('card shows last check and automatic balance now', (
    tester,
  ) async {
    final state = _state(const Duration(days: 1));
    await _pumpHome(tester, state);

    final checked = state.profile!.balanceAsOf;
    expect(
      find.text('Last checked ₹60,000 · ${checked.day} ${_months[checked.month - 1]}'),
      findsOneWidget,
    );
    // ₹60,000 − the ₹5,000 added after the check.
    expect(_rowValue('Balance now', '₹55,000'), findsOneWidget);
    expect(_rowValue('Savings kept aside', '₹10,000'), findsOneWidget);
    expect(_rowValue('Kept for boards', '₹0'), findsOneWidget);
    // Free money works from balance now: 55,000 − 10,000 savings.
    expect(_rowValue('Free to spend', '₹45,000'), findsOneWidget);
    expect(find.textContaining('Days left'), findsOneWidget);
    expect(find.text('Check your bank balance and update it.'), findsNothing);
  });

  testWidgets('a check older than 7 days asks for an update', (tester) async {
    await _pumpHome(tester, _state(const Duration(days: 8)));
    expect(find.text('Check your bank balance and update it.'), findsOneWidget);
  });

  testWidgets('"Update from bank" opens the profile on the balance field', (
    tester,
  ) async {
    await _pumpHome(tester, _state(const Duration(days: 1)));
    await tester.tap(find.text('Update from bank'));
    await tester.pumpAndSettle();

    expect(find.text('Update your money profile'), findsOneWidget);
    final balanceField = find.descendant(
      of: find.widgetWithText(TextFormField, 'Current account balance'),
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(balanceField);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, '60000');
  });

  testWidgets('no free money shows ₹0 and the planned-for message', (
    tester,
  ) async {
    // Savings of ₹60,000 keeps the whole ₹55,000 balance aside.
    final base = _state(const Duration(days: 1));
    final state = base.copyWith(
      profile: FinancialProfile(
        monthlyIncomeMinor: 8_000_000,
        balanceMinor: 6_000_000,
        unpaidCommitmentsMinor: 0,
        plannedSavingsMinor: 6_000_000,
        balanceAsOf: base.profile!.balanceAsOf,
      ),
    );
    await _pumpHome(tester, state);
    expect(
      find.text(
        'Everything is planned for. Nothing extra to spend freely today.',
      ),
      findsOneWidget,
    );
    expect(_rowValue('Free to spend', '₹0'), findsOneWidget);
    // Nothing negative or "spent more than" on the card itself.
    final card = find
        .ancestor(
          of: find.text('SAFE TO SPEND TODAY'),
          matching: find.byType(Column),
        )
        .first;
    for (final text in ['−₹', 'more than', 'Over by', 'Short by']) {
      expect(
        find.descendant(of: card, matching: find.textContaining(text)),
        findsNothing,
      );
    }
  });
}
