/// Reads pasted bank / UPI SMS texts on the phone. Nothing here touches the
/// network or storage: callers get back only the amount, merchant, date and
/// direction, never a copy of the raw message to save.
library;

/// One pasted message after reading it.
class ParsedBankMessage {
  /// In minor units (paise). Null when the message couldn't be read.
  final int? amountMinor;

  /// True for money out (debit), false for money in (credit).
  final bool? isDebit;

  /// Merchant, payee or payer. "Bank transaction" when none was found.
  final String merchant;

  /// When the message says it happened. Null when no date was found.
  final DateTime? date;

  /// True when the message included a time, not just a date.
  final bool hasTime;

  /// A short start of the message, for the "couldn't read" row only. It is
  /// shown on screen and never saved.
  final String preview;

  const ParsedBankMessage({
    required this.amountMinor,
    required this.isDebit,
    required this.merchant,
    required this.date,
    required this.hasTime,
    required this.preview,
  });

  bool get readable => amountMinor != null && isDebit != null;
}

/// Splits pasted text into messages: one per paragraph (blank line between),
/// or one per line when every line reads as its own message.
List<String> splitBankMessages(String text) {
  final chunks = text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((chunk) => chunk.trim())
      .where((chunk) => chunk.isNotEmpty);
  final messages = <String>[];
  for (final chunk in chunks) {
    final lines = chunk
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final eachLineIsAMessage =
        lines.length > 1 &&
        lines.every(
          (line) => _amountIn(_withoutBalances(line)) != null &&
              _direction(line) != null,
        );
    if (eachLineIsAMessage) {
      messages.addAll(lines);
    } else {
      messages.add(lines.join(' '));
    }
  }
  return messages;
}

/// Reads every message in [text].
List<ParsedBankMessage> parseBankMessages(String text) =>
    splitBankMessages(text).map(parseBankMessage).toList();

/// Reads one message: amount, debit or credit, merchant and date.
ParsedBankMessage parseBankMessage(String message) {
  final text = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  final amount = _amountIn(_withoutBalances(text));
  final isDebit = _direction(text);
  final (date, hasTime) = _dateIn(text);
  return ParsedBankMessage(
    amountMinor: amount,
    isDebit: isDebit,
    merchant: (isDebit == null ? null : _merchantIn(text, isDebit)) ??
        'Bank transaction',
    date: date,
    hasTime: hasTime,
    preview: text.length <= 48 ? text : '${text.substring(0, 48)}…',
  );
}

/// The key used to spot the same transaction twice: amount, merchant and
/// calendar date. It holds no message text.
String bankDuplicateKey(int amountMinor, String merchant, DateTime date) {
  final day =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return '$amountMinor|${_normalize(merchant)}|$day';
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

// ---------------------------------------------------------------- amount ---

const _number = r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)';

/// Drops "Avl Bal Rs 12,345", "Avl Lmt: INR 50,000" and similar, so the
/// account balance is never read as the transaction amount.
String _withoutBalances(String text) => text.replaceAll(
  RegExp(
    r'(?:avl\.?|avbl\.?|available|total|clear|closing)\s*'
    r'(?:bal(?:ance)?|lmt|limit|credit limit)\.?\s*(?:is|:)?\s*'
    r'(?:rs\.?|inr|₹)?\s*[0-9][0-9,]*(?:\.[0-9]+)?',
    caseSensitive: false,
  ),
  ' ',
);

int? _amountIn(String text) {
  final withCurrency = RegExp(
    r'(?:rs\.?|inr|₹)\s*' + _number,
    caseSensitive: false,
  ).firstMatch(text);
  // SBI: "debited by 250.0", "credited by 500" (no currency word).
  final match =
      withCurrency ??
      RegExp(
        r'(?:debited|credited)\s+(?:by|with|for)\s+' + _number,
        caseSensitive: false,
      ).firstMatch(text);
  if (match == null) return null;
  return _toMinor(match.group(1)!);
}

int? _toMinor(String raw) {
  final value = raw.replaceAll(',', '');
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length < 2
      ? 0
      : int.parse(parts[1].padRight(2, '0').substring(0, 2));
  final minor = whole * 100 + fraction;
  return minor > 0 ? minor : null;
}

// ------------------------------------------------------------- direction ---

final _debitWords = RegExp(
  r'\b(?:debited|spent|sent|paid|withdrawn|withdrawal|purchase|was used|'
  r'used for|using|dr)\b',
);

