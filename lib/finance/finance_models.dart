import 'dart:convert';
import 'dart:math' as math;

class Money {
  const Money._();

  static int? parseMinor(String raw) {
    final value = raw.trim().replaceAll(',', '').replaceAll('₹', '').trim();
    if (!RegExp(r'^\d+(?:\.\d{0,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  static int fromLegacy(num value) => (value * 100).round();

  static String format(int minor, {String currency = 'INR'}) {
    final absolute = minor.abs();
    final major = absolute ~/ 100;
    final fraction = absolute % 100;
    final grouped = _groupIndian(major.toString());
    final symbol = currency == 'INR' ? '₹' : '$currency ';
    return '${minor < 0 ? '−' : ''}$symbol$grouped'
        '${fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}'}';
  }

  static String _groupIndian(String value) {
    if (value.length <= 3) return value;
    final lastThree = value.substring(value.length - 3);
    var prefix = value.substring(0, value.length - 3);
    final groups = <String>[];
    while (prefix.length > 2) {
      groups.insert(0, prefix.substring(prefix.length - 2));
      prefix = prefix.substring(0, prefix.length - 2);
    }
    if (prefix.isNotEmpty) groups.insert(0, prefix);
    return '${groups.join(',')},$lastThree';
  }
}

class FinancialProfile {
  final int monthlyIncomeMinor;
  final int balanceMinor;
  final int unpaidCommitmentsMinor;
  final int plannedSavingsMinor;
  final DateTime balanceAsOf;
  final String currency;

  const FinancialProfile({
    required this.monthlyIncomeMinor,
    required this.balanceMinor,
    required this.unpaidCommitmentsMinor,
    required this.plannedSavingsMinor,
    required this.balanceAsOf,
    this.currency = 'INR',
  });

  // A monthly plan keeps the savings target separate from the cash snapshot.
  int get monthlyBudgetPoolMinor => monthlyIncomeMinor - plannedSavingsMinor;

  Map<String, dynamic> toJson() => {
    'monthlyIncomeMinor': monthlyIncomeMinor,
    'balanceMinor': balanceMinor,
    'unpaidCommitmentsMinor': unpaidCommitmentsMinor,
    'plannedSavingsMinor': plannedSavingsMinor,
    'balanceAsOf': balanceAsOf.toIso8601String(),
    'currency': currency,
  };

  factory FinancialProfile.fromJson(Map<String, dynamic> json) =>
      FinancialProfile(
        monthlyIncomeMinor: _toInt(json['monthlyIncomeMinor']),
        balanceMinor: _toInt(json['balanceMinor']),
        unpaidCommitmentsMinor: _toInt(json['unpaidCommitmentsMinor']),
        plannedSavingsMinor: _toInt(json['plannedSavingsMinor']),
        balanceAsOf:
            DateTime.tryParse('${json['balanceAsOf']}') ?? DateTime.now(),
        currency: json['currency'] as String? ?? 'INR',
      );
}

class ExpenseBoard {
  final String id;
  final String name;
  final String iconKey;
  final String? merchantKey;
  final String? logoUrl;
  final int accentColor;
  final int sortOrder;

  const ExpenseBoard({
    required this.id,
    required this.name,
    required this.iconKey,
    this.merchantKey,
    this.logoUrl,
    this.accentColor = 0xFF147D64,
    this.sortOrder = 0,
  });

  ExpenseBoard copyWith({
    String? name,
    String? iconKey,
    String? merchantKey,
    String? logoUrl,
    int? accentColor,
    int? sortOrder,
  }) => ExpenseBoard(
    id: id,
    name: name ?? this.name,
    iconKey: iconKey ?? this.iconKey,
    merchantKey: merchantKey ?? this.merchantKey,
    logoUrl: logoUrl ?? this.logoUrl,
    accentColor: accentColor ?? this.accentColor,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconKey': iconKey,
    'merchantKey': merchantKey,
    'logoUrl': logoUrl,
    'accentColor': accentColor,
    'sortOrder': sortOrder,
  };

  factory ExpenseBoard.fromJson(Map<String, dynamic> json) => ExpenseBoard(
    id: '${json['id']}',
    name: '${json['name']}',
    iconKey: json['iconKey'] as String? ?? 'category',
    merchantKey: json['merchantKey'] as String?,
    logoUrl: json['logoUrl'] as String?,
    accentColor: _toInt(json['accentColor'], fallback: 0xFF147D64),
    sortOrder: _toInt(json['sortOrder']),
  );
}

class BudgetAllocation {
  final String boardId;
  final String periodStart;
  final int amountMinor;

  const BudgetAllocation({
    required this.boardId,
    required this.periodStart,
    required this.amountMinor,
  });

  Map<String, dynamic> toJson() => {
    'boardId': boardId,
    'periodStart': periodStart,
    'amountMinor': amountMinor,
  };

  factory BudgetAllocation.fromJson(Map<String, dynamic> json) =>
      BudgetAllocation(
        boardId: '${json['boardId']}',
        periodStart: '${json['periodStart']}',
        amountMinor: _toInt(json['amountMinor']),
      );
}

enum TransactionKind { expense, refund, income, transfer }

enum TransactionStatus { posted, pending }

class FinanceTransaction {
  final String id;
  final String boardId;
  final String description;
  final int amountMinor;
  final DateTime occurredAt;
  final TransactionKind kind;
  final TransactionStatus status;
  final String? merchantKey;
  final String iconKey;
  final String? logoUrl;
  final int accentColor;
  final String? source;
  final String? externalId;

  const FinanceTransaction({
    required this.id,
    required this.boardId,
    required this.description,
    required this.amountMinor,
    required this.occurredAt,
    this.kind = TransactionKind.expense,
    this.status = TransactionStatus.posted,
    this.merchantKey,
    this.iconKey = 'category',
    this.logoUrl,
    this.accentColor = 0xFF147D64,
    this.source = 'manual',
    this.externalId,
  });

  /// How this transaction changes spending: expenses add, refunds subtract,
  /// and income and transfers never count as spending.
  int get spendingEffectMinor => switch (kind) {
    TransactionKind.expense => amountMinor,
    TransactionKind.refund => -amountMinor,
    TransactionKind.income || TransactionKind.transfer => 0,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'boardId': boardId,
    'description': description,
    'amountMinor': amountMinor,
    'occurredAt': occurredAt.toIso8601String(),
    'kind': kind.name,
    'status': status.name,
    'merchantKey': merchantKey,
    'iconKey': iconKey,
    'logoUrl': logoUrl,
    'accentColor': accentColor,
    'source': source,
    'externalId': externalId,
  };

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) =>
      FinanceTransaction(
        id: '${json['id']}',
        boardId: '${json['boardId']}',
        description: '${json['description']}',
        amountMinor: _toInt(json['amountMinor']),
        occurredAt:
            DateTime.tryParse('${json['occurredAt']}') ?? DateTime.now(),
        kind: TransactionKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => TransactionKind.expense,
        ),
        status: TransactionStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => TransactionStatus.posted,
        ),
        merchantKey: json['merchantKey'] as String?,
        iconKey: json['iconKey'] as String? ?? 'category',
        logoUrl: json['logoUrl'] as String?,
        accentColor: _toInt(json['accentColor'], fallback: 0xFF147D64),
        source: json['source'] as String? ?? 'manual',
        externalId: json['externalId'] as String?,
      );
}

