import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'finance_engine.dart';
import 'finance_models.dart';

class MadsConversationMessage {
  final String role;
  final String content;

  const MadsConversationMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class MadsFinanceContext {
  final Map<String, dynamic> facts;
  final String currency;

  /// Free to spend this month, as the home screen shows it (never below 0).
  /// Purchase checks are measured against this.
  final int? freeToSpendMinor;

  const MadsFinanceContext({
    required this.facts,
    required this.currency,
    required this.freeToSpendMinor,
  });

  /// [excludedBoardIds] are boards answered "not in this month's plan". Pass
  /// the same set the home screen uses so the figures match it exactly.
  factory MadsFinanceContext.fromState(
    FinanceState state, {
    DateTime? now,
    Set<String> excludedBoardIds = const {},
  }) {
    final profile = state.profile;
    final date = now ?? DateTime.now();
    // The same calculation as the home screen's "Safe to spend today" card.
    final safe = computeSafeToSpend(
      state,
      date,
      excludedBoardIds: excludedBoardIds,
    );
    final period = periodOf(date);
    final currency = profile?.currency ?? 'INR';
    final categoryTotals =
        state.boards
            .map(
              (board) => (board.name, state.spentFor(board.id, period: period)),
            )
            .where((entry) => entry.$2 != 0)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    final categorySpend = categoryTotals
        .map(
          (entry) => <String, dynamic>{
            'category': entry.$1,
            'amount': Money.format(entry.$2, currency: currency),
          },
        )
        .toList();
    final monthSpentMinor = state.boards.fold<int>(
      0,
      (total, board) => total + state.spentFor(board.id, period: period),
    );
    final allocatedMinor = state.allocations
        .where((allocation) => allocation.periodStart == period)
        .fold(0, (total, allocation) => total + allocation.amountMinor);
    String? format(int? minor) =>
        minor == null ? null : Money.format(minor, currency: currency);

    return MadsFinanceContext(
      currency: currency,
      freeToSpendMinor: safe.freeToSpendMinor,
      facts: {
        'currency': currency,
        'month': '${date.year}-${date.month.toString().padLeft(2, '0')}',
        'monthlyIncome': profile == null
            ? null
            : Money.format(profile.monthlyIncomeMinor, currency: currency),
        'balanceSnapshot': profile == null
            ? null
            : Money.format(profile.balanceMinor, currency: currency),
        'balanceSnapshotDate': profile?.balanceAsOf.toIso8601String(),
        'monthlySavingsTarget': profile == null
            ? null
            : Money.format(profile.plannedSavingsMinor, currency: currency),
        // These match the home screen's "Safe to spend today" card.
        'balanceNow': format(safe.balanceNowMinor),
        'savingsKeptAside': format(safe.savingsKeptMinor),
        'keptForBoards': format(safe.keptForBoardsMinor),
        'freeToSpendThisMonth': format(safe.freeToSpendMinor),
        'safeToSpendToday': format(safe.safeTodayDisplayMinor),
        'daysLeftInMonthIncludingToday': safe.daysLeft,
        'postedTransactionsAfterBalanceSnapshot': profile == null
            ? null
            : Money.format(
                state.transactionsSinceBalanceSnapshotMinor,
                currency: currency,
              ),
        'postedSpendingThisMonth': Money.format(
          monthSpentMinor,
          currency: currency,
        ),
        'spendingByCategory': categorySpend,
        // Each board's plan for this month, worded like the board tiles.
        'boardsThisMonth': [
          for (final board in state.boards)
            _boardFacts(
              board,
              plannedMinor: state.allocationFor(board.id, period),
              spentMinor: state.spentFor(board.id, period: period),
              inPlan: !excludedBoardIds.contains(board.id),
              currency: currency,
            ),
        ],
        'currentMonthAllocations': Money.format(
          allocatedMinor,
          currency: currency,
        ),
        'actualSavingsProgress': 'not tracked in the available finance data',
        'unpaidCommitments': 'not captured by the current money profile',
        'transactionHistoryAvailable': state.transactions.isNotEmpty,
        'incomeToBalanceReconciliation': state.transactions.isEmpty
            ? 'unexplained by available records; no spending is inferred'
            : 'not reconciled; account and period coverage is not confirmed',
        'calculationNotes': [
          'The balance is a snapshot, separate from monthly income.',
          'The income-to-balance difference is not spending.',
          'Balance now is the balance snapshot adjusted for posted transactions dated after it.',
          'Transactions dated on or before the snapshot are treated as already reflected.',
          'The monthly savings target is a planning goal, not savings already achieved.',
          'Free to spend this month = balance now minus savings kept aside minus money kept for boards (shown as zero if that is negative).',
          'Safe to spend today = free to spend this month divided by the days left in the month, including today. This is the figure on the home screen.',
          'When asked what can be spent today, quote safe to spend today, not the balance now.',
          'Money that can still be planned for a board, or spent freely, is the free to spend this month figure. There is no other unassigned or unplanned pool; never suggest moving money that is not part of free to spend.',
        ],
      },
    );
  }

  /// One board's plan, spending and status, using the same wording as the
  /// board tiles on the home and Boards screens.
  static Map<String, dynamic> _boardFacts(
    ExpenseBoard board, {
    required int plannedMinor,
    required int spentMinor,
    required bool inPlan,
    required String currency,
  }) {
    String money(int minor) => Money.format(minor, currency: currency);
    final left = plannedMinor - spentMinor;
    final isBill = board.type == BoardType.bill;
    final String status;
    if (!inPlan) {
      status = "Not in this month's plan";
    } else if (isBill) {
      status = plannedMinor == 0
          ? 'Amount not set'
          : (left <= 0 ? 'Paid' : 'Due ${money(left)}');
    } else {
      status = plannedMinor == 0
          ? 'Budget not set'
          : (left < 0
                ? 'Over budget by ${money(-left)}'
                : '${money(left)} left of ${money(plannedMinor)}');
    }
    return {
      'board': board.name,
      'kind': isBill ? 'bill' : 'budget',
      'plannedThisMonth': plannedMinor == 0 ? 'not set' : money(plannedMinor),
      'spentThisMonth': money(spentMinor),
      'status': status,
    };
  }

  Map<String, dynamic> factsForQuestion(String question) {
    final factsForQuestion = Map<String, dynamic>.of(facts);
    final lowerQuestion = question.toLowerCase();
    final asksAffordability = RegExp(
      r'\b(afford|buy|purchase)\b|\b(can|could|should)\s+(i|we)\s+spend\b',
    ).hasMatch(lowerQuestion);
    if (!asksAffordability) return factsForQuestion;

    final amountMatch = RegExp(
      r'(?:₹|rs\.?\s*)([\d,]+(?:\.\d{1,2})?)|\b(?:for|costs?\s+about|around)\s+([\d,]+(?:\.\d{1,2})?)|\b(?:afford|buy|purchase|spend)\b[^\d]{0,20}([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(question);
    final rawAmount =
        amountMatch?.group(1) ?? amountMatch?.group(2) ?? amountMatch?.group(3);
    final purchaseMinor = rawAmount == null
        ? null
        : Money.parseMinor(rawAmount);
    // "What can I spend today?" names no purchase: answer from the figures
    // above instead of asking for an amount. Only "afford/buy/purchase"
    // questions without an amount need one.
    final namesAPurchase = RegExp(
      r'\b(afford|buy|purchase)\b',
    ).hasMatch(lowerQuestion);
    if (purchaseMinor == null && !namesAPurchase) return factsForQuestion;
    if (purchaseMinor == null || freeToSpendMinor == null) {
      factsForQuestion['questionSpecificVerifiedCheck'] = 'A purchase amount or a saved current balance is missing. Ask only for the missing detail.';
      return factsForQuestion;
    }

    final remainingMinor = freeToSpendMinor! - purchaseMinor;
    factsForQuestion['questionSpecificVerifiedCheck'] = {
      'purchaseAmount': Money.format(purchaseMinor, currency: currency),
      'freeToSpendBeforePurchase': Money.format(
        freeToSpendMinor!,
        currency: currency,
      ),
      'fitsWithinFreeToSpend': remainingMinor >= 0,
      'freeToSpendAfterPurchase': Money.format(
        remainingMinor,
        currency: currency,
      ),
    };
    return factsForQuestion;
  }
}

/// How Money Angel talks. Only the tone changes: every personality uses the
/// same figures and never scolds about spending (enforced in the
/// mads-finance-chat function).
enum MadsPersonality {
  friendly('friendly', 'Friendly', 'Warm and encouraging.'),
  sarcastic('sarcastic', 'Sarcastic', 'Dry wit, never at your expense.'),
  witch(
    'woo_woo_witch',
    'Woo Woo Witch',
    'Mystical vibes, with a short money affirmation.',
  );

  const MadsPersonality(this.wireName, this.label, this.description);

  /// The value sent to the chat function and saved on the device.
  final String wireName;
  final String label;
  final String description;

  static MadsPersonality fromWireName(String? value) => values.firstWhere(
    (personality) => personality.wireName == value,
    orElse: () => MadsPersonality.friendly,
  );
}

/// Saves each user's Money Angel personality on this device.
class MadsPersonalityStore {
  static String _key(String userId) => 'mads_${userId}_money_angel_personality';

  /// The user's saved personality, or Friendly if none is saved or device
  /// storage isn't available.
  static Future<MadsPersonality> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return MadsPersonality.fromWireName(prefs.getString(_key(userId)));
    } catch (_) {
      return MadsPersonality.friendly;
    }
  }

