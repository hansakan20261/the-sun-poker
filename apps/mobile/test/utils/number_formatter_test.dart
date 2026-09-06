import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/utils/number_formatter.dart';

void main() {
  group('NumberFormatter.formatAbbreviated', () {
    test('formats millions with M suffix', () {
      expect(NumberFormatter.formatAbbreviated(4450000), '4.45M');
      expect(NumberFormatter.formatAbbreviated(1000000), '1M');
      expect(NumberFormatter.formatAbbreviated(5000000), '5M');
      expect(NumberFormatter.formatAbbreviated(20000000), '20M');
      expect(NumberFormatter.formatAbbreviated(100000000), '100M');
    });

    test('formats thousands with K suffix', () {
      expect(NumberFormatter.formatAbbreviated(293800), '293.8K');
      expect(NumberFormatter.formatAbbreviated(1500), '1.5K');
      expect(NumberFormatter.formatAbbreviated(1000), '1K');
      expect(NumberFormatter.formatAbbreviated(50000), '50K');
      expect(NumberFormatter.formatAbbreviated(200000), '200K');
      expect(NumberFormatter.formatAbbreviated(500000), '500K');
    });

    test('formats amounts below 1000 as-is', () {
      expect(NumberFormatter.formatAbbreviated(500), '500');
      expect(NumberFormatter.formatAbbreviated(0), '0');
      expect(NumberFormatter.formatAbbreviated(999), '999');
      expect(NumberFormatter.formatAbbreviated(1), '1');
    });
  });

  group('NumberFormatter.formatWithCommas', () {
    test('formats numbers with comma separators', () {
      expect(NumberFormatter.formatWithCommas(341198), '341,198');
      expect(NumberFormatter.formatWithCommas(1000), '1,000');
      expect(NumberFormatter.formatWithCommas(2000), '2,000');
      expect(NumberFormatter.formatWithCommas(15000), '15,000');
      expect(NumberFormatter.formatWithCommas(1000000), '1,000,000');
    });

    test('does not add commas for numbers below 1000', () {
      expect(NumberFormatter.formatWithCommas(0), '0');
      expect(NumberFormatter.formatWithCommas(999), '999');
      expect(NumberFormatter.formatWithCommas(100), '100');
    });
  });

  group('NumberFormatter.formatBlinds', () {
    test('formats blinds with Thai label and ante', () {
      expect(
        NumberFormatter.formatBlinds(1000, 2000, 1000),
        'บลายด์: 1,000/2,000 Ante: 1,000',
      );
    });

    test('formats small blinds without commas', () {
      expect(
        NumberFormatter.formatBlinds(50, 100, 10),
        'บลายด์: 50/100 Ante: 10',
      );
    });

    test('formats large blinds with commas', () {
      expect(
        NumberFormatter.formatBlinds(50000, 100000, 10000),
        'บลายด์: 50,000/100,000 Ante: 10,000',
      );
    });
  });
}