class FinanceState {
  final FinancialProfile? profile;
  final List<ExpenseBoard> boards;
  final List<BudgetAllocation> allocations;
  final List<FinanceTransaction> transactions;
  final String themeMode;

  const FinanceState({
    required this.profile,
    required this.boards,
    required this.allocations,
    required this.transactions,
    this.themeMode = 'system',
  });

  FinanceState copyWith({
    FinancialProfile? profile,
    bool clearProfile = false,
    List<ExpenseBoard>? boards,
    List<BudgetAllocation>? allocations,
    List<FinanceTransaction>? transactions,
    String? themeMode,
  }) => FinanceState(
    profile: clearProfile ? null : (profile ?? this.profile),
    boards: boards ?? this.boards,
    allocations: allocations ?? this.allocations,
    transactions: transactions ?? this.transactions,
    themeMode: themeMode ?? this.themeMode,
  );

  int allocationFor(String boardId, String period) => allocations
      .where((item) => item.boardId == boardId && item.periodStart == period)
      .fold(0, (sum, item) => sum + item.amountMinor);

  int get transactionsSinceBalanceSnapshotMinor {
    final currentProfile = profile;
    if (currentProfile == null) return 0;
    final snapshotDate = _calendarDate(currentProfile.balanceAsOf);
    return transactions
        .where(
          (item) =>
              item.status == TransactionStatus.posted &&
              _calendarDate(item.occurredAt).isAfter(snapshotDate),
        )
        .fold(0, (sum, item) => sum + item.spendingEffectMinor);
  }

  int? get safeToSpendMinor {
    final currentProfile = profile;
    if (currentProfile == null) return null;
    return currentProfile.balanceMinor - transactionsSinceBalanceSnapshotMinor;
  }

  int spentFor(String boardId, {String? period}) => transactions
      .where((item) {
        if (item.boardId != boardId ||
            item.status != TransactionStatus.posted) {
          return false;
        }
        if (period != null && periodOf(item.occurredAt) != period) return false;
        return true;
      })
      .fold(0, (sum, item) => sum + item.spendingEffectMinor);

  Map<String, dynamic> toJson() => {
    'version': 2,
    'profile': profile?.toJson(),
    'boards': boards.map((item) => item.toJson()).toList(),
    'allocations': allocations.map((item) => item.toJson()).toList(),
    'transactions': transactions.map((item) => item.toJson()).toList(),
    'themeMode': themeMode,
  };

  factory FinanceState.fromJson(Map<String, dynamic> json) => FinanceState(
    profile: json['profile'] is Map
        ? FinancialProfile.fromJson(
            Map<String, dynamic>.from(json['profile'] as Map),
          )
        : null,
    boards: (json['boards'] as List? ?? const [])
        .map(
          (item) =>
              ExpenseBoard.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    allocations: (json['allocations'] as List? ?? const [])
        .map(
          (item) =>
              BudgetAllocation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    transactions: (json['transactions'] as List? ?? const [])
        .map(
          (item) => FinanceTransaction.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(),
    themeMode: json['themeMode'] as String? ?? 'system',
  );

  static FinanceState defaults() => FinanceState(
    profile: null,
    boards: [
      ExpenseBoard(
        id: newId(),
        name: 'Groceries',
        iconKey: 'groceries',
        sortOrder: 0,
      ),
      ExpenseBoard(id: newId(), name: 'Rent', iconKey: 'home', sortOrder: 1),
      ExpenseBoard(
        id: newId(),
        name: 'Electricity',
        iconKey: 'electricity',
        sortOrder: 2,
      ),
      ExpenseBoard(
        id: newId(),
        name: 'Shopping',
        iconKey: 'shopping',
        sortOrder: 3,
      ),
      ExpenseBoard(
        id: newId(),
        name: 'Subscriptions',
        iconKey: 'subscriptions',
        sortOrder: 4,
      ),
    ],
    allocations: const [],
    transactions: const [],
  );
}

DateTime _calendarDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String periodOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-01';

String newId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

int _toInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? fallback;
}

String encodeState(FinanceState state) => jsonEncode(state.toJson());
