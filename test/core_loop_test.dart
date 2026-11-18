import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/finance_models.dart';
import 'package:mads/finance/finance_repository.dart';
import 'package:mads/finance/finance_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tests for the MVP core loop: enter the monthly amount, log spending, see
/// today's spending limit.
class _FakeRepository implements FinanceRepository {
  _FakeRepository(this.state, {this.failSave = false});

  FinanceState state;
  final bool failSave;

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
    if (failSave) throw Exception('disk full');
    state = value;
  }

  @override
  Future<CatalogResolution> resolveCatalogItem(String name) async =>
      CatalogResolution.fallback(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FinanceState _stateWith({int balance = 5_000_000, int savings = 0}) {
  final base = FinanceState.defaults();
  return base.copyWith(
    profile: FinancialProfile(
      monthlyIncomeMinor: 8_000_000,
      balanceMinor: balance,
      unpaidCommitmentsMinor: 0,
      plannedSavingsMinor: savings,
      balanceAsOf: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  );
}

Future<_FakeRepository> _pumpHome(
  WidgetTester tester,
  FinanceState state, {
  bool failSave = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repository = _FakeRepository(state, failSave: failSave);
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
  return repository;
}

void main() {
  group('monthly amount (onboarding)', () {
    Future<void> openOnboarding(
      WidgetTester tester,
      List<FinancialProfile?> saved,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  saved.add(await Navigator.push<FinancialProfile>(
                    context,
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  )),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a first-time profile starts with empty fields', (tester) async {
      await openOnboarding(tester, []);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((field) => field.controller!.text)
          .toList();
      expect(fields, ['', '', '']);
    });

    testWidgets('blank income shows an error and does not save', (tester) async {
      final saved = <FinancialProfile?>[];
      await openOnboarding(tester, saved);
      await tester.ensureVisible(find.text('Save money profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save money profile'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your monthly income.'), findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('income of 0 is rejected with a clear message', (tester) async {
      final saved = <FinancialProfile?>[];
      await openOnboarding(tester, saved);
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.ensureVisible(find.text('Save money profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save money profile'));
      await tester.pumpAndSettle();
      expect(find.text('Monthly income must be more than ₹0.'), findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('text that is not a number is rejected', (tester) async {
      final saved = <FinancialProfile?>[];
      await openOnboarding(tester, saved);
      await tester.enterText(find.byType(TextFormField).first, 'abc');
      await tester.ensureVisible(find.text('Save money profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save money profile'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter a number like 25000'),
        findsOneWidget,
      );
      expect(saved, isEmpty);
    });

    testWidgets('valid income and balance save in paise', (tester) async {
      final saved = <FinancialProfile?>[];
      await openOnboarding(tester, saved);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '80,000');
      await tester.enterText(fields.at(1), '50000.50');
      await tester.ensureVisible(find.text('Save money profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save money profile'));
      await tester.pumpAndSettle();
      expect(saved.single!.monthlyIncomeMinor, 8_000_000);
      expect(saved.single!.balanceMinor, 5_000_050);
    });
  });

  group("today's limit card", () {
    testWidgets('shows the limit with a Log spending button', (tester) async {
      await _pumpHome(tester, _stateWith());
      expect(find.text('SAFE TO SPEND TODAY'), findsOneWidget);
      expect(find.text('Log spending'), findsOneWidget);
      expect(find.textContaining('Tap here'), findsNothing);
    });

    testWidgets('no profile: tapping the card opens setup', (tester) async {
      await _pumpHome(tester, FinanceState.defaults());
      expect(find.text('Set up your money profile'), findsOneWidget);
      await tester.tap(find.text('Set up your money profile'));
      await tester.pumpAndSettle();
      expect(find.text('Your money profile'), findsOneWidget);
    });

    testWidgets('a blank balance says so instead of blaming savings', (
      tester,
    ) async {
      await _pumpHome(tester, _stateWith(balance: 0));
      expect(find.textContaining('current balance is ₹0'), findsOneWidget);
      await tester.tap(find.textContaining('current balance is ₹0'));
      await tester.pumpAndSettle();
      // Opens the profile with the balance field focused.
      expect(find.text('Update your money profile'), findsOneWidget);
    });
  });

  group('log spending', () {
    testWidgets('Home flow saves the expense and reports the new limit', (
      tester,
    ) async {
      final repository = await _pumpHome(tester, _stateWith());
      await tester.tap(find.text('Log spending'));
      await tester.pumpAndSettle();
      expect(find.text('What did you spend on?'), findsOneWidget);
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      // Description is optional; only the amount is needed.
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AddTransactionDialog),
              matching: find.byType(TextFormField),
            )
            .last,
        '250',
      );
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionDialog), findsNothing);
      final saved = repository.state.transactions.single;
      expect(saved.amountMinor, 25_000);
      expect(saved.description, 'Groceries');
      expect(saved.boardId, repository.state.boards.first.id);
      expect(find.textContaining('Expense of ₹250 saved to Groceries'),
          findsOneWidget);
      expect(find.textContaining('Safe to spend today:'), findsOneWidget);
    });

    testWidgets('invalid amount shows an error and keeps the dialog open', (
      tester,
    ) async {
      final repository = await _pumpHome(tester, _stateWith());
      await tester.tap(find.text('Log spending'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number, like 250 or 250.50.'), findsOneWidget);
      expect(find.byType(AddTransactionDialog), findsOneWidget);
      expect(repository.state.transactions, isEmpty);
    });

    testWidgets('cancelling the board picker saves nothing', (tester) async {
      final repository = await _pumpHome(tester, _stateWith());
      await tester.tap(find.text('Log spending'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionDialog), findsNothing);
      expect(repository.state.transactions, isEmpty);
    });

    testWidgets('a failed save tells the user instead of failing silently', (
      tester,
    ) async {
      await _pumpHome(tester, _stateWith(), failSave: true);
      await tester.tap(find.text('Log spending'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AddTransactionDialog),
              matching: find.byType(TextFormField),
            )
            .last,
        '100',
      );
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save your changes"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('double-tapping Save does not pop the screen underneath', (
      tester,
    ) async {
      final repository = await _pumpHome(tester, _stateWith());
      await tester.tap(find.text('Boards'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add expense'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AddTransactionDialog),
              matching: find.byType(TextFormField),
            )
            .last,
        '40',
      );
      final save = find.text('Save transaction');
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      // Still on the board screen, with exactly one expense.
      expect(find.byType(ExpenseBoardScreen), findsOneWidget);
      expect(repository.state.transactions, hasLength(1));
    });
  });

  test('cloud timestamps are read in local time', () {
    final row = transactionToCloudRow(
      FinanceTransaction(
        id: 'a',
        boardId: 'b',
        description: 'Tea',
        amountMinor: 1000,
        occurredAt: DateTime.utc(2026, 11, 30, 19, 0),
      ),
      userId: 'u',
      currency: 'INR',
    );
    final read = transactionFromCloudRow(row);
    expect(read.occurredAt.isUtc, isFalse);
    expect(read.occurredAt.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 19)),
        isTrue);
  });
}
