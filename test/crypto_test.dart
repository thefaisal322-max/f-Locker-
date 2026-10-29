import 'package:f_locker/core/crypto.dart';
import 'package:f_locker/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> _collect(Stream<List<int>> s) async {
  final out = <int>[];
  await for (final c in s) {
    out.addAll(c);
  }
  return out;
}

void main() {
  test('recovery key is 10 easy-to-read characters', () {
    final k = newRecoveryKey();
    expect(k.length, 10);
    expect(k.split('').every(recoveryAlphabet.contains), isTrue);
  });

  test('file encryption round trip across several chunks', () async {
    final key = randomBytes(32);
    final data = List<int>.generate(chunkSize * 2 + 12345, (i) => i % 251);
    final enc = await _collect(encryptStream(Stream.value(data), key));
    final dec = await _collect(decryptStream(Stream.value(enc), key));
    expect(dec, data);
  });

  test('empty file round trip', () async {
    final key = randomBytes(32);
    final enc = await _collect(encryptStream(Stream.value(<int>[]), key));
    final dec = await _collect(decryptStream(Stream.value(enc), key));
    expect(dec, isEmpty);
  });

  test('wrong key is rejected', () async {
    final enc = await _collect(
        encryptStream(Stream.value(List<int>.filled(100, 7)), randomBytes(32)));
    expect(_collect(decryptStream(Stream.value(enc), randomBytes(32))),
        throwsA(isA<WrongSecret>()));
  });

  test('cut-off file is detected', () async {
    final key = randomBytes(32);
    final enc = await _collect(encryptStream(
        Stream.value(List<int>.filled(chunkSize + 10, 1)), key));
    final cut = enc.sublist(0, 16 + 4 + chunkSize + 16);
    expect(_collect(decryptStream(Stream.value(cut), key)),
        throwsA(isA<FormatException>()));
  });

  test('sealed values open only with the right key', () async {
    final key = randomBytes(32);
    final sealed = await sealBytes([1, 2, 3], key);
    expect(await openBytes(sealed, key), [1, 2, 3]);
    expect(openBytes(sealed, randomBytes(32)), throwsA(isA<WrongSecret>()));
  });

  test('received files go to the right tab', () {
    expect(tabForName('a.MP4'), VaultTab.videos);
    expect(tabForName('b.jpg'), VaultTab.images);
    expect(tabForName('c.apk'), VaultTab.apps);
    expect(tabForName('d.7z'), VaultTab.zips);
    expect(tabForName('e.pdf'), VaultTab.documents);
  });
}
