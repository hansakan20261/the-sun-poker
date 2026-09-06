import 'thai_labels.dart';

/// Pure utility for formatting numbers with Thai-appropriate abbreviated notation.
class NumberFormatter {
  /// Formats a number with abbreviated suffix.
  ///
  /// Amounts ≥ 1,000,000 use "M" suffix, ≥ 1,000 use "K" suffix, < 1,000 as-is.
  ///
  /// Examples:
  /// - 4450000 → "4.45M"
  /// - 293800 → "293.8K"
  /// - 1500 → "1.5K"
  /// - 500 → "500"
  static String formatAbbreviated(int amount) {
    if (amount >= 1000000) {
      final value = amount / 1000000;
      return '${_trimTrailingZeros(value)}M';
    } else if (amount >= 1000) {
      final value = amount / 1000;
      return '${_trimTrailingZeros(value)}K';
    }
    return amount.toString();
  }

  /// Formats with comma separators.
  ///
  /// Example: 341198 → "341,198", -640 → "-640"
  static String formatWithCommas(int amount) {
    final isNegative = amount < 0;
    final str = amount.abs().toString();
    final buffer = StringBuffer();
    final length = str.length;
    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return isNegative ? '-${buffer.toString()}' : buffer.toString();
  }

  /// Formats blinds info string.
  ///
  /// Example: formatBlinds(1000, 2000, 1000) → "บลายด์: 1,000/2,000 Ante: 1,000"
  static String formatBlinds(int smallBlind, int bigBlind, int ante) {
    final sb = formatWithCommas(smallBlind);
    final bb = formatWithCommas(bigBlind);
    final a = formatWithCommas(ante);
    return '${ThaiLabels.blinds}: $sb/$bb Ante: $a';
  }

  /// Short format for preset buttons — compact display.
  ///
  /// Examples: 26 → "26", 1500 → "1.5K", 20000 → "20K"
  static String formatShort(int amount) {
    if (amount >= 1000000) {
      final value = amount / 1000000;
      return '${_trimTrailingZeros(value)}M';
    } else if (amount >= 10000) {
      final value = amount / 1000;
      return '${_trimTrailingZeros(value)}K';
    } else if (amount >= 1000) {
      return formatWithCommas(amount);
    }
    return amount.toString();
  }

  /// Removes unnecessary trailing zeros from a decimal number.
  /// Keeps up to 2 decimal places.
  static String _trimTrailingZeros(double value) {
    // Round to 2 decimal places to avoid floating point artifacts
    final rounded = (value * 100).round() / 100;
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    // Format with up to 2 decimal places, trim trailing zeros
    final str = rounded.toStringAsFixed(2);
    var end = str.length;
    while (end > 0 && str[end - 1] == '0') {
      end--;
    }
    if (end > 0 && str[end - 1] == '.') {
      end--;
    }
    return str.substring(0, end);
  }
}
