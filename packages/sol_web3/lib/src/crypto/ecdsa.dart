/// ECDSA over secp256k1, in the `(r, s, recoveryId)` form Ethereum uses for
/// transaction and message signatures.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

/// Derives a deterministic ECDSA nonce per RFC 6979 §3.2 using HMAC-SHA-256.
///
/// [privateKey] and [messageHash] are the same inputs passed to [signEcdsa].
/// The returned `k` is guaranteed to be in `[1, secp256k1N - 1]`.
BigInt _rfc6979Nonce(BigInt privateKey, Uint8List messageHash) {
  // int2octets(privkey) — private key as 32-byte big-endian.
  final x = bigIntToBytes(privateKey, 32);

  // bits2octets(h1) — reduce message hash mod n, then encode as 32 bytes.
  final h1Int = bytesToBigInt(messageHash) % secp256k1N;
  final h1 = bigIntToBytes(h1Int, 32);

  Uint8List hmac(Uint8List key, List<int> data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

  // Steps 3–7: initialise the HMAC_DRBG state.
  var v = Uint8List(32)..fillRange(0, 32, 0x01);
  var k = Uint8List(32); // all-zero

  k = hmac(k, [...v, 0x00, ...x, ...h1]);
  v = hmac(k, v);
  k = hmac(k, [...v, 0x01, ...x, ...h1]);
  v = hmac(k, v);

  // Step 8: generate candidate nonces until one falls in [1, n-1].
  while (true) {
    v = hmac(k, v); // T = V (qlen == hlen == 256 bits, so one block suffices)
    final candidate = bytesToBigInt(v);
    if (candidate > BigInt.zero && candidate < secp256k1N) return candidate;

    // Rejected: reseed and retry.
    k = hmac(k, [...v, 0x00]);
    v = hmac(k, v);
  }
}

/// Signs [messageHash] (typically a 32-byte `keccak256` digest) with
/// [privateKey] over secp256k1.
///
/// The nonce `k` is derived deterministically via RFC 6979 (HMAC-SHA-256).
/// Deterministic nonces guarantee that no two signatures ever share a `k`
/// value (the catastrophic failure mode of randomised ECDSA), and they are
/// fully reproducible without depending on RNG quality. The result is
/// normalised to low-`s` form as Ethereum requires (EIP-2).
EcdsaSignature signEcdsa(BigInt privateKey, Uint8List messageHash) {
  final z = bytesToBigInt(messageHash);
  var k = _rfc6979Nonce(privateKey, messageHash);

  // RFC 6979 §3.2 step 8 loop: extremely unlikely to iterate more than once
  // for secp256k1 (would require k*G.x == 0 mod n, probability ~2^-128).
  while (true) {
    final point = ECPoint.generator * k;
    if (point.isInfinity) {
      k = _rfc6979Nonce(privateKey, Uint8List.fromList([...messageHash, 0]));
      continue;
    }

    final r = point.x % secp256k1N;
    if (r == BigInt.zero) {
      k = _rfc6979Nonce(privateKey, Uint8List.fromList([...messageHash, 1]));
      continue;
    }

    final kInv = k.modInverse(secp256k1N);
    var s = (kInv * (z + r * privateKey)) % secp256k1N;
    if (s == BigInt.zero) {
      k = _rfc6979Nonce(privateKey, Uint8List.fromList([...messageHash, 2]));
      continue;
    }

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
