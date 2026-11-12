import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../branding.dart';
import 'finance_assistant.dart';
import 'finance_assistant_screen.dart';
import 'household_screen.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

class FinancialProfileGate extends StatefulWidget {
  final User user;
  final FinanceRepository Function(String userId)? repositoryFactory;

  const FinancialProfileGate({
    super.key,
    required this.user,
    this.repositoryFactory,
  });

  @override
  State<FinancialProfileGate> createState() => _FinancialProfileGateState();
}

class _FinancialProfileGateState extends State<FinancialProfileGate> {
  late final FinanceRepository repository;
  late Future<FinanceState> stateFuture;

  @override
  void initState() {
    super.initState();
    repository =
        widget.repositoryFactory?.call(widget.user.id) ??
        FinanceRepository(widget.user.id, Supabase.instance.client);
    stateFuture = _loadState();
  }

  Future<FinanceState> _loadState() async {
    final state = await repository.load();
    final nextThemeMode = _themeModeFromString(state.themeMode);
    if (mounted && ruvoThemeMode.value != nextThemeMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ruvoThemeMode.value != nextThemeMode) {
          ruvoThemeMode.value = nextThemeMode;
        }
      });
    }
    return state;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FinanceState>(
    future: stateFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: forestGreen)),
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to open your finance space.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => stateFuture = _loadState()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      final state = snapshot.data!;
      return HomeScreen(
        repository: repository,
        initialState: state,
        userName: widget.user.userMetadata?['full_name'] as String?,
        email: widget.user.email,
      );
    },
  );
}

class OnboardingScreen extends StatefulWidget {
  final FinancialProfile? initialProfile;

