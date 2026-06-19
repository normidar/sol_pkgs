import 'dart:typed_data';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  final key = EthPrivateKey.fromHex(
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );
  final recipient = EthAddress.fromHex(
    '0x00000000000000000000000000000000000000d0',
  );

  group('EthereumTransaction (EIP-1559)', () {
    EthereumTransaction buildTx() => EthereumTransaction(
      chainId: BigInt.from(31337),
      nonce: BigInt.zero,
      gasLimit: BigInt.from(21000),
      to: recipient,
      value: BigInt.from(1000000000000000000),
      data: Uint8List(0),
      maxPriorityFeePerGas: BigInt.from(1000000000),
      maxFeePerGas: BigInt.from(2000000000),
    );

    test('signing hash is stable for identical fields', () {
      expect(buildTx().signingHash(), buildTx().signingHash());
    });

    test('signed bytes start with the 0x02 type prefix', () {
      final signed = buildTx().sign(key);
      expect(signed[0], 0x02);
    });

    test('the signature recovers the signer address', () {
      final tx = buildTx();
      final hash = tx.signingHash();
      final sig = key.sign(hash);
      expect(recoverEthAddress(sig, hash), key.address);
    });

    test('decoded payload has 12 RLP fields (9 unsigned + v, r, s)', () {
      final signed = buildTx().sign(key);
      final decoded = rlpDecode(signed.sublist(1)) as RlpList;
      expect(decoded.items, hasLength(12));
    });

    test(
      'contract-creation transaction (to == null) encodes an empty `to`',
      () {
        final tx = EthereumTransaction(
          chainId: BigInt.from(31337),
          nonce: BigInt.zero,
          gasLimit: BigInt.from(100000),
          data: Uint8List.fromList([0x60, 0x80, 0x60, 0x40]),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          maxFeePerGas: BigInt.from(2000000000),
        );
        final signed = tx.sign(key);
        final decoded = rlpDecode(signed.sublist(1)) as RlpList;
        // to is field index 5 in the EIP-1559 payload.
        expect((decoded.items[5] as RlpBytes).data, isEmpty);
      },
    );

    test('different nonces produce different signing hashes', () {
      final tx0 = buildTx();
      final tx1 = EthereumTransaction(
        chainId: tx0.chainId,
        nonce: BigInt.one,
        gasLimit: tx0.gasLimit,
        to: tx0.to,
        value: tx0.value,
        data: tx0.data,
        maxPriorityFeePerGas: tx0.maxPriorityFeePerGas,
        maxFeePerGas: tx0.maxFeePerGas,
      );
      expect(tx0.signingHash(), isNot(tx1.signingHash()));
    });
  });

  group('EthereumTransaction (legacy / EIP-155)', () {
    EthereumTransaction buildLegacyTx() => EthereumTransaction(
      chainId: BigInt.from(31337),
      nonce: BigInt.from(5),
      gasLimit: BigInt.from(21000),
      to: recipient,
      value: BigInt.from(42),
      data: Uint8List(0),
      type: TransactionType.legacy,
      gasPrice: BigInt.from(20000000000),
    );

    test('signed legacy tx decodes to exactly 9 RLP fields', () {
      final signed = buildLegacyTx().sign(key);
      final decoded = rlpDecode(signed) as RlpList;
      expect(decoded.items, hasLength(9));
    });

    test('v follows EIP-155: recoveryId + chainId * 2 + 35', () {
      // Derive the recoveryId from the *same* signature that ends up in
      // `signed` (not a second, independently-generated one): signing is
      // randomised (no RFC 6979), so two separate `sign()` calls on the same
      // hash can legitimately pick different recoveryIds and made this test
      // flaky when it called `key.sign(hash)` a second time for comparison.
      final tx = buildLegacyTx();
      final hash = tx.signingHash();
      final signed = tx.sign(key);

      final decoded = rlpDecode(signed) as RlpList;
      final v = bytesToBigInt((decoded.items[6] as RlpBytes).data);
      final r = bytesToBigInt((decoded.items[7] as RlpBytes).data);
      final s = bytesToBigInt((decoded.items[8] as RlpBytes).data);
      final recoveryId = (v - tx.chainId * BigInt.two - BigInt.from(35))
          .toInt();

      expect(recoveryId, anyOf(0, 1));
      expect(
        recoverEthAddress(EcdsaSignature(r, s, recoveryId), hash),
        key.address,
      );
    });

    test('the signature recovers the signer address', () {
      final tx = buildLegacyTx();
      final hash = tx.signingHash();
      final sig = key.sign(hash);
      expect(recoverEthAddress(sig, hash), key.address);
    });

    test('legacy and EIP-1559 signing hashes for similar fields differ', () {
      final legacy = buildLegacyTx();
      final eip1559 = EthereumTransaction(
        chainId: legacy.chainId,
        nonce: legacy.nonce,
        gasLimit: legacy.gasLimit,
        to: legacy.to,
        value: legacy.value,
        data: legacy.data,
        maxPriorityFeePerGas: BigInt.from(1000000000),
        maxFeePerGas: BigInt.from(2000000000),
      );
      expect(legacy.signingHash(), isNot(eip1559.signingHash()));
    });
  });
}