  static Future<void> save(String userId, MadsPersonality personality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), personality.wireName);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

abstract interface class MadsAssistant {
  Future<String> reply({
    required MadsFinanceContext context,
    required List<MadsConversationMessage> conversation,
    MadsPersonality personality = MadsPersonality.friendly,
  });
}

class SupabaseMadsAssistant implements MadsAssistant {
  SupabaseMadsAssistant(this.client);

  final SupabaseClient client;

  @override
  Future<String> reply({
    required MadsFinanceContext context,
    required List<MadsConversationMessage> conversation,
    MadsPersonality personality = MadsPersonality.friendly,
  }) async {
    final latestUserMessage = conversation.lastWhere(
      (message) => message.role == 'user',
      orElse: () => const MadsConversationMessage(role: 'user', content: ''),
    );
    final response = await client.functions.invoke(
      'mads-finance-chat',
      body: {
        'financialContext': context.factsForQuestion(latestUserMessage.content),
        'messages': conversation.map((message) => message.toJson()).toList(),
        'personality': personality.wireName,
      },
    );
    final data = response.data;
    if (data is Map && data['reply'] is String) {
      final reply = (data['reply'] as String).trim();
      if (reply.isNotEmpty) return reply;
    }
    throw const MadsAssistantException(
      'Money Angel could not prepare a reply. Please try again.',
    );
  }
}

class MadsAssistantException implements Exception {
  const MadsAssistantException(this.message);

  final String message;

  @override
  String toString() => message;
}
