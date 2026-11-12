import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'finance_models.dart';

class FinanceRepository {
  FinanceRepository(this.userId, this.client);

  final String userId;
  final SupabaseClient client;
  bool cloudReady = false;

  String get _localKey => 'ruvo_${userId}_finance_v2';
  String _legacyKey(String field) => 'ruvo_${userId}_$field';

  Future<FinanceState> load() async {
    final local = await _readLocal();
    try {
      final remote = await _readCloud();
      if (remote != null) {
        cloudReady = true;
        await _writeLocal(remote);
        return remote;
      }
      final initial = local ?? FinanceState.defaults();
      await _syncCloud(initial);
      cloudReady = true;
      await _writeLocal(initial);
      return initial;
    } catch (_) {
      cloudReady = false;
      final fallback = local ?? FinanceState.defaults();
      await _writeLocal(fallback);
      return fallback;
    }
  }

  Future<void> save(FinanceState state) async {
    await _writeLocal(state);
    try {
      await _syncCloud(state);
      cloudReady = true;
    } catch (_) {
      // Keep the user's edits on device when the migration is not applied,
      // the network is unavailable, or the account is offline.
      cloudReady = false;
    }
  }

  Future<CatalogResolution> resolveCatalogItem(String name) async {
    if (!cloudReady) return CatalogResolution.fallback(name);
    try {
      final result = await client.rpc(
        'resolve_catalog_item',
        params: {'p_name': name},
      );
      if (result is Map) {
        return CatalogResolution.fromJson(Map<String, dynamic>.from(result));
      }
    } catch (_) {
      // The local mapping keeps board creation available until the SQL
      // migration and network are ready.
    }
    return CatalogResolution.fallback(name);
  }