  const OnboardingScreen({super.key, this.initialProfile});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController incomeController;
  late final TextEditingController balanceController;
  late final TextEditingController savingsController;
  late DateTime balanceAsOf;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    incomeController = TextEditingController(
      text: _minorInput(profile?.monthlyIncomeMinor ?? 0),
    );
    balanceController = TextEditingController(
      text: _minorInput(profile?.balanceMinor ?? 0),
    );
    savingsController = TextEditingController(
      text: _minorInput(profile?.plannedSavingsMinor ?? 0),
    );
    balanceAsOf = profile?.balanceAsOf ?? DateTime.now();
  }

  @override
  void dispose() {
    incomeController.dispose();
    balanceController.dispose();
    savingsController.dispose();
    super.dispose();
  }

  String _minorInput(int minor) => minor % 100 == 0
      ? '${minor ~/ 100}'
      : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;
    final values = [incomeController, balanceController, savingsController]
        .map((controller) => Money.parseMinor(controller.text.trim()) ?? 0)
        .toList();
    setState(() => saving = true);
    Navigator.pop(
      context,
      FinancialProfile(
        monthlyIncomeMinor: values[0],
        balanceMinor: values[1],
        unpaidCommitmentsMinor:
            widget.initialProfile?.unpaidCommitmentsMinor ?? 0,
        plannedSavingsMinor: values[2],
        balanceAsOf: balanceAsOf,
      ),
    );
  }

  Widget _moneyField(
    String label,
    TextEditingController controller, {
    bool required = false,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        helperText: helper,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return required ? 'Enter your monthly income.' : null;
        }
        if (Money.parseMinor(value) == null) {
          return 'Enter a valid amount with up to two decimal places.';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initialProfile == null
            ? 'Your money profile'
            : 'Update your money profile',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: formKey,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEVORA.',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  'Your finance pal.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              widget.initialProfile == null
                  ? 'Set up your money home.'
                  : 'Your profile, up to date.',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep your income, current balance and savings target clear and separate.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),
            _moneyField('Monthly income', incomeController, required: true),
            _moneyField(
              'Current account balance',
              balanceController,
              helper: "Your current balance is the money available in the account or accounts you've chosen to include, as of the date shown. It already reflects transactions completed before that time.",
            ),
            _dateButton(),
            _moneyField(
              'Monthly savings target',
              savingsController,
              helper: 'How much would you like to save this month? This is a target, not savings already achieved.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(
                widget.initialProfile == null
                    ? 'Save money profile'
                    : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dateButton() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: balanceAsOf,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) setState(() => balanceAsOf = picked);
      },
      icon: const Icon(Icons.event_outlined),
      label: Text('Balance last checked · ${_dateLabel(balanceAsOf)}'),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  final FinanceRepository repository;
  final FinanceState initialState;
  final String? userName;
  final String? email;
  final MevoraAssistant? assistant;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.initialState,
    this.userName,
    this.email,
    this.assistant,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late FinanceState state;

  @override
  void initState() {
    super.initState();
    state = widget.initialState;
    _refreshCatalogIcons();
  }

  Future<void> _save(FinanceState value) async {
    setState(() => state = value);
    await widget.repository.save(value);
    if (mounted) setState(() {});
  }

  Future<void> _refreshCatalogIcons() async {
    var changed = false;
    final boards = <ExpenseBoard>[];
    for (final board in state.boards) {
      final resolved = await widget.repository.resolveCatalogItem(board.name);
      if (board.iconKey != resolved.iconKey ||
          board.merchantKey != resolved.merchantKey ||
          board.logoUrl != resolved.logoUrl) {
        changed = true;
        boards.add(
          board.copyWith(
            iconKey: resolved.iconKey,
            merchantKey: resolved.merchantKey,
            logoUrl: resolved.logoUrl,
            accentColor: resolved.accentColor,
          ),
        );
      } else {
        boards.add(board);
      }
    }
    if (changed && mounted) await _save(state.copyWith(boards: boards));
  }

  Future<void> _editFinancialProfile() async {
    final profile = await Navigator.push<FinancialProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(initialProfile: state.profile),
      ),
    );
    if (profile != null && mounted) {
      await _save(state.copyWith(profile: profile));
    }
  }

  Future<void> _addBoard() async {
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AddExpenseBoardScreen()),
    );
    if (name == null || !mounted) return;
    if (state.boards.any(
      (board) => normalizeName(board.name) == normalizeName(name),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That board already exists.')),
      );
      return;
    }
    final icon = await widget.repository.resolveCatalogItem(name);
    final board = ExpenseBoard(
      id: newId(),
      name: name,
      iconKey: icon.iconKey,
      merchantKey: icon.merchantKey,
      logoUrl: icon.logoUrl,
      accentColor: icon.accentColor,
      sortOrder: state.boards.length,
    );
    await _save(state.copyWith(boards: [...state.boards, board]));
  }

  Future<void> _openBoard(ExpenseBoard board) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseBoardScreen(
          board: board,
          repository: widget.repository,
          initialState: state,
          onStateChanged: (next) {
            if (mounted) setState(() => state = next);
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: widget.repository.userId,
          userName: widget.userName,
          email: widget.email,
          state: state,
          cloudReady: widget.repository.cloudReady,
          onEditFinancialProfile: _editFinancialProfile,
          onThemeChanged: (mode) async {
            ruvoThemeMode.value = _themeModeFromString(mode);
            await _save(state.copyWith(themeMode: mode));
          },
          onLogout: () => Supabase.instance.client.auth.signOut(),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openMevora({String? initialQuestion}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MevoraConversationScreen(
          contextData: MevoraFinanceContext.fromState(state),
          assistant:
              widget.assistant ??
              SupabaseMevoraAssistant(widget.repository.client),
          initialQuestion: initialQuestion,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final period = periodOf(DateTime.now());
    final currency = profile?.currency ?? 'INR';
    final totalAllocated = state.allocations
        .where((allocation) => allocation.periodStart == period)
        .fold(0, (sum, allocation) => sum + allocation.amountMinor);
    final planPool = profile?.monthlyBudgetPoolMinor;
    final unallocated = planPool == null ? null : planPool - totalAllocated;
    final fullName = widget.userName?.trim();
    final firstName = fullName == null || fullName.isEmpty
        ? 'there'
        : fullName.split(RegExp(r'\s+')).first;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MEVORA.',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                            ),
                            Text(
                              'Your finance pal.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Your profile and settings',
                        onPressed: _openProfile,
                        icon: const Icon(Icons.person_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Hi, $firstName!',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Your money, organised for the month.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _incomeCard(profile, currency),
                  const SizedBox(height: 16),
                  _mevoraCard(firstName, profile != null),
                  const SizedBox(height: 23),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your expense boards',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text(
                        _monthLabel(DateTime.now()),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.boards.length + 1,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.13,
                        ),
                    itemBuilder: (context, index) {
                      if (index == state.boards.length) return _addBoardTile();
                      final board = state.boards[index];
                      final budget = state.allocationFor(board.id, period);
                      final spent = state.spentFor(board.id, period: period);
                      return _BoardTile(
                        board: board,
                        budgetMinor: budget,
                        spentMinor: spent,
                        currency: currency,
                        onTap: () => _openBoard(board),
                      );
                    },
                  ),
                  const SizedBox(height: 19),
                  _safeToSpendCard(profile, currency),
                  const SizedBox(height: 14),
                  if (unallocated != null)
                    _allocationSummary(
                      allocated: totalAllocated,
                      pool: planPool!,
                      remaining: unallocated,
                      currency: currency,
                    ),
                  const SizedBox(height: 14),
                  _recentTransactions(currency),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _spendCheck,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Check before you buy'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incomeCard(FinancialProfile? profile, String currency) => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONTHLY INCOME',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                profile == null
                    ? 'Add your income'
                    : Money.format(
                        profile.monthlyIncomeMinor,
                        currency: currency,
                      ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _editFinancialProfile,
          child: Text(profile == null ? 'Set up' : 'Edit'),
        ),
      ],
    ),
  );

  Widget _mevoraCard(String firstName, bool hasProfile) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(21),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.1),
              child: Icon(
                Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                hasProfile ? 'MEVORA is here, $firstName' : 'MEVORA is here',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          hasProfile
              ? "How's your month going? Ask me anything about your money."
              : "Add your money profile when you're ready, or start by asking me a question.",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ActionChip(
              label: const Text('Where is most of my money going?'),
              onPressed: () => _openMevora(
                initialQuestion: 'Where is most of my money going?',
              ),
            ),
            ActionChip(
              label: const Text('Help me plan my month'),
              onPressed: () => _openMevora(
                initialQuestion: 'Can you help me plan my month?',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _openMevora,
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Start a conversation'),
        ),
      ],
    ),
  );

  Widget _safeToSpendCard(FinancialProfile? profile, String currency) {
    final amount = state.safeToSpendMinor;
    final dated = profile == null
        ? ''
        : 'Balance checked ${_dateLabel(profile.balanceAsOf)}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E6B55), Color(0xFF164D57)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SAFE TO SPEND',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            amount == null
                ? 'Set up your money profile'
                : Money.format(amount, currency: currency),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amount == null
                ? 'Add your monthly income, current balance and savings target.'
                : 'Your balance snapshot, adjusted for posted transactions after it. Savings goals and the income-to-balance difference stay separate.',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          if (amount != null) ...[
            const SizedBox(height: 12),
            Text(
              dated,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 10),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 9),
            _equationRow('Current balance', profile!.balanceMinor, currency),
            _equationRow(
              'Transactions after balance check',
              -state.transactionsSinceBalanceSnapshotMinor,
              currency,
            ),
            if (amount < 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Posted spending after the balance check exceeds that snapshot.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _equationRow(String label, int value, String currency) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          Money.format(value, currency: currency),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _allocationSummary({
    required int allocated,
    required int pool,
    required int remaining,
    required String currency,
  }) {
    final over = remaining < 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: over ? const Color(0xFFFFF0ED) : const Color(0xFFEAF5EF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            over ? Icons.warning_amber_rounded : Icons.pie_chart_outline,
            color: over ? coral : forestGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  over ? 'Your plan is over allocated' : 'Monthly plan',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  over
                      ? '${Money.format(allocated, currency: currency)} assigned · ${Money.format(remaining.abs(), currency: currency)} above your planned pool'
                      : '${Money.format(allocated, currency: currency)} assigned · ${Money.format(remaining, currency: currency)} not assigned yet',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentTransactions(String currency) {
    final recent = [...state.transactions]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final items = recent.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent activity',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Your expenses will show here as you add them to a board.',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          ...items.map((transaction) {
            final board = _boardForId(state.boards, transaction.boardId);
            final sign = transaction.kind == TransactionKind.refund ? '+' : '−';
            return Card(
              child: ListTile(
                leading: transaction.merchantKey != null
                    ? BoardIconView(
                        iconKey: transaction.iconKey,
                        accentColor: transaction.accentColor,
                        logoUrl: transaction.logoUrl,
                        size: 22,
                      )
                    : BoardIconView(
                        iconKey: board?.iconKey ?? 'category',
                        accentColor:
                            board?.accentColor ?? forestGreen.toARGB32(),
                        logoUrl: board?.logoUrl,
                        size: 22,
                      ),
                title: Text(transaction.description),
                subtitle: Text(
                  '${board?.name ?? 'Board'} · ${_dateLabel(transaction.occurredAt)}',
                ),
                trailing: Text(
                  '$sign${Money.format(transaction.amountMinor, currency: currency)}',
                  style: TextStyle(
                    color: transaction.kind == TransactionKind.refund
                        ? forestGreen
                        : ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _addBoardTile() => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _addBoard,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
          border: Border.all(
            color: forestGreen.withValues(alpha: 0.25),
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: forestGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add board',
              style: TextStyle(color: forestGreen, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _spendCheck() async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check a purchase'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Purchase amount',
            prefixText: '₹ ',
          ),
          onSubmitted: (_) =>
              Navigator.pop(context, Money.parseMinor(controller.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, Money.parseMinor(controller.text)),
            child: const Text('Check'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    final safe = state.safeToSpendMinor;
    final message = safe == null
        ? 'Add your current balance to check this purchase.'
        : amount <= safe
        ? 'This is within the current available amount. Check the board budget too.'
        : 'This is ${Money.format(amount - safe, currency: state.profile!.currency)} above the current available amount.';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spend check'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  final ExpenseBoard board;
  final int budgetMinor;
  final int spentMinor;
  final String currency;
  final VoidCallback onTap;

  const _BoardTile({
    required this.board,
    required this.budgetMinor,
    required this.spentMinor,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final left = budgetMinor - spentMinor;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BoardIconView(
                iconKey: board.iconKey,
                accentColor: board.accentColor,
                logoUrl: board.logoUrl,
                size: 29,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Money.format(spentMinor, currency: currency)} spent',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  Text(
                    budgetMinor == 0
                        ? 'Budget not set'
                        : '${Money.format(left, currency: currency)} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: left < 0 ? coral : forestGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpenseBoardScreen extends StatefulWidget {
  final ExpenseBoard board;
  final FinanceRepository repository;
  final FinanceState initialState;
  final ValueChanged<FinanceState> onStateChanged;

  const ExpenseBoardScreen({
    super.key,
    required this.board,
    required this.repository,
    required this.initialState,
    required this.onStateChanged,
  });

  @override
  State<ExpenseBoardScreen> createState() => _ExpenseBoardScreenState();
}

class _ExpenseBoardScreenState extends State<ExpenseBoardScreen> {
  late FinanceState state;
  late final TextEditingController budgetController;
  final budgetFormKey = GlobalKey<FormState>();
  bool savingBudget = false;

  String get period => periodOf(DateTime.now());
  int get budget => state.allocationFor(widget.board.id, period);
  int get spent => state.spentFor(widget.board.id, period: period);
  String get currency => state.profile?.currency ?? 'INR';

  @override
  void initState() {
    super.initState();
    state = widget.initialState;
    budgetController = TextEditingController(text: _minorInput(budget));
  }

  @override
  void dispose() {
    budgetController.dispose();
    super.dispose();
  }

  String _minorInput(int minor) => minor == 0
      ? ''
      : minor % 100 == 0
      ? '${minor ~/ 100}'
      : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  Future<void> _persist(FinanceState next) async {
    setState(() => state = next);
    widget.onStateChanged(next);
    await widget.repository.save(next);
    if (mounted) setState(() {});
  }

  Future<void> _saveBudget() async {
    if (savingBudget || !budgetFormKey.currentState!.validate()) return;
    final amount = Money.parseMinor(budgetController.text.trim()) ?? 0;
    final allocations = state.allocations
        .where(
          (item) =>
              !(item.boardId == widget.board.id && item.periodStart == period),
        )
        .toList();
    allocations.add(
      BudgetAllocation(
        boardId: widget.board.id,
        periodStart: period,
        amountMinor: amount,
      ),
    );
    setState(() => savingBudget = true);
    await _persist(state.copyWith(allocations: allocations));
    if (mounted) {
      setState(() => savingBudget = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monthly budget saved.')));
    }
  }

  Future<void> _addTransaction({String? description}) async {
    final entry = await showDialog<_TransactionEntry>(
      context: context,
      builder: (_) => AddTransactionDialog(
        initialDescription: description,
        boardName: widget.board.name,
      ),
    );
    if (entry == null || !mounted) return;
    final merchant = await widget.repository.resolveCatalogItem(
      entry.description,
    );
    final transaction = FinanceTransaction(
      id: newId(),
      boardId: widget.board.id,
      description: entry.description,
      amountMinor: entry.amountMinor,
      occurredAt: DateTime.now(),
      kind: entry.kind,
      merchantKey: merchant.merchantKey,
      iconKey: merchant.iconKey,
      logoUrl: merchant.logoUrl,
      accentColor: merchant.accentColor,
    );
    await _persist(
      state.copyWith(transactions: [transaction, ...state.transactions]),
    );
  }

  Future<void> _importCsv() async {
    final controller = TextEditingController();
    final csv = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import statement rows'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Paste CSV with headers such as Date, Description, Debit, Credit, Reference',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (csv == null || !mounted) return;
    final rows = _parseCsvRows(csv);
    if (rows.length < 2) {
      _showMessage('Paste a CSV header followed by at least one transaction.');
      return;
    }

    final headers = rows.first.map(normalizeName).toList();
    int column(List<String> names) => headers.indexWhere(names.contains);
    final dateColumn = column([
      'date',
      'transaction date',
      'value date',
      'occurred at',
    ]);
    final descriptionColumn = column([
      'description',
      'narration',
      'merchant',
      'remarks',
      'details',
      'particulars',
    ]);
    final debitColumn = column([
      'debit',
      'withdrawal',
      'debit amount',
      'money out',
    ]);
    final creditColumn = column([
      'credit',
      'deposit',
      'credit amount',
      'money in',
    ]);
    final amountColumn = column(['amount', 'transaction amount', 'value']);
    final typeColumn = column([
      'type',
      'transaction type',
      'dr cr',
      'debit credit',
    ]);
    final referenceColumn = column([
      'transaction id',
      'reference',
      'reference number',
      'txn id',
      'utr',
    ]);
    if (descriptionColumn < 0 ||
        (debitColumn < 0 && creditColumn < 0 && amountColumn < 0)) {
      _showMessage(
        'CSV needs a Description or Narration column and an Amount, Debit, or Credit column.',
      );
      return;
    }

    String cell(List<String> row, int index) =>
        index < 0 || index >= row.length ? '' : row[index].trim();
    int parseAmount(String value) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9,.-]'), '');
      return Money.parseMinor(cleaned.replaceFirst(RegExp(r'^[+-]'), '')) ?? 0;
    }

    final existingKeys = state.transactions
        .where((item) => item.source == 'bank_csv' && item.externalId != null)
        .map((item) => item.externalId)
        .toSet();
    final imported = <FinanceTransaction>[];
    var skipped = 0;

    for (final row in rows.skip(1)) {
      final description = cell(row, descriptionColumn);
      if (description.isEmpty) {
        skipped++;
        continue;
      }
      var kind = TransactionKind.expense;
      var amountMinor = 0;
      if (debitColumn >= 0 || creditColumn >= 0) {
        final debit = parseAmount(cell(row, debitColumn));
        final credit = parseAmount(cell(row, creditColumn));
        if (debit > 0) {
          amountMinor = debit;
        } else if (credit > 0) {
          amountMinor = credit;
          kind = TransactionKind.refund;
        }
      } else {
        final rawAmount = cell(row, amountColumn);
        amountMinor = parseAmount(rawAmount);
        final type = normalizeName(cell(row, typeColumn));
        if (type.contains('credit') ||
            type.contains('refund') ||
            rawAmount.trim().startsWith('+')) {
          kind = TransactionKind.refund;
        }
      }
      if (amountMinor <= 0) {
        skipped++;
        continue;
      }

      final occurredAt =
          _parseStatementDate(cell(row, dateColumn)) ?? DateTime.now();
      final suppliedReference = cell(row, referenceColumn);
      final duplicateKey = suppliedReference.isNotEmpty
          ? suppliedReference
          : '${widget.board.id}|${periodOf(occurredAt)}|${normalizeName(description)}|$amountMinor|${kind.name}';
      if (existingKeys.contains(duplicateKey)) {
        skipped++;
        continue;
      }
      existingKeys.add(duplicateKey);
      final merchant = await widget.repository.resolveCatalogItem(description);
      imported.add(
        FinanceTransaction(
          id: newId(),
          boardId: widget.board.id,
          description: description,
          amountMinor: amountMinor,
          occurredAt: occurredAt,
          kind: kind,
          merchantKey: merchant.merchantKey,
          iconKey: merchant.iconKey,
          logoUrl: merchant.logoUrl,
          accentColor: merchant.accentColor,
          source: 'bank_csv',
          externalId: duplicateKey,
        ),
      );
    }

    if (imported.isEmpty) {
      _showMessage('No new transactions imported. $skipped rows were skipped.');
      return;
    }
    await _persist(
      state.copyWith(transactions: [...imported, ...state.transactions]),
    );
    if (mounted) {
      _showMessage(
        'Imported ${imported.length} transactions. $skipped rows were skipped.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<FinanceTransaction> get transactions {
    final items = state.transactions
        .where(
          (item) =>
              item.boardId == widget.board.id &&
              periodOf(item.occurredAt) == period,
        )
        .toList();
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  List<String> get suggestions {
    final name = normalizeName(widget.board.name);
    if (name.contains('subscription') || name.contains('streaming')) {
      return const ['Netflix', 'YouTube', 'ChatGPT', 'Claude'];
    }
    if (name.contains('shopping') || name.contains('fashion')) {
      return const ['Clothes', 'Beauty', 'Shoes', 'Accessories'];
    }
    if (name.contains('grocer') || name.contains('food')) {
      return const [
        'Fruits & vegetables',
        'Household items',
        'Other groceries',
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final month = _monthLabel(DateTime.now());
    final allocationTotal = state.allocations
        .where((item) => item.periodStart == period)
        .fold(0, (sum, item) => sum + item.amountMinor);
    final pool = state.profile?.monthlyBudgetPoolMinor;
    final remainder = budget - spent;
    final progress = budget <= 0
        ? 0.0
        : (spent / budget).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(title: Text(widget.board.name)),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          children: [
            Row(
              children: [
                BoardIconView(
                  iconKey: widget.board.iconKey,
                  accentColor: widget.board.accentColor,
                  logoUrl: widget.board.logoUrl,
                  size: 38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.board.name,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: ink, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Your $month board',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _spendingSummary(progress, remainder),
            const SizedBox(height: 18),
            _budgetEditor(allocationTotal, pool),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transactions',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Import CSV statement',
                  onPressed: _importCsv,
                  icon: const Icon(Icons.upload_file_outlined),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addTransaction(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 11),
              const Text('Quick add', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: suggestions
                    .map(
                      (value) => ActionChip(
                        label: Text(value),
                        onPressed: () => _addTransaction(description: value),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 34,
                      color: Colors.black38,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No transactions this month yet.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              )
            else
              ...transactions.map(_transactionTile),
          ],
        ),
      ),
    );
  }

  Widget _spendingSummary(double progress, int remainder) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SPENT THIS MONTH',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          Money.format(spent, currency: currency),
          style: const TextStyle(
            color: ink,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          budget == 0
              ? 'Set a monthly budget to see what remains.'
              : 'of ${Money.format(budget, currency: currency)} planned',
          style: const TextStyle(color: Colors.black54),
        ),
        if (budget > 0) ...[
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              color: remainder < 0 ? coral : forestGreen,
              backgroundColor: forestGreen.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remainder >= 0
                ? '${Money.format(remainder, currency: currency)} left in this board.'
                : 'Over this board’s plan by ${Money.format(remainder.abs(), currency: currency)}.',
            style: TextStyle(
              color: remainder < 0 ? coral : forestGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _budgetEditor(int allocationTotal, int? pool) => Form(
    key: budgetFormKey,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$month plan',
            style: const TextStyle(
              color: ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Set the amount you want for ${widget.board.name}. This is a plan; actual purchases are recorded below.',
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 13),
          TextFormField(
            controller: budgetController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly amount',
              prefixText: '₹ ',
              hintText: 'Enter any amount',
            ),
            validator: (value) =>
                value == null ||
                    value.trim().isEmpty ||
                    Money.parseMinor(value) == null
                ? 'Enter a valid amount.'
                : null,
          ),
          if (_wouldOverallocate(allocationTotal, pool)) ...[
            const SizedBox(height: 9),
            Text(
              'With this amount, all boards will have ${Money.format(_proposedTotal(allocationTotal), currency: currency)} planned against a ${Money.format(pool!, currency: currency)} pool. You can still save it; review the total plan on your home screen.',
              style: const TextStyle(
                color: Color(0xFF9C4A37),
                height: 1.35,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: savingBudget ? null : _saveBudget,
              child: Text(savingBudget ? 'Saving…' : 'Save monthly budget'),
            ),
          ),
        ],
      ),
    ),
  );

  String get month => _monthLabel(DateTime.now());

  Widget _transactionTile(FinanceTransaction transaction) {
    final sign = transaction.kind == TransactionKind.refund ? '+' : '−';
    final color = transaction.kind == TransactionKind.refund
        ? forestGreen
        : ink;
    return Card(
      child: ListTile(
        leading: transaction.merchantKey != null
            ? BoardIconView(
                iconKey: transaction.iconKey,
                accentColor: transaction.accentColor,
                logoUrl: transaction.logoUrl,
                size: 23,
              )
            : CircleAvatar(
                backgroundColor: forestGreen.withValues(alpha: 0.1),
                child: Icon(
                  transaction.kind == TransactionKind.refund
                      ? Icons.undo_rounded
                      : Icons.receipt_long_outlined,
                  color: forestGreen,
                ),
              ),
        title: Text(transaction.description),
        subtitle: Text(
          '${_dateLabel(transaction.occurredAt)} · ${transaction.status.name}',
        ),
        trailing: Text(
          '$sign${Money.format(transaction.amountMinor, currency: currency)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  int _proposedTotal(int currentTotal) {
    final draft = Money.parseMinor(budgetController.text.trim());
    return draft == null ? currentTotal : currentTotal - budget + draft;
  }

  bool _wouldOverallocate(int currentTotal, int? pool) =>
      pool != null && _proposedTotal(currentTotal) > pool;
}

class _TransactionEntry {
  final String description;
  final int amountMinor;
  final TransactionKind kind;
  const _TransactionEntry(this.description, this.amountMinor, this.kind);
}

class AddTransactionDialog extends StatefulWidget {
  final String? initialDescription;
  final String boardName;
  const AddTransactionDialog({
    super.key,
    this.initialDescription,
    required this.boardName,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController descriptionController;
  final amountController = TextEditingController();
  TransactionKind kind = TransactionKind.expense;

  @override
  void initState() {
    super.initState();
    descriptionController = TextEditingController(
      text: widget.initialDescription ?? '',
    );
  }

  @override
  void dispose() {
    descriptionController.dispose();
    amountController.dispose();
    super.dispose();
  }

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _TransactionEntry(
        descriptionController.text.trim(),
        Money.parseMinor(amountController.text.trim())!,
        kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(kind == TransactionKind.refund ? 'Add refund' : 'Add expense'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<TransactionKind>(
            segments: const [
              ButtonSegment(
                value: TransactionKind.expense,
                label: Text('Expense'),
                icon: Icon(Icons.arrow_upward),
              ),
              ButtonSegment(
                value: TransactionKind.refund,
                label: Text('Refund'),
                icon: Icon(Icons.undo),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (value) => setState(() => kind = value.first),
          ),
          TextFormField(
            controller: descriptionController,
            autofocus: widget.initialDescription == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'What was it for?',
              hintText: widget.boardName,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a description.'
                : null,
          ),
          TextFormField(
            controller: amountController,
            autofocus: widget.initialDescription != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
            ),
            validator: (value) {
              final amount = value == null ? null : Money.parseMinor(value);
              return amount == null || amount <= 0
                  ? 'Enter an amount above ₹0.'
                  : null;
            },
            onFieldSubmitted: (_) => save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Save transaction')),
    ],
  );
}

class AddExpenseBoardScreen extends StatefulWidget {
  const AddExpenseBoardScreen({super.key});

  @override
  State<AddExpenseBoardScreen> createState() => _AddExpenseBoardScreenState();
}

class _AddExpenseBoardScreenState extends State<AddExpenseBoardScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void add() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add board')),
    body: SafeArea(
      child: Form(
        key: formKey,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.dashboard_customize_outlined,
              size: 45,
              color: forestGreen,
            ),
            const SizedBox(height: 15),
            Text(
              'Create an expense board',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Give it a name. RUVO matches it to a category and icon automatically.',
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: nameController,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Board name',
                hintText: 'e.g. Groceries, Travel, Pet care',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a name for your board.'
                  : null,
              onFieldSubmitted: (_) => add(),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('Add board'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  final String userId;
  final String? userName;
  final String? email;
  final FinanceState state;
  final bool cloudReady;
  final Future<void> Function() onEditFinancialProfile;
  final Future<void> Function(String) onThemeChanged;
  final Future<void> Function() onLogout;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.email,
    required this.state,
    required this.cloudReady,
    required this.onEditFinancialProfile,
    required this.onThemeChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final name = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : 'RUVO member';
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(22),
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: forestGreen.withValues(alpha: 0.1),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: forestGreen,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
          if (email != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                email!,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ],
          const SizedBox(height: 25),
          const Text(
            'MONEY PROFILE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: forestGreen,
              ),
              title: const Text('Financial details'),
              subtitle: const Text(
                'Income, current balance and savings target',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onEditFinancialProfile,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'APPEARANCE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                initialValue: state.themeMode,
                decoration: const InputDecoration(
                  labelText: 'Theme',
                  border: InputBorder.none,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text('Use device setting'),
                  ),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value != null) onThemeChanged(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'DATA',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                cloudReady ? Icons.cloud_done_outlined : Icons.phone_android,
                color: cloudReady ? forestGreen : Colors.orange.shade800,
              ),
              title: Text(
                cloudReady ? 'Synced to your account' : 'Saved on this device',
              ),
              subtitle: Text(
                cloudReady
                    ? 'Your finance data syncs through your private account.'
                    : 'Cloud sync will start when the database migration is applied and a connection is available.',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.home_work_outlined, color: forestGreen),
              title: const Text('Household'),
              subtitle: const Text(
                'Invite people and track expenses you choose to share',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdScreen(userId: userId),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'RUVO uses your current balance as a snapshot. Purchases are tracked separately and are not subtracted from it again.',
              style: TextStyle(
                color: Colors.black54,
                height: 1.45,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: coral),
              title: const Text('Log out'),
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class BoardIconView extends StatelessWidget {
  final String iconKey;
  final int accentColor;
  final String? logoUrl;
  final double size;

  const BoardIconView({
    super.key,
    required this.iconKey,
    this.accentColor = 0xFF147D64,
    this.logoUrl,
    this.size = 28,
  });

  IconData get _icon => switch (iconKey) {
    'groceries' => Icons.shopping_basket_outlined,
    'home' || 'electricity' => Icons.home_rounded,
    'shopping' => Icons.shopping_bag_outlined,
    'beauty' => Icons.face_retouching_natural,
    'subscriptions' => Icons.subscriptions_outlined,
    'travel' => Icons.flight_outlined,
    'health' => Icons.favorite_border,
    'pets' => Icons.pets,
    'dining' => Icons.restaurant_outlined,
    'transport' => Icons.directions_car_outlined,
    'education' => Icons.school_outlined,
    'internet' => Icons.wifi_outlined,
    'entertainment' => Icons.movie_outlined,
    'insurance' => Icons.verified_user_outlined,
    'netflix' => Icons.movie_outlined,
    'youtube' => Icons.play_arrow_rounded,
    'chatgpt' || 'claude' => Icons.auto_awesome,
    _ => Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final color = Color(accentColor);
    final brandMark = switch (iconKey) {
      'netflix' => Container(
        width: size + 5,
        height: size + 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          'N',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.82,
          ),
        ),
      ),
      'youtube' => Container(
        width: size + 7,
        height: size * 0.76,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 19,
        ),
      ),
      'chatgpt' => Container(
        width: size + 5,
        height: size + 5,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        alignment: Alignment.center,
        child: Text(
          '✳',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.9,
          ),
        ),
      ),
      'claude' => Container(
        width: size + 5,
        height: size + 5,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '✦',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.95,
          ),
        ),
      ),
      'electricity' => _electricityIcon(color),
      _ => null,
    };
    final fallback = brandMark ?? Icon(_icon, color: color, size: size);
    final mark = logoUrl == null || logoUrl!.isEmpty
        ? fallback
        : Image.network(
            logoUrl!,
            width: size + 7,
            height: size + 7,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => fallback,
          );
    if (iconKey != 'groceries') return mark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: mark,
    );
  }

  Widget _electricityIcon(Color color) => SizedBox(
    width: size + 8,
    height: size + 5,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.home_rounded, color: color, size: size),
        Positioned(
          top: size * 0.53,
          left: size * 0.34,
          child: _lightWindow(size),
        ),
        Positioned(
          top: size * 0.53,
          left: size * 0.61,
          child: _lightWindow(size),
        ),
      ],
    ),
  );

  Widget _lightWindow(double iconSize) => Container(
    width: iconSize * 0.14,
    height: iconSize * 0.14,
    decoration: BoxDecoration(
      color: Colors.amber.shade300,
      borderRadius: BorderRadius.circular(2),
      boxShadow: [
        BoxShadow(color: Colors.amber.withValues(alpha: 0.8), blurRadius: 7),
      ],
    ),
  );
}

ThemeMode _themeModeFromString(String value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

ExpenseBoard? _boardForId(List<ExpenseBoard> boards, String id) {
  for (final board in boards) {
    if (board.id == id) return board;
  }
  return null;
}

List<List<String>> _parseCsvRows(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (char == '"') {
      if (quoted && index + 1 < input.length && input[index + 1] == '"') {
        cell.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      row.add(cell.toString());
      cell.clear();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      if (char == '\r' &&
          index + 1 < input.length &&
          input[index + 1] == '\n') {
        index++;
      }
      row.add(cell.toString());
      cell.clear();
      if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(char);
    }
  }
  row.add(cell.toString());
  if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
  return rows;
}

DateTime? _parseStatementDate(String value) {
  final direct = DateTime.tryParse(value);
  if (direct != null) return direct;
  final match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$')
      .firstMatch(value.trim());
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  var year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  if (year < 100) year += year < 70 ? 2000 : 1900;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

String _monthLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _dateLabel(DateTime date) =>
    '${date.day} ${_monthLabel(date).split(' ').first} ${date.year}';
