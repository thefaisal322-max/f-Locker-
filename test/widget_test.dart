import 'package:f_locker/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

// Kept so `flutter create` does not add its default counter-app test.
void main() {
  test('there are six content tabs', () {
    expect(VaultTab.values.length, 6);
  });
}