  Future<FinanceState?> _readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localKey);
    if (stored != null) {
      try {
        return FinanceState.fromJson(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        );
      } catch (_) {
        // A broken cache must not prevent recovery from cloud data.
      }
    }
    return _migrateLegacy(prefs);
  }

  Future<FinanceState?> _migrateLegacy(SharedPreferences prefs) async {
    final wasCompleted = prefs.getBool(_legacyKey('completed')) ?? false;
    final savedCategories = prefs.getStringList(_legacyKey('home_categories'));
    if (!wasCompleted && (savedCategories == null || savedCategories.isEmpty)) {
      return null;
    }

    int legacyAmount(String field) =>
        Money.fromLegacy(prefs.getDouble(_legacyKey(field)) ?? 0);

    final now = DateTime.now();
    final profile = wasCompleted
        ? FinancialProfile(
            monthlyIncomeMinor: legacyAmount('income'),
            balanceMinor: legacyAmount('balance'),
            unpaidCommitmentsMinor:
                legacyAmount('expenses') + legacyAmount('bills'),
            plannedSavingsMinor: legacyAmount('savings'),
            balanceAsOf: now,
          )
        : null;
    final names =
        savedCategories ??
        const ['Groceries', 'Rent', 'Electricity', 'Shopping', 'Subscriptions'];
    final boards = <ExpenseBoard>[];
    final allocations = <BudgetAllocation>[];
    final transactions = <FinanceTransaction>[];
    final period = periodOf(now);

    for (var index = 0; index < names.length; index++) {
      final name = names[index].trim();
      if (name.isEmpty) continue;
      final boardId = newId();
      final resolved = CatalogResolution.fallback(name);
      final board = ExpenseBoard(
        id: boardId,
        name: name,
        iconKey: resolved.iconKey,
        merchantKey: resolved.merchantKey,
        accentColor: resolved.accentColor,
        sortOrder: index,
      );
      boards.add(board);

      final encodedName = Uri.encodeComponent(name);
      final legacyBudget = prefs.getDouble(
        _legacyKey(
          'board_budget_${encodedName}_${period.substring(0, 4)}_${period.substring(5, 7)}',
        ),
      );
      if (legacyBudget != null && legacyBudget > 0) {
        allocations.add(
          BudgetAllocation(
            boardId: boardId,
            periodStart: period,
            amountMinor: Money.fromLegacy(legacyBudget),
          ),
        );
      }

      final oldExpenses = prefs.getString(
        _legacyKey(
          'board_expenses_${encodedName}_${period.substring(0, 4)}_${period.substring(5, 7)}',
        ),
      );
      if (oldExpenses == null) continue;
      try {
        final rows = jsonDecode(oldExpenses) as List<dynamic>;
        for (final row in rows) {
          final entry = Map<String, dynamic>.from(row as Map);
          final createdAt = DateTime.tryParse('${entry['createdAt']}') ?? now;
          transactions.add(
            FinanceTransaction(
              id: newId(),
              boardId: boardId,
              description: '${entry['description'] ?? name}',
              amountMinor: Money.fromLegacy((entry['amount'] as num?) ?? 0),
              occurredAt: createdAt,
            ),
          );
        }
      } catch (_) {
        // Skip malformed legacy rows while preserving the rest of the user's data.
      }
    }

    return FinanceState(
      profile: profile,
      boards: boards.isEmpty ? FinanceState.defaults().boards : boards,
      allocations: allocations,
      transactions: transactions,
    );
  }

  Future<void> _writeLocal(FinanceState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, encodeState(state));
    await prefs.setString('ruvo_${userId}_theme_mode', state.themeMode);
  }

  Future<FinanceState?> _readCloud() async {
    final profiles = await client
        .from('profiles')
        .select('theme_mode')
        .eq('id', userId)
        .limit(1);
    final themeMode = profiles.isEmpty
        ? 'system'
        : profiles.first['theme_mode'] as String? ?? 'system';

    final profileRows = await client
        .from('financial_profiles')
        .select()
        .eq('user_id', userId)
        .limit(1);
    final boardRows = await client
        .from('expense_boards')
        .select()
        .eq('user_id', userId)
        .order('sort_order');
    final allocationRows = await client
        .from('budget_allocations')
        .select()
        .eq('user_id', userId);
    final transactionRows = await client
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('occurred_at', ascending: false);

    if (profileRows.isEmpty &&
        boardRows.isEmpty &&
        allocationRows.isEmpty &&
        transactionRows.isEmpty) {
      return null;
    }
    final financialProfile = profileRows.isEmpty
        ? null
        : _profileFromCloud(Map<String, dynamic>.from(profileRows.first));
    return FinanceState(
      profile: financialProfile,
      boards: boardRows.map(_boardFromCloud).toList(),
      allocations: allocationRows.map(_allocationFromCloud).toList(),
      transactions: transactionRows.map(_transactionFromCloud).toList(),
      themeMode: themeMode,
    );
  }

  Future<void> _syncCloud(FinanceState state) async {
    await client.from('profiles').upsert({
      'id': userId,
      'display_name': client.auth.currentUser?.userMetadata?['full_name'],
      'theme_mode': state.themeMode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');

    final profile = state.profile;
    if (profile != null) {
      await client.from('financial_profiles').upsert({
        'user_id': userId,
        'monthly_income_minor': profile.monthlyIncomeMinor,
        'balance_minor': profile.balanceMinor,
        'unpaid_commitments_minor': profile.unpaidCommitmentsMinor,
        'planned_savings_minor': profile.plannedSavingsMinor,
        'balance_as_of': profile.balanceAsOf.toIso8601String().substring(0, 10),
        'currency': profile.currency,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    }

    if (state.boards.isNotEmpty) {
      await client
          .from('expense_boards')
          .upsert(
            state.boards
                .map(
                  (board) => {
                    'id': board.id,
                    'user_id': userId,
                    'name': board.name,
                    'normalized_name': normalizeName(board.name),
                    'icon_key': board.iconKey,
                    'merchant_key': board.merchantKey,
                    'logo_url': board.logoUrl,
                    'accent_color':
                        '#${board.accentColor.toRadixString(16).padLeft(8, '0').substring(2)}',
                    'sort_order': board.sortOrder,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                )
                .toList(),
            onConflict: 'id',
          );
    }

    if (state.allocations.isNotEmpty) {
      await client
          .from('budget_allocations')
          .upsert(
            state.allocations
                .map(
                  (allocation) => {
                    'user_id': userId,
                    'board_id': allocation.boardId,
                    'period_start': allocation.periodStart,
                    'amount_minor': allocation.amountMinor,
                    'currency': state.profile?.currency ?? 'INR',
                  },
                )
                .toList(),
            onConflict: 'board_id,period_start',
          );
    }

    if (state.transactions.isNotEmpty) {
      await client
          .from('transactions')
          .upsert(
            state.transactions
                .map(
                  (transaction) => {
                    'id': transaction.id,
                    'user_id': userId,
                    'board_id': transaction.boardId,
                    'description': transaction.description,
                    'amount_minor': transaction.amountMinor,
                    'currency': state.profile?.currency ?? 'INR',
                    'transaction_kind': transaction.kind.name,
                    'status': transaction.status.name,
                    'merchant_key': transaction.merchantKey,
                    'icon_key': transaction.iconKey,
                    'logo_url': transaction.logoUrl,
                    'accent_color':
                        '#${transaction.accentColor.toRadixString(16).padLeft(8, '0').substring(2)}',
                    'source': transaction.source,
                    'external_id': transaction.externalId,
                    'occurred_at': transaction.occurredAt
                        .toUtc()
                        .toIso8601String(),
                  },
                )
                .toList(),
            onConflict: 'id',
          );
    }
  }

  FinancialProfile _profileFromCloud(Map<String, dynamic> row) =>
      FinancialProfile(
        monthlyIncomeMinor: _asInt(row['monthly_income_minor']),
        balanceMinor: _asInt(row['balance_minor']),
        unpaidCommitmentsMinor: _asInt(row['unpaid_commitments_minor']),
        plannedSavingsMinor: _asInt(row['planned_savings_minor']),
        balanceAsOf:
            DateTime.tryParse('${row['balance_as_of']}') ?? DateTime.now(),
        currency: row['currency'] as String? ?? 'INR',
      );

  ExpenseBoard _boardFromCloud(dynamic value) {
    final row = Map<String, dynamic>.from(value as Map);
    return ExpenseBoard(
      id: '${row['id']}',
      name: '${row['name']}',
      iconKey: row['icon_key'] as String? ?? 'category',
      merchantKey: row['merchant_key'] as String?,
      logoUrl: row['logo_url'] as String?,
      accentColor: _colorFromHex(row['accent_color'] as String?),
      sortOrder: _asInt(row['sort_order']),
    );
  }

  BudgetAllocation _allocationFromCloud(dynamic value) {
    final row = Map<String, dynamic>.from(value as Map);
    return BudgetAllocation(
      boardId: '${row['board_id']}',
      periodStart: '${row['period_start']}',
      amountMinor: _asInt(row['amount_minor']),
    );
  }

  FinanceTransaction _transactionFromCloud(dynamic value) {
    final row = Map<String, dynamic>.from(value as Map);
    return FinanceTransaction(
      id: '${row['id']}',
      boardId: '${row['board_id']}',
      description: '${row['description']}',
      amountMinor: _asInt(row['amount_minor']),
      occurredAt: DateTime.tryParse('${row['occurred_at']}') ?? DateTime.now(),
      kind: row['transaction_kind'] == 'refund'
          ? TransactionKind.refund
          : TransactionKind.expense,
      status: row['status'] == 'pending'
          ? TransactionStatus.pending
          : TransactionStatus.posted,
      merchantKey: row['merchant_key'] as String?,
      iconKey: row['icon_key'] as String? ?? 'category',
      logoUrl: row['logo_url'] as String?,
      accentColor: _colorFromHex(row['accent_color'] as String?),
      source: row['source'] as String? ?? 'manual',
      externalId: row['external_id'] as String?,
    );
  }
}

class CatalogResolution {
  final String iconKey;
  final String? merchantKey;
  final String? logoUrl;
  final int accentColor;

  const CatalogResolution({
    required this.iconKey,
    this.merchantKey,
    this.logoUrl,
    this.accentColor = 0xFF147D64,
  });

  factory CatalogResolution.fromJson(Map<String, dynamic> json) =>
      CatalogResolution(
        iconKey: json['iconKey'] as String? ?? 'category',
        merchantKey: json['merchantKey'] as String?,
        logoUrl: json['logoUrl'] as String?,
        accentColor: _colorFromHex(json['accentColor'] as String?),
      );

  factory CatalogResolution.fallback(String value) {
    final name = normalizeName(value);
    if (['grocery', 'groceries', 'food', 'market'].any(name.contains)) {
      return const CatalogResolution(iconKey: 'groceries');
    }
    if (['rent', 'home', 'housing'].any(name.contains)) {
      return const CatalogResolution(iconKey: 'home');
    }
    if (['electric', 'power', 'utility'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'electricity',
        accentColor: 0xFFE6A700,
      );
    }
    if ([
      'subscription',
      'netflix',
      'youtube',
      'chatgpt',
      'claude',
    ].any(name.contains)) {
      String? merchant;
      for (final candidate in ['netflix', 'youtube', 'chatgpt', 'claude']) {
        if (name.contains(candidate)) {
          merchant = candidate;
          break;
        }
      }
      final brandStyle = switch (merchant) {
        'netflix' => const CatalogResolution(
          iconKey: 'netflix',
          merchantKey: 'netflix',
          accentColor: 0xFFE50914,
        ),
        'youtube' => const CatalogResolution(
          iconKey: 'youtube',
          merchantKey: 'youtube',
          accentColor: 0xFFFF0000,
        ),
        'chatgpt' => const CatalogResolution(
          iconKey: 'chatgpt',
          merchantKey: 'chatgpt',
          accentColor: 0xFF10A37F,
        ),
        'claude' => const CatalogResolution(
          iconKey: 'claude',
          merchantKey: 'claude',
          accentColor: 0xFFD97757,
        ),
        _ => const CatalogResolution(iconKey: 'subscriptions'),
      };
      return brandStyle;
    }
    if (['shopping', 'shop', 'clothes', 'fashion'].any(name.contains)) {
      return const CatalogResolution(iconKey: 'shopping');
    }
    if (['beauty', 'salon', 'makeup'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'beauty',
        accentColor: 0xFFB55277,
      );
    }
    if (['travel', 'flight', 'hotel'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'travel',
        accentColor: 0xFF4B68C7,
      );
    }
    if (['health', 'medical', 'pharmacy'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'health',
        accentColor: 0xFFD34F64,
      );
    }
    if (['pet', 'pets', 'vet'].any(name.contains)) {
      return const CatalogResolution(iconKey: 'pets', accentColor: 0xFFAD713F);
    }
    if (['restaurant', 'dining', 'cafe', 'takeaway'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'dining',
        accentColor: 0xFFDF7547,
      );
    }
    if (['transport', 'fuel', 'commute', 'uber', 'cab'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'transport',
        accentColor: 0xFF47719A,
      );
    }
    if (['education', 'school', 'tuition'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'education',
        accentColor: 0xFF7562A9,
      );
    }
    if (['internet', 'broadband', 'phone bill'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'internet',
        accentColor: 0xFF448A9C,
      );
    }
    if (['entertainment', 'cinema', 'movies', 'games'].any(name.contains)) {
      return const CatalogResolution(
        iconKey: 'entertainment',
        accentColor: 0xFF9A65A8,
      );
    }
    if (name.contains('insurance')) {
      return const CatalogResolution(
        iconKey: 'insurance',
        accentColor: 0xFF4B7182,
      );
    }
    return const CatalogResolution(iconKey: 'category');
  }
}

String normalizeName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? 0;
}

int _colorFromHex(String? value) {
  if (value == null || value.isEmpty) return 0xFF147D64;
  final hex = value.replaceAll('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return 0xFF147D64;
  return hex.length == 6 ? 0xFF000000 | parsed : parsed;
}
