/// An secp256k1 keypair with Ethereum's address derivation built in.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';

import '../codec.dart';
import '../eth_address.dart';
import 'ecdsa.dart';
import 'secp256k1.dart';

/// A private key (scalar) on secp256k1, together with the public key and
/// Ethereum address it derives.
class EthPrivateKey {
  EthPrivateKey(this.privateKey) {
    if (privateKey <= BigInt.zero || privateKey >= secp256k1N) {
      throw ArgumentError('private key out of range [1, secp256k1N - 1]');
    }
  }

  /// Parses a `0x`-prefixed or bare 64-hex-digit private key.
  factory EthPrivateKey.fromHex(String hex) =>
      EthPrivateKey(bigIntFromHex(hex));

  /// Generates a fresh private key using [random] (a CSPRNG by default).
  factory EthPrivateKey.createRandom([Random? random]) =>
      EthPrivateKey(randomScalar(random ?? Random.secure()));

  final BigInt privateKey;

  ECPoint get publicKeyPoint => ECPoint.generator * privateKey;

  /// The 64-byte uncompressed public key (`X || Y`, without the leading
  /// `0x04` SEC1 prefix).
  Uint8List get publicKeyBytes => Uint8List.fromList([
    ...bigIntToBytes(publicKeyPoint.x, 32),
    ...bigIntToBytes(publicKeyPoint.y, 32),
  ]);

  /// The Ethereum address derived from this key: the low 20 bytes of
  /// `keccak256(publicKeyBytes)`.
  EthAddress get address =>
      EthAddress(Uint8List.fromList(keccak256(publicKeyBytes).sublist(12)));

  /// Signs a 32-byte digest, e.g. an [EthereumTransaction]'s signing hash.
  EcdsaSignature sign(Uint8List messageHash32) =>
      signEcdsa(privateKey, messageHash32);

  /// Lowercase hex with a `0x` prefix.
  ///
  /// Handle with the same care as the raw key: anyone with this string can
  /// spend any funds the corresponding address holds.
  String toHex() => bytesToHex(bigIntToBytes(privateKey, 32), include0x: true);
}
