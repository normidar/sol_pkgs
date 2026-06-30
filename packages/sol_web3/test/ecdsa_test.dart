import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';
import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('signEcdsa / recoverPublicKey', () {
    test('a fresh signature verifies and recovers the right public key', () {
      final privateKey = BigInt.from(0xC0FFEE);
      final publicKey = ECPoint.generator * privateKey;
      final hash = keccak256OfString('hello world');

      final sig = signEcdsa(privateKey, hash);
      expect(
        sig.s * BigInt.two <= secp256k1N,
        isTrue,
        reason: 'must be low-s (EIP-2)',
      );

      final recovered = recoverPublicKey(sig, hash);
      expect(recovered, publicKey);
    });

    test(
      'recoverEthAddress matches the address derived from the public key',
      () {
        final key = EthPrivateKey.fromHex(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );
        final hash = keccak256OfString('sol_web3');
        final sig = key.sign(hash);

        final recoveredAddress = recoverEthAddress(sig, hash);
        expect(recoveredAddress, key.address);
      },
    );

    test('different messages produce different recoverable signatures', () {
      final key = EthPrivateKey.fromHex(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );
      final hashA = keccak256OfString('message A');
      final hashB = keccak256OfString('message B');
      final sigA = key.sign(hashA);

      // Recovering sigA against the wrong message must not yield the signer.
      final recovered = recoverEthAddress(sigA, hashB);
      expect(recovered, isNot(key.address));
    });

    test('RFC 6979: same key+message always produces the same signature', () {
      final privateKey = BigInt.from(424242);
      final hash = keccak256OfString('same message every time');
      final sig1 = signEcdsa(privateKey, hash);
      final sig2 = signEcdsa(privateKey, hash);
      expect(sig1.r, sig2.r, reason: 'RFC 6979 nonce must be deterministic');
      expect(sig1.s, sig2.s);
    });

    test('RFC 6979: different messages produce different nonces', () {
      final privateKey = BigInt.from(424242);
      final sig1 = signEcdsa(privateKey, keccak256OfString('message one'));
      final sig2 = signEcdsa(privateKey, keccak256OfString('message two'));
      expect(sig1.r, isNot(sig2.r));
    });

    test('recoverPublicKey returns null for a clearly malformed signature', () {
      final hash = Uint8List(32);
      final bogus = EcdsaSignature(secp256k1P + BigInt.one, BigInt.one, 3);
      expect(recoverPublicKey(bogus, hash), isNull);
    });
  });
}