final _creditWords = RegExp(
  r'\b(?:credited|received|deposited|deposit|refund|refunded|cr)\b',
);

/// True for debit, false for credit, null when neither is said. When both
/// appear (ICICI: "debited for Rs 250; SWIGGY credited") the first wins.
bool? _direction(String text) {
  // "Credit Card" names the card, not the direction.
  final lower = text.toLowerCase().replaceAll('credit card', 'card');
  final debit = _debitWords.firstMatch(lower)?.start;
  final credit = _creditWords.firstMatch(lower)?.start;
  if (debit == null && credit == null) return null;
  if (credit == null) return true;
  if (debit == null) return false;
  return debit < credit;
}

// -------------------------------------------------------------- merchant ---

const _name = r"([A-Za-z0-9][A-Za-z0-9 &.'*_\-]*?)";
const _nameEnd =
    r"(?=\s+on\b|\s+ref(?:no)?\b|\s+via\b|\s+upi\b|\s+avl\b|\s+info\b|"
    r"[.,;:(]|$)";
const _vpa = r'([A-Za-z0-9._\-]+@[A-Za-z0-9.\-]+)';

String? _merchantIn(String text, bool isDebit) {
  final patterns = isDebit
      ? [
          RegExp(r'\bto\s+vpa\s+' + _vpa, caseSensitive: false),
          // ICICI: "debited for Rs 250.00 on 14-Nov-26; SWIGGY credited."
          RegExp(r';\s*' + _name + r'\s+credited\b', caseSensitive: false),
          RegExp(r'\bat\s+' + _name + _nameEnd, caseSensitive: false),
          RegExp(
            r'\b(?:trf to|transfer to|towards|to)\s+' + _name + _nameEnd,
            caseSensitive: false,
          ),
        ]
      : [
          RegExp(
            r'\b(?:from|linked to)\s+vpa\s+' + _vpa,
            caseSensitive: false,
          ),
          RegExp(
            r'\b(?:transfer from|from)\s+' + _name + _nameEnd,
            caseSensitive: false,
          ),
          RegExp(r'\bby\s+' + _name + _nameEnd, caseSensitive: false),
        ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(text)) {
      final name = _cleanName(match.group(1)!);
      if (name != null) return name;
    }
  }
  return null;
}

/// Tidies a candidate name, or rejects it when it's the user's own account
/// or card rather than a merchant.
String? _cleanName(String raw) {
  var name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  name = name.replaceAll(RegExp(r'[\s.\-*]+$'), '');
  if (name.length < 2) return null;
  final lower = name.toLowerCase();
  const notMerchants = [
    'a/c',
    'ac ',
    'acct',
    'account',
    'card',
    'your',
    'you',
    'bank',
    'transfer',
    'upi user',
    'customer',
  ];
  if (notMerchants.any(lower.startsWith) ||
      lower.contains('a/c') ||
      RegExp(r'^[x*]*\d+$').hasMatch(lower)) {
    return null;
  }
  return name.length > 40 ? name.substring(0, 40).trim() : name;
}

// ------------------------------------------------------------------ date ---

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// The message's date (day-month order, as Indian banks write it) and
/// whether it also gave a time.
(DateTime?, bool) _dateIn(String text) {
  DateTime? day;
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(text);
  final numeric = RegExp(
    r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b',
  ).firstMatch(text);
  final named = RegExp(
    r'\b(\d{1,2})[-\s]?([A-Za-z]{3})[A-Za-z]*[-\s,]*(\d{2,4})\b',
  ).firstMatch(text);
  if (iso != null) {
    day = _validDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  if (day == null && numeric != null) {
    day = _validDate(
      _fullYear(int.parse(numeric.group(3)!)),
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(1)!),
    );
  }
  if (day == null && named != null) {
    final month = _months[named.group(2)!.toLowerCase()];
    if (month != null) {
      day = _validDate(
        _fullYear(int.parse(named.group(3)!)),
        month,
        int.parse(named.group(1)!),
      );
    }
  }
  if (day == null) return (null, false);
  final time = RegExp(
    r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b',
  ).firstMatch(text);
  if (time == null) return (day, false);
  return (
    DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(time.group(1)!),
      int.parse(time.group(2)!),
      int.parse(time.group(3) ?? '0'),
    ),
    true,
  );
}

int _fullYear(int year) => year < 100 ? 2000 + year : year;

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || year < 2000 || year > 2100) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.month == month ? date : null; // rejects 31 Feb etc.
}
