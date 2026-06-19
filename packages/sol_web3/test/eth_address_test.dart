import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('EthAddress', () {
    test('fromHex accepts 0x-prefixed and bare hex, case-insensitively', () {
      final a = EthAddress.fromHex(
        '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      );
      final b = EthAddress.fromHex('f39fd6e51aad88f6f4ce6ab8827279cfffb92266');
      expect(a, b);
    });

    test('rejects byte arrays that are not 20 bytes', () {
      expect(() => EthAddress.fromHex('0x1234'), throwsArgumentError);
    });

    test('zero is the all-zero address', () {
      expect(
        EthAddress.zero.toHex(),
        '0x0000000000000000000000000000000000000000',
      );
    });

    // EIP-55 test vectors from the spec itself.
    for (final vector in const [
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
      '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
    ]) {
      test('toChecksumHex reproduces EIP-55 vector $vector', () {
        final address = EthAddress.fromHex(vector);
        expect(address.toChecksumHex(), vector);
      });
    }

    test('toString uses checksum casing', () {
      final address = EthAddress.fromHex(
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
      expect(address.toString(), address.toChecksumHex());
    });
  });
}
