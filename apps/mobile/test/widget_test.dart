import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/utils/thai_labels.dart';

void main() {
  test('ThaiLabels constants are defined', () {
    expect(ThaiLabels.fold, 'หมอบ');
    expect(ThaiLabels.call, 'ตาม');
    expect(ThaiLabels.raise, 'เก');
    expect(ThaiLabels.handNames.length, 10);
    expect(ThaiLabels.lobby, 'ล็อบบี้');
  });
}
