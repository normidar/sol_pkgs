import 'dart:typed_data';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('EthPrivateKey', () {
    // The well-known Hardhat/Anvil default account #0. Verified against an
    // independently-derived (Node.js crypto.createECDH) public key, so this
    // is a true external test vector, not a self-referential check.
    const hardhatPrivateKeyHex =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
    const hardhatAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

    test('derives the published Hardhat account #0 address', () {
      final key = EthPrivateKey.fromHex(hardhatPrivateKeyHex);
      expect(key.address.toChecksumHex(), hardhatAddress);
    });

    test('toHex round-trips through fromHex', () {
      final key = EthPrivateKey.fromHex(hardhatPrivateKeyHex);
      expect(key.toHex(), hardhatPrivateKeyHex);
    });

    test('publicKeyBytes is 64 bytes (X || Y, no 0x04 prefix)', () {
      final key = EthPrivateKey.fromHex(hardhatPrivateKeyHex);
      expect(key.publicKeyBytes, hasLength(64));
    });

    test('rejects zero as a private key', () {
      expect(() => EthPrivateKey(BigInt.zero), throwsArgumentError);
    });

    test('rejects values >= the curve order', () {
      expect(() => EthPrivateKey(secp256k1N), throwsArgumentError);
    });

    test('createRandom produces a usable, in-range key', () {
      final key = EthPrivateKey.createRandom();
      expect(key.privateKey > BigInt.zero, isTrue);
      expect(key.privateKey < secp256k1N, isTrue);
      // sign/recover round trip as a sanity check that the key is well-formed.
      final hash = Uint8List(32)..[0] = 1;
      final sig = key.sign(hash);
      expect(recoverEthAddress(sig, hash), key.address);
    });

    test('two random keys are different', () {
      final a = EthPrivateKey.createRandom();
      final b = EthPrivateKey.createRandom();
      expect(a.privateKey, isNot(b.privateKey));
    });
  });
}
