import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruvo/branding.dart';
import 'package:ruvo/finance/finance_assistant.dart';
import 'package:ruvo/finance/finance_models.dart';
import 'package:ruvo/finance/finance_repository.dart';
import 'package:ruvo/finance/finance_screens.dart';
import 'package:ruvo/main.dart' as app;
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

class _FakeMevoraAssistant implements MevoraAssistant {
  MevoraFinanceContext? lastContext;
  List<MevoraConversationMessage>? lastConversation;

  @override
  Future<String> reply({
    required MevoraFinanceContext context,
    required List<MevoraConversationMessage> conversation,
  }) async {
    lastContext = context;
    lastConversation = conversation;
    return 'I can help you make sense of the records you have saved.';
  }
}

User _testUser() => User(
  id: '11111111-1111-4111-8111-111111111111',
  appMetadata: const {},
  userMetadata: const {'full_name': 'Test User'},
  aud: 'authenticated',
  createdAt: DateTime(2026).toIso8601String(),
);

FinanceState _state({String themeMode = 'system'}) =>
    FinanceState.defaults().copyWith(
      profile: FinancialProfile(
        monthlyIncomeMinor: 8_000_000,
        balanceMinor: 300_000,
        unpaidCommitmentsMinor: 2_250_000,
        plannedSavingsMinor: 200_000,
        balanceAsOf: DateTime(2026, 11, 12),
      ),
      themeMode: themeMode,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('finance display audit', () {
    test('monthly plan excludes legacy commitments and reconciles', () {
      final state = _state().copyWith(
        allocations: [
          BudgetAllocation(
            boardId: 'groceries',
            periodStart: '2026-11-01',
            amountMinor: 50_000,
          ),
          BudgetAllocation(
            boardId: 'rent',
            periodStart: '2026-11-01',
            amountMinor: 1_050_000,
          ),
          BudgetAllocation(
            boardId: 'electricity',
            periodStart: '2026-11-01',
            amountMinor: 50_000,
          ),
        ],
      );

      expect(state.profile!.monthlyBudgetPoolMinor, 7_800_000);
      expect(state.safeToSpendMinor, 300_000);
      final allocated = state.allocations
          .where((item) => item.periodStart == '2026-11-01')
          .fold(0, (sum, item) => sum + item.amountMinor);
      expect(allocated, 1_150_000);
      expect(state.profile!.monthlyBudgetPoolMinor - allocated, 6_650_000);
    });

    test('snapshot spending is not counted twice in safe-to-spend', () {
      final base = FinanceState.defaults();
      final groceries = base.boards.first;
      final state = _state().copyWith(
        profile: FinancialProfile(
          monthlyIncomeMinor: 8_000_000,
          balanceMinor: 5_000_000,
          unpaidCommitmentsMinor: 2_250_000,
          plannedSavingsMinor: 1_000_000,
          balanceAsOf: DateTime(2026, 11, 12),
        ),
        transactions: [
          FinanceTransaction(
            id: 'before-snapshot',
            boardId: groceries.id,
            description: 'Already reflected',
            amountMinor: 100_000,
            occurredAt: DateTime(2026, 11, 11),
          ),
          FinanceTransaction(
            id: 'snapshot-day',
            boardId: groceries.id,
            description: 'Included on snapshot date',
            amountMinor: 50_000,
            occurredAt: DateTime(2026, 11, 12, 18),
          ),
          FinanceTransaction(
            id: 'after-snapshot',
            boardId: groceries.id,
            description: 'After snapshot',
            amountMinor: 150_000,
            occurredAt: DateTime(2026, 11, 13),
          ),
          FinanceTransaction(
            id: 'refund-after-snapshot',
            boardId: groceries.id,
            description: 'Refund after snapshot',
            amountMinor: 20_000,
            occurredAt: DateTime(2026, 11, 14),
            kind: TransactionKind.refund,
          ),
          FinanceTransaction(
            id: 'pending-after-snapshot',
            boardId: groceries.id,
            description: 'Pending item',
            amountMinor: 90_000,
            occurredAt: DateTime(2026, 11, 15),
            status: TransactionStatus.pending,
          ),
        ],
      );

      expect(state.transactionsSinceBalanceSnapshotMinor, 130_000);
      expect(state.safeToSpendMinor, 4_870_000);
      expect(state.profile!.monthlyBudgetPoolMinor, 7_000_000);
    });

    test('money parser rejects invalid and negative values', () {
      expect(Money.parseMinor('80000'), 8_000_000);
      expect(Money.parseMinor('-1'), isNull);
      expect(Money.parseMinor('eight thousand'), isNull);
      expect(Money.parseMinor('12.345'), isNull);
    });

    test(
      'AI context contains only computed figures and asks no gap question',
      () {
        final base = _state();
        final subscriptions = base.boards.firstWhere(
          (board) => board.name == 'Subscriptions',
        );
        final state = base.copyWith(
          transactions: [
            FinanceTransaction(
              id: 'subscription',
              boardId: subscriptions.id,
              description: 'Netflix',
              amountMinor: 19_900,
              occurredAt: DateTime(2026, 11, 12),
            ),
          ],
        );
        final context = MevoraFinanceContext.fromState(
          state,
          now: DateTime(2026, 11, 12),
        );
        expect(context.facts['monthlyIncome'], '₹80,000');
        expect(context.facts['balanceSnapshot'], '₹3,000');
        expect(context.facts['postedSpendingThisMonth'], '₹199');
        expect(context.facts['actualSavingsProgress'], contains('not tracked'));
        expect(
          context.facts['calculationNotes'],
          contains('The income-to-balance difference is not spending.'),
        );
        expect(
          context.factsForQuestion(
            'Can I afford to buy for ₹1,000?',
          )['questionSpecificVerifiedCheck'],
          {
            'purchaseAmount': '₹1,000',
            'safeToSpendBeforePurchase': '₹3,000',
            'affordableFromRecordedAvailableAmount': true,
            'remainingAfterPurchase': '₹2,000',
          },
        );
      },
    );

    test(
      'category spending counts posted expenses and subtracts refunds once',
      () {
        final base = FinanceState.defaults();
        final groceries = base.boards.first;
        final state = base.copyWith(
          transactions: [
            FinanceTransaction(
              id: 'one',
              boardId: groceries.id,
              description: 'Groceries',
              amountMinor: 70_000,
              occurredAt: DateTime(2026, 11, 12),
            ),
            FinanceTransaction(
              id: 'two',
              boardId: groceries.id,
              description: 'Returned item',
              amountMinor: 5_000,
              occurredAt: DateTime(2026, 11, 12),
              kind: TransactionKind.refund,
            ),
            FinanceTransaction(
              id: 'three',
              boardId: groceries.id,
              description: 'Pending purchase',
              amountMinor: 10_000,
              occurredAt: DateTime(2026, 11, 12),
              status: TransactionStatus.pending,
            ),
          ],
        );

        expect(state.spentFor(groceries.id, period: '2026-11-01'), 65_000);
      },
    );
  });

  testWidgets('saved theme is applied after the profile gate build', (
    tester,
  ) async {
    ruvoThemeMode.value = ThemeMode.system;
    final repository = _FakeFinanceRepository(_state(themeMode: 'light'));

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: ruvoThemeMode,
        builder: (context, themeMode, child) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          home: FinancialProfileGate(
            user: _testUser(),
            repositoryFactory: (_) => repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(ruvoThemeMode.value, ThemeMode.light);
    expect(find.text('Your expense boards'), findsOneWidget);
    expect(tester.takeException(), isNull);
    ruvoThemeMode.value = ThemeMode.system;
  });

  testWidgets('welcome opens the login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: app.WelcomeScreen()));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome\nback.'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('profile logout action invokes its callback', (tester) async {
    var loggedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          userId: 'test-user',
          userName: 'Test User',
          email: 'test@example.com',
          state: FinanceState.defaults(),
          cloudReady: true,
          onEditFinancialProfile: () async {},
          onThemeChanged: (_) async {},
          onLogout: () async {
            loggedOut = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Log out'));
    expect(loggedOut, isTrue);
  });

  testWidgets('dashboard introduces MEVORA and starts a contextual chat', (
    tester,
  ) async {
    final repository = _FakeFinanceRepository(_state());
    final assistant = _FakeMevoraAssistant();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          initialState: repository.state,
          userName: 'Test User',
          assistant: assistant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MEVORA.'), findsOneWidget);
    expect(find.text('Your finance pal.'), findsOneWidget);
    expect(find.text('Hi, Test!'), findsOneWidget);
    expect(find.text('Your money, organised for the month.'), findsOneWidget);

    await tester.ensureVisible(find.text('Start a conversation'));
    await tester.tap(find.text('Start a conversation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your money profile is ready'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Where is most of my money going?',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      find.text('I can help you make sense of the records you have saved.'),
      findsOneWidget,
    );
    expect(assistant.lastConversation!.last.content, contains('Where is most'));
    expect(assistant.lastContext!.facts['monthlyIncome'], '₹80,000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile edit has three fields and preserves saved commitments', (
    tester,
  ) async {
    final repository = _FakeFinanceRepository(_state());
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          initialState: repository.state,
          userName: 'Test User',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Update your money profile'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Unpaid commitments still due this month'), findsNothing);
    expect(
      find.textContaining("Your current balance is the money available"),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(1), '50000');
    final saveButton = find.text('Save changes');
    await tester.scrollUntilVisible(
      saveButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.state.profile!.monthlyIncomeMinor, 8_000_000);
    expect(repository.state.profile!.balanceMinor, 5_000_000);
    expect(repository.state.profile!.plannedSavingsMinor, 200_000);
    expect(repository.state.profile!.unpaidCommitmentsMinor, 2_250_000);
    expect(repository.state.safeToSpendMinor, 5_000_000);
  });

  testWidgets(
    'onboarding, board details, and transaction entry navigate cleanly',
    (tester) async {
      final repository = _FakeFinanceRepository(FinanceState.defaults());
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: repository,
            initialState: repository.state,
            userName: 'Test User',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      expect(find.text('Your money profile'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '80000');
      final saveProfileButton = find.text('Save money profile');
      await tester.scrollUntilVisible(
        saveProfileButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(saveProfileButton);
      await tester.pumpAndSettle();
      expect(find.text('₹80,000'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Groceries'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Groceries').first);
      await tester.pumpAndSettle();
      expect(find.text('Transactions'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AddTransactionDialog),
              matching: find.byType(TextFormField),
            )
            .first,
        'Weekly groceries',
      );
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AddTransactionDialog),
              matching: find.byType(TextFormField),
            )
            .last,
        '725.50',
      );
      expect(
        tester
            .widgetList<TextFormField>(
              find.descendant(
                of: find.byType(AddTransactionDialog),
                matching: find.byType(TextFormField),
              ),
            )
            .map((field) => field.controller!.text)
            .toList(),
        ['Weekly groceries', '725.50'],
      );
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionDialog), findsNothing);
      expect(repository.state.transactions, hasLength(1));
      await tester.scrollUntilVisible(
        find.text('Weekly groceries'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Weekly groceries'), findsOneWidget);
      expect(find.textContaining('₹725.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
