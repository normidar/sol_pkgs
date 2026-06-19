/// Ethereum transactions: legacy (type 0, EIP-155) and EIP-1559 (type 2),
/// with RLP-based signing-hash construction and signed-encoding per spec.
library;

import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';

import 'crypto/ecdsa.dart';
import 'crypto/eth_private_key.dart';
import 'eth_address.dart';
import 'rlp.dart';

/// Which wire format / fee model a transaction uses.
enum TransactionType {
  /// Pre-EIP-1559 transaction with a single `gasPrice`, replay-protected by
  /// folding `chainId` into `v` (EIP-155).
  legacy,

  /// EIP-1559 dynamic-fee transaction (`0x02` type byte), with separate
  /// `maxPriorityFeePerGas` / `maxFeePerGas` and an explicit access list.
  eip1559,
}

/// An unsigned (or signed) Ethereum transaction.
///
/// Construct with the fields relevant to [type]; the other type's fields are
/// simply ignored when encoding. [to] is `null` for a contract-creation
/// transaction.
class EthereumTransaction {
  EthereumTransaction({
    required this.chainId,
    required this.nonce,
    required this.gasLimit,
    required this.data,
    this.to,
    BigInt? value,
    this.type = TransactionType.eip1559,
    BigInt? gasPrice,
    BigInt? maxPriorityFeePerGas,
    BigInt? maxFeePerGas,
  }) : value = value ?? BigInt.zero,
       gasPrice = gasPrice ?? BigInt.zero,
       maxPriorityFeePerGas = maxPriorityFeePerGas ?? BigInt.zero,
       maxFeePerGas = maxFeePerGas ?? BigInt.zero;

  final BigInt chainId;
  final BigInt nonce;
  final BigInt gasLimit;
  final EthAddress? to;
  final BigInt value;

  /// Contract-creation init code, or call data for a message call.
  final Uint8List data;
  final TransactionType type;

  /// Used only when [type] is [TransactionType.legacy].
  final BigInt gasPrice;

  /// Used only when [type] is [TransactionType.eip1559].
  final BigInt maxPriorityFeePerGas;

  /// Used only when [type] is [TransactionType.eip1559].
  final BigInt maxFeePerGas;

  RlpItem get _toRlp => RlpBytes(to == null ? Uint8List(0) : to!.bytes);

  Uint8List _legacyUnsignedRlp() => rlpEncode(
    RlpList([
      rlpUint(nonce),
      rlpUint(gasPrice),
      rlpUint(gasLimit),
      _toRlp,
      rlpUint(value),
      RlpBytes(data),
      rlpUint(chainId),
      RlpBytes(Uint8List(0)),
      RlpBytes(Uint8List(0)),
    ]),
  );

  Uint8List _eip1559UnsignedPayload() => rlpEncode(
    RlpList([
      rlpUint(chainId),
      rlpUint(nonce),
      rlpUint(maxPriorityFeePerGas),
      rlpUint(maxFeePerGas),
      rlpUint(gasLimit),
      _toRlp,
      rlpUint(value),
      RlpBytes(data),
      const RlpList([]),
    ]),
  );

  Uint8List _typedPayload(Uint8List rlpPayload) =>
      Uint8List.fromList([0x02, ...rlpPayload]);

  /// The 32-byte digest that gets signed: `keccak256` of the unsigned RLP
  /// encoding (legacy), or of the `0x02`-prefixed unsigned RLP payload
  /// (EIP-1559, per EIP-2718's typed-transaction envelope).
  Uint8List signingHash() {
    switch (type) {
      case TransactionType.legacy:
        return keccak256(_legacyUnsignedRlp());
      case TransactionType.eip1559:
        return keccak256(_typedPayload(_eip1559UnsignedPayload()));
    }
  }

  /// Signs this transaction with [key] and returns the final RLP-encoded
  /// (and, for EIP-1559, type-prefixed) bytes ready for
  /// `eth_sendRawTransaction`.
  Uint8List sign(EthPrivateKey key) {
    final sig = key.sign(signingHash());
    return _encodeSigned(sig);
  }

  Uint8List _encodeSigned(EcdsaSignature sig) {
    switch (type) {
      case TransactionType.legacy:
        final v =
            BigInt.from(sig.recoveryId) +
            chainId * BigInt.two +
            BigInt.from(35);
        return rlpEncode(
          RlpList([
            rlpUint(nonce),
            rlpUint(gasPrice),
            rlpUint(gasLimit),
            _toRlp,
            rlpUint(value),
            RlpBytes(data),
            rlpUint(v),
            rlpUint(sig.r),
            rlpUint(sig.s),
          ]),
        );
      case TransactionType.eip1559:
        final payload = rlpEncode(
          RlpList([
            rlpUint(chainId),
            rlpUint(nonce),
            rlpUint(maxPriorityFeePerGas),
            rlpUint(maxFeePerGas),
            rlpUint(gasLimit),
            _toRlp,
            rlpUint(value),
            RlpBytes(data),
            const RlpList([]),
            rlpUint(BigInt.from(sig.recoveryId)),
            rlpUint(sig.r),
            rlpUint(sig.s),
          ]),
        );
        return _typedPayload(payload);
    }
  }
}
