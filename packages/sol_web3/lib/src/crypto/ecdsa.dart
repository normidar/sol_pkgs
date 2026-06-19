/// ECDSA over secp256k1, in the `(r, s, recoveryId)` form Ethereum uses for
/// transaction and message signatures.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';

import '../codec.dart';
import '../eth_address.dart';
import 'secp256k1.dart';

/// An ECDSA signature in Ethereum's `(r, s, recoveryId)` form.
///
/// [recoveryId] is the `y`-parity bit (0 or 1) of the nonce point needed to
/// recover the signer's public key from `(r, s)` alone. Bit 1 is set in the
/// (astronomically rare, ~1-in-2^128) case where that point's `x`-coordinate
/// was `>= secp256k1N`.
class EcdsaSignature {
  const EcdsaSignature(this.r, this.s, this.recoveryId);

  final BigInt r;
  final BigInt s;
  final int recoveryId;

  @override
  String toString() =>
      'EcdsaSignature(r: 0x${r.toRadixString(16)}, s: 0x${s.toRadixString(16)}, '
      'recoveryId: $recoveryId)';
}

/// Signs [messageHash] (typically a 32-byte `keccak256` digest) with
/// [privateKey] over secp256k1.
///
/// The nonce `k` is drawn fresh from [random] (a CSPRNG by default) on every
/// call rather than derived deterministically (RFC 6979); a fresh random `k`
/// is sufficient to avoid the nonce-reuse key-recovery attacks that have
/// broken real wallets, and avoids needing an HMAC/SHA-256 implementation
/// purely for nonce derivation. The result is normalised to low-`s` form, as
/// Ethereum requires (EIP-2).
EcdsaSignature signEcdsa(
  BigInt privateKey,
  Uint8List messageHash, [
  Random? random,
]) {
  final rnd = random ?? Random.secure();
  final z = bytesToBigInt(messageHash);

  while (true) {
    final k = randomScalar(rnd);
    final point = ECPoint.generator * k;
    if (point.isInfinity) continue;

    final r = point.x % secp256k1N;
    if (r == BigInt.zero) continue;

    final kInv = k.modInverse(secp256k1N);
    var s = (kInv * (z + r * privateKey)) % secp256k1N;
    if (s == BigInt.zero) continue;

    var recoveryId = (point.x >= secp256k1N ? 2 : 0) | (point.y.isOdd ? 1 : 0);
    if (BigInt.two * s > secp256k1N) {
      s = secp256k1N - s;
      recoveryId ^= 1;
    }
    return EcdsaSignature(r, s, recoveryId);
  }
}

/// Recovers the public key (as an [ECPoint]) that produced [sig] over
/// [messageHash], or `null` if [sig] is malformed (not produced by a real
/// signing operation over this curve).
ECPoint? recoverPublicKey(EcdsaSignature sig, Uint8List messageHash) {
  var x = sig.r;
  if (sig.recoveryId >= 2) x += secp256k1N;
  if (x >= secp256k1P) return null;

  final ySquared =
      (x.modPow(BigInt.from(3), secp256k1P) + BigInt.from(7)) % secp256k1P;
  // secp256k1's p ≡ 3 (mod 4), so a square root of a quadratic residue `a`
  // is `a^((p+1)/4) mod p` directly (no Tonelli–Shanks needed).
  var y = ySquared.modPow(
    (secp256k1P + BigInt.one) ~/ BigInt.from(4),
    secp256k1P,
  );
  if (y.isOdd != sig.recoveryId.isOdd) {
    y = secp256k1P - y;
  }
  if ((y * y) % secp256k1P != ySquared) return null;

  final pointR = ECPoint(x, y);
  final z = bytesToBigInt(messageHash);
  final negZ = (secp256k1N - (z % secp256k1N)) % secp256k1N;
  // Q = r⁻¹ · (s·R - z·G)
  final sum = (pointR * sig.s) + (ECPoint.generator * negZ);
  return sum * sig.r.modInverse(secp256k1N);
}

/// Recovers the signer's [EthAddress] for [sig] over [messageHash], or
/// `null` if [sig] is malformed.
EthAddress? recoverEthAddress(EcdsaSignature sig, Uint8List messageHash) {
  final point = recoverPublicKey(sig, messageHash);
  if (point == null) return null;
  final pubKeyBytes = Uint8List.fromList([
    ...bigIntToBytes(point.x, 32),
    ...bigIntToBytes(point.y, 32),
  ]);
  return EthAddress(Uint8List.fromList(keccak256(pubKeyBytes).sublist(12)));
}
