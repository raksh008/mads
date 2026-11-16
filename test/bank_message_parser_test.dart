import 'package:flutter_test/flutter_test.dart';
import 'package:mads/finance/bank_message_parser.dart';

// Sample wording in the style of common Indian bank / UPI messages.
// Account numbers and references are made up.
void main() {
  void expectRead(
    String message, {
    required int amountMinor,
    required bool isDebit,
    required String merchant,
    required DateTime date,
  }) {
    final parsed = parseBankMessage(message);
    expect(parsed.readable, isTrue, reason: message);
    expect(parsed.amountMinor, amountMinor, reason: message);
    expect(parsed.isDebit, isDebit, reason: message);
    expect(parsed.merchant, merchant, reason: message);
    expect(parsed.date, date, reason: message);
  }

  test('HDFC UPI debit, "Sent … To"', () {
    expectRead(
      'Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 14/11/26 '
      'Ref 612345678901 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808',
      amountMinor: 25000,
      isDebit: true,
      merchant: 'SWIGGY',
      date: DateTime(2026, 11, 14),
    );
  });

  test('HDFC debit to a VPA', () {
    expectRead(
      'Rs.500.00 debited from a/c **1234 on 13-11-26 to VPA chai.point@okicici '
      '(UPI Ref No 612345678902). Not you? Call on 18002586161 to report',
      amountMinor: 50000,
      isDebit: true,
      merchant: 'chai.point@okicici',
      date: DateTime(2026, 11, 13),
    );
  });

  test('HDFC credit from a VPA, with time', () {
    expectRead(
      'Rs. 80,000.00 credited to HDFC Bank A/c XX1234 on 01-11-26 10:15:00 by '
      'a/c linked to VPA acme.payroll@okaxis (UPI Ref No 612345678903).',
      amountMinor: 8000000,
      isDebit: false,
      merchant: 'acme.payroll@okaxis',
      date: DateTime(2026, 11, 1, 10, 15),
    );
  });

  test('HDFC card, "Thank you for using"', () {
    expectRead(
      'Thank you for using HDFC Bank Card XX1234 for Rs. 450.00 at ZOMATO on '
      '14-11-2026 11:32:10. Not you? SMS BLOCK 1234 to 7308080808',
      amountMinor: 45000,
      isDebit: true,
      merchant: 'ZOMATO',
      date: DateTime(2026, 11, 14, 11, 32, 10),
    );
  });

  test('SBI UPI debit, "debited by … trf to"', () {
    expectRead(
      'Dear UPI user A/C X1234 debited by 250.0 on date 14Nov26 trf to '
      'SWIGGY Refno 612345678904. If not u? call 1800111109. -SBI',
      amountMinor: 25000,
      isDebit: true,
      merchant: 'SWIGGY',
      date: DateTime(2026, 11, 14),
    );
  });

  test('SBI credit; the available balance is not the amount', () {
    expectRead(
      'Your A/C XXXXX1234 Credited INR 80,000.00 on 01/11/26 -Deposit by '
      'transfer from ACME LTD. Avl Bal INR 1,20,000.00-SBI',
      amountMinor: 8000000,
      isDebit: false,
      merchant: 'ACME LTD',
      date: DateTime(2026, 11, 1),
    );
  });

  test('ICICI UPI debit, "; MERCHANT credited"', () {
    expectRead(
      'ICICI Bank Acct XX123 debited for Rs 250.00 on 14-Nov-26; SWIGGY '
      'credited. UPI:612345678905. Call 18002662 for dispute. SMS BLOCK 123 '
      'to 9215676766.',
      amountMinor: 25000,
      isDebit: true,
      merchant: 'SWIGGY',
      date: DateTime(2026, 11, 14),
    );
  });

  test('ICICI credit "from"', () {
    expectRead(
      'Dear Customer, Acct XX123 is credited with Rs 500.00 on 13-Nov-26 from '
      'RAHUL S. UPI:612345678906-ICICI Bank.',
      amountMinor: 50000,
      isDebit: false,
      merchant: 'RAHUL S',
      date: DateTime(2026, 11, 13),
    );
  });

  test('ICICI credit card spend; the limit is not the amount', () {
    expectRead(
      'INR 1,299.00 spent on ICICI Bank Credit Card XX1234 on 14-Nov-26 at '
      'AMAZON. Avl Lmt: INR 50,000.00. To dispute, call 18002662.',
      amountMinor: 129900,
      isDebit: true,
      merchant: 'AMAZON',
      date: DateTime(2026, 11, 14),
    );
  });

  test('UPI app "Paid ₹ … to … via UPI"', () {
    expectRead(
      'Paid ₹120 to Chai Point via UPI on 14-11-2026',
      amountMinor: 12000,
      isDebit: true,
      merchant: 'Chai Point',
      date: DateTime(2026, 11, 14),
    );
  });

  test('a message without amount or direction is unreadable', () {
    final parsed = parseBankMessage(
      'Your OTP for login is 482913. Do not share it with anyone.',
    );
    expect(parsed.readable, isFalse);
    expect(parsed.preview, startsWith('Your OTP for login'));
  });

  test('no merchant found falls back to "Bank transaction"; no date is null', () {
    final parsed = parseBankMessage('Rs 300 debited from your account');
    expect(parsed.readable, isTrue);
    expect(parsed.merchant, 'Bank transaction');
    expect(parsed.date, isNull);
  });

  test('splits by blank lines, or by line when each line is a message', () {
    expect(
      splitBankMessages(
        'Sent Rs.250.00 To SWIGGY On 14/11/26\n'
        'Paid ₹120 to Chai Point via UPI on 14-11-2026',
      ),
      hasLength(2),
    );
    // A message wrapped over two lines stays one message.
    expect(
      splitBankMessages(
        'Rs.500.00 debited from a/c **1234 on 13-11-26\n'
        'to VPA chai.point@okicici (UPI Ref No 6123)\n'
        '\n'
        'Your OTP is 4829.',
      ),
      hasLength(2),
    );
  });

  test('the duplicate key is amount, merchant and day only', () {
    expect(
      bankDuplicateKey(25000, 'SWIGGY ', DateTime(2026, 11, 14, 9, 30)),
      bankDuplicateKey(25000, 'swiggy', DateTime(2026, 11, 14, 21)),
    );
  });
}
