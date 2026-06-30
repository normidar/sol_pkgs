/// Pure-Dart secp256k1 elliptic curve arithmetic — the curve behind
/// Ethereum (and Bitcoin) signatures and key derivation.
///
/// Affine short-Weierstrass point arithmetic (`y^2 = x^3 + 7 mod p`) built
/// entirely on [BigInt] and its built-in [BigInt.modInverse]. This is not a
/// constant-time implementation: timing side-channels are not defended
/// against, consistent with the rest of sol_pkgs being a from-scratch
/// reference implementation rather than an audited cryptography library.
library;

import 'dart:math';
import 'dart:typed_data';

import '../codec.dart';

/// The secp256k1 field prime (`y^2 = x^3 + 7` is defined over `F_p`).
///
/// Expressed via its closed form (`p = 2^256 - 2^32 - 977`) rather than a
/// hand-transcribed hex literal: a single mistyped digit in a 64-digit
/// literal is invisible on read-through but turns every curve operation
/// into nonsense (and, since the result is no longer guaranteed prime,
/// occasionally non-invertible — see the `Not coprime` exceptions this form
/// was introduced to fix).
final BigInt secp256k1P =
    BigInt.two.pow(256) - BigInt.two.pow(32) - BigInt.from(977);

/// The order of the secp256k1 base point (the curve's cofactor is 1, so this
/// is also the order of every other non-identity point on the curve).
final BigInt secp256k1N = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);

final BigInt _gx = BigInt.parse(
  '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
  radix: 16,
);

final BigInt _gy = BigInt.parse(
  '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
  radix: 16,
);

/// A point on the secp256k1 curve in affine coordinates, or the point at
/// infinity (the additive identity) when [isInfinity] is true.
///
/// Instances are never compile-time constants ([BigInt] values can't be —
/// see the rejected `const` attempt this comment replaces), so neither
/// constructor is `const`.
class ECPoint {
  ECPoint(this.x, this.y) : isInfinity = false;

  ECPoint.infinity() : x = BigInt.zero, y = BigInt.zero, isInfinity = true;

  final BigInt x;
  final BigInt y;
  final bool isInfinity;

  /// The curve's base point `G`.
  static final ECPoint generator = ECPoint(_gx, _gy);

  ECPoint operator +(ECPoint other) {
    if (isInfinity) return other;
    if (other.isInfinity) return this;

    if (x == other.x) {
      if ((y + other.y) % secp256k1P == BigInt.zero) {
        return ECPoint.infinity();
      }
      // Same point: use the doubling tangent-line formula (a = 0).
      final lambda =
          (BigInt.from(3) * x * x * (BigInt.two * y).modInverse(secp256k1P)) %
          secp256k1P;
      final rx = (lambda * lambda - BigInt.two * x) % secp256k1P;
      final ry = (lambda * (x - rx) - y) % secp256k1P;
      return ECPoint(rx, ry);
    }

    final lambda =
        ((other.y - y) * (other.x - x).modInverse(secp256k1P)) % secp256k1P;
    final rx = (lambda * lambda - x - other.x) % secp256k1P;
    final ry = (lambda * (x - rx) - y) % secp256k1P;
    return ECPoint(rx, ry);
  }

  ECPoint operator -() =>
      isInfinity ? this : ECPoint(x, (secp256k1P - y) % secp256k1P);

  /// Scalar multiplication via the Montgomery ladder. [k] is reduced mod the
  /// group order first.
  ///
  /// Unlike double-and-add, the ladder performs one double and one add per
  /// bit regardless of the bit value, eliminating the data-dependent branching
  /// that makes double-and-add vulnerable to simple timing analysis.
  ///
  /// Note: [BigInt] arithmetic in Dart VM is not guaranteed constant-time at
  /// the machine-word level (cache/branch timing from the runtime's own bignum
  /// routines may still exist). This implementation raises the bar
  /// significantly over double-and-add but is not a substitute for a
  /// hardware-level constant-time library.
  ECPoint operator *(BigInt k) {
    final n = k % secp256k1N;
    if (n == BigInt.zero) return ECPoint.infinity();

    // Montgomery ladder: invariant R1 - R0 == this throughout.
    var r0 = ECPoint.infinity();
    var r1 = this;
    for (var i = n.bitLength - 1; i >= 0; i--) {
      if (!((n >> i).isOdd)) {
        r1 = r0 + r1;
        r0 = r0 + r0;
      } else {
        r0 = r0 + r1;
        r1 = r1 + r1;
      }
    }
    return r0;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ECPoint) return false;
    if (isInfinity || other.isInfinity) return isInfinity == other.isInfinity;
    return x == other.x && y == other.y;
  }

  @override
  int get hashCode => isInfinity ? 0 : Object.hash(x, y);

  @override
  String toString() => isInfinity
      ? 'ECPoint.infinity'
      : 'ECPoint(0x${x.toRadixString(16)}, 0x${y.toRadixString(16)})';
}

/// A uniformly random scalar in `[1, secp256k1N - 1]`, suitable as a private
/// key or an ECDSA signing nonce.
BigInt randomScalar(Random random) {
  while (true) {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final candidate = bytesToBigInt(bytes);
    if (candidate > BigInt.zero && candidate < secp256k1N) return candidate;
  }
}
