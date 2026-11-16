import 'package:flutter/material.dart';

import '../branding.dart';
import 'bank_message_parser.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

/// One reviewed row the user chose to add. Holds no message text.
class BankMessageEntry {
  final String boardId;
  final String merchant;
  final int amountMinor;
  final DateTime date;
  final bool isDebit;

  /// Amount, merchant and day, to skip this transaction if pasted again.
  final String duplicateKey;

  const BankMessageEntry({
    required this.boardId,
    required this.merchant,
    required this.amountMinor,
    required this.date,
    required this.isDebit,
    required this.duplicateKey,
  });
}

/// Paste bank / UPI SMS texts, review what was read, then add them.
/// Messages are read on the phone; the pasted text is never saved or sent
/// anywhere and is cleared as soon as it has been read.
class BankMessagesScreen extends StatefulWidget {
  final List<ExpenseBoard> boards;

  /// Already-saved transactions, to mark duplicates.
  final List<FinanceTransaction> existing;

  const BankMessagesScreen({
    super.key,
    required this.boards,
    required this.existing,
  });

  @override
  State<BankMessagesScreen> createState() => _BankMessagesScreenState();
}

class _Row {
  final ParsedBankMessage parsed;
  final DateTime date;
  final String? duplicateKey;
  final bool duplicate;
  bool ticked;
  String? boardId;

  _Row({
    required this.parsed,
    required this.date,
    required this.duplicateKey,
    required this.duplicate,
    required this.ticked,
    required this.boardId,
  });
}

class _BankMessagesScreenState extends State<BankMessagesScreen> {
  final pasteController = TextEditingController();
  List<_Row>? rows;

  /// Shown above the buttons (a snackbar would cover "Add all").
  String? reviewMessage;

  @override
  void dispose() {
    pasteController.dispose();
    super.dispose();
  }

  /// The board whose name appears in the merchant, if exactly one does.
  String? _guessBoard(String merchant) {
    final name = normalizeName(merchant);
    final matches = widget.boards.where((board) {
      final boardName = normalizeName(board.name);
      return boardName.isNotEmpty &&
          (name.contains(boardName) || boardName.contains(name));
    }).toList();
    return matches.length == 1 ? matches.single.id : null;
  }

  void _read() {
    final parsed = parseBankMessages(pasteController.text);
    // The raw text isn't kept once it has been read.
    pasteController.clear();
    final seen = {
      for (final item in widget.existing)
        bankDuplicateKey(
          item.amountMinor,
          item.description,
          item.occurredAt.toLocal(),
        ),
      for (final item in widget.existing)
        if (item.externalId != null) item.externalId!,
    };
    final now = DateTime.now();
    final result = <_Row>[];
    for (final message in parsed) {
      final date = message.date ?? now;
      final key = message.readable
          ? bankDuplicateKey(message.amountMinor!, message.merchant, date)
          : null;
      final duplicate = key != null && !seen.add(key);
      result.add(
        _Row(
          parsed: message,
          date: date,
          duplicateKey: key,
          duplicate: duplicate,
          ticked: message.readable && !duplicate,
          boardId: _guessBoard(message.merchant),
        ),
      );
    }
    setState(() {
      rows = result;
      reviewMessage = null;
    });
  }

  List<_Row> get _ticked =>
      (rows ?? const <_Row>[]).where((row) => row.ticked).toList();

  void _addAll() {
    final ticked = _ticked;
    if (ticked.any((row) => row.boardId == null)) {
      setState(() => reviewMessage = 'Choose a board for every ticked row.');
      return;
    }
    Navigator.pop(context, [
      for (final row in ticked)
        BankMessageEntry(
          boardId: row.boardId!,
          merchant: row.parsed.merchant,
          amountMinor: row.parsed.amountMinor!,
          date: row.date,
          isDebit: row.parsed.isDebit!,
          duplicateKey: row.duplicateKey!,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paste bank messages')),
    body: SafeArea(child: rows == null ? _pasteView() : _reviewView()),
  );

  Widget _pasteView() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text(
        'Paste one or more bank or UPI SMS messages. They are read on this '
        'phone only, and the text is never saved or uploaded.',
        style: TextStyle(color: madsMutedText, height: 1.45),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: pasteController,
        minLines: 6,
        maxLines: 14,
        decoration: const InputDecoration(
          labelText: 'Bank messages',
          hintText: 'Leave a blank line between messages',
          alignLabelWithHint: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: pasteController.text.trim().isEmpty ? null : _read,
        icon: const Icon(Icons.manage_search_rounded),
        label: const Text('Read messages'),
      ),
    ],
  );

  Widget _reviewView() {
    final list = rows!;
    final ticked = _ticked.length;
    return Column(
      children: [
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No messages found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _rowTile(list[index]),
                ),
        ),
        if (reviewMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              reviewMessage!,
              style: const TextStyle(color: madsDanger, fontWeight: FontWeight.w600),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => rows = null),
                child: const Text('Paste again'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: ticked == 0 ? null : _addAll,
                  child: Text('Add all ($ticked)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rowTile(_Row row) {
    final parsed = row.parsed;
    if (!parsed.readable) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.help_outline, color: madsDanger),
          title: const Text("Couldn't read this message"),
          subtitle: Text(parsed.preview),
        ),
      );
    }
    final amount = Money.format(parsed.amountMinor!);
    final dateLabel =
        '${row.date.day}/${row.date.month}/${row.date.year}'
        '${parsed.date == null ? ' (no date found, using today)' : ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(
              value: row.ticked,
              onChanged: row.duplicate
                  ? null
                  : (value) => setState(() => row.ticked = value ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${parsed.isDebit! ? 'Debit −' : 'Credit +'}$amount · '
                    '$dateLabel',
                    style: const TextStyle(color: madsMutedText, fontSize: 12),
                  ),
                  if (row.duplicate)
                    const Text(
                      'Already added',
                      style: TextStyle(
                        color: madsFaintText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    DropdownButton<String>(
                      value: row.boardId,
                      isExpanded: true,
                      hint: const Text('Choose board'),
                      items: [
                        for (final board in widget.boards)
                          DropdownMenuItem(
                            value: board.id,
                            child: Text(board.name),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        row.boardId = value;
                        reviewMessage = null;
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
