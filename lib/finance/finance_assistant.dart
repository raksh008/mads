import 'package:supabase_flutter/supabase_flutter.dart';

import 'finance_models.dart';

class MevoraConversationMessage {
  final String role;
  final String content;

  const MevoraConversationMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class MevoraFinanceContext {
  final Map<String, dynamic> facts;
  final String currency;
  final int? safeToSpendMinor;

  const MevoraFinanceContext({
    required this.facts,
    required this.currency,
    required this.safeToSpendMinor,
  });

  factory MevoraFinanceContext.fromState(FinanceState state, {DateTime? now}) {
    final profile = state.profile;
    final date = now ?? DateTime.now();
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
    final poolMinor = profile?.monthlyBudgetPoolMinor;

    return MevoraFinanceContext(
      currency: currency,
      safeToSpendMinor: state.safeToSpendMinor,
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
        'safeToSpend': state.safeToSpendMinor == null
            ? null
            : Money.format(state.safeToSpendMinor!, currency: currency),
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
        'monthlyBudgetPool': poolMinor == null
            ? null
            : Money.format(poolMinor, currency: currency),
        'currentMonthAllocations': Money.format(
          allocatedMinor,
          currency: currency,
        ),
        'unassignedPlan': poolMinor == null
            ? null
            : Money.format(poolMinor - allocatedMinor, currency: currency),
        'actualSavingsProgress': 'not tracked in the available finance data',
        'unpaidCommitments': 'not captured by the current money profile',
        'transactionHistoryAvailable': state.transactions.isNotEmpty,
        'incomeToBalanceReconciliation': state.transactions.isEmpty
            ? 'unexplained by available records; no spending is inferred'
            : 'not reconciled; account and period coverage is not confirmed',
        'calculationNotes': [
          'The balance is a snapshot, separate from monthly income.',
          'The income-to-balance difference is not spending.',
          'Only posted transactions dated after the balance snapshot affect safe-to-spend.',
          'Transactions dated on or before the snapshot are treated as already reflected.',
          'The monthly savings target is a planning goal, not savings already achieved.',
          'The monthly savings target is not deducted from safe-to-spend.',
        ],
      },
    );
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
    if (purchaseMinor == null || safeToSpendMinor == null) {
      factsForQuestion['questionSpecificVerifiedCheck'] = 'A purchase amount or a saved current balance is missing. Ask only for the missing detail.';
      return factsForQuestion;
    }

    final remainingMinor = safeToSpendMinor! - purchaseMinor;
    factsForQuestion['questionSpecificVerifiedCheck'] = {
      'purchaseAmount': Money.format(purchaseMinor, currency: currency),
      'safeToSpendBeforePurchase': Money.format(
        safeToSpendMinor!,
        currency: currency,
      ),
      'affordableFromRecordedAvailableAmount': remainingMinor >= 0,
      'remainingAfterPurchase': Money.format(
        remainingMinor,
        currency: currency,
      ),
    };
    return factsForQuestion;
  }
}

abstract interface class MevoraAssistant {
  Future<String> reply({
    required MevoraFinanceContext context,
    required List<MevoraConversationMessage> conversation,
  });
}

class SupabaseMevoraAssistant implements MevoraAssistant {
  SupabaseMevoraAssistant(this.client);

  final SupabaseClient client;

  @override
  Future<String> reply({
    required MevoraFinanceContext context,
    required List<MevoraConversationMessage> conversation,
  }) async {
    final latestUserMessage = conversation.lastWhere(
      (message) => message.role == 'user',
      orElse: () => const MevoraConversationMessage(role: 'user', content: ''),
    );
    final response = await client.functions.invoke(
      'mevora-finance-chat',
      body: {
        'financialContext': context.factsForQuestion(latestUserMessage.content),
        'messages': conversation.map((message) => message.toJson()).toList(),
      },
    );
    final data = response.data;
    if (data is Map && data['reply'] is String) {
      final reply = (data['reply'] as String).trim();
      if (reply.isNotEmpty) return reply;
    }
    throw const MevoraAssistantException(
      'MEVORA could not prepare a reply. Please try again.',
    );
  }
}

class MevoraAssistantException implements Exception {
  const MevoraAssistantException(this.message);

  final String message;

  @override
  String toString() => message;
}
