import 'package:sol_support/sol_support.dart';
import 'package:test/test.dart';

void main() {
  group('keccak256', () {
    test('hashes the empty input', () {
      expect(
        keccak256HexOfString(''),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
    });

    test('hashes "abc"', () {
      expect(
        keccak256HexOfString('abc'),
        '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
      );
    });

    test('hashes a 136-byte (one full rate block) message', () {
      final msg = List<int>.generate(136, (i) => i & 0xff);
      expect(keccak256(msg).length, 32);
      // Stable, non-zero digest (exercises the all-blocks-then-pad path).
      expect(keccak256Hex(msg).substring(0, 8), isNot('00000000'));
    });

    test('computes the ERC-20 transfer selector', () {
      // keccak256("transfer(address,uint256)")[:4] == 0xa9059cbb
      final hash = keccak256HexOfString('transfer(address,uint256)');
      expect(hash.substring(0, 8), 'a9059cbb');
    });

    test('computes the ERC-20 approve selector', () {
      // keccak256("approve(address,uint256)")[:4] == 0x095ea7b3
      final hash = keccak256HexOfString('approve(address,uint256)');
      expect(hash.substring(0, 8), '095ea7b3');
    });

    test('is deterministic', () {
      expect(keccak256HexOfString('hello'), keccak256HexOfString('hello'));
    });
  });
}
