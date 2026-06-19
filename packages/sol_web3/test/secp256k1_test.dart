import 'dart:math';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('ECPoint', () {
    test('generator has the standard secp256k1 Gx/Gy', () {
      final g = ECPoint.generator;
      expect(
        g.x.toRadixString(16),
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
      );
      expect(
        g.y.toRadixString(16),
        '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
      );
    });

    test('G * 1 == G', () {
      expect(ECPoint.generator * BigInt.one, ECPoint.generator);
    });

    test('G * 0 is the point at infinity', () {
      expect((ECPoint.generator * BigInt.zero).isInfinity, isTrue);
    });

    test('G * n (curve order) is the point at infinity', () {
      expect((ECPoint.generator * secp256k1N).isInfinity, isTrue);
    });

    test('doubling matches repeated addition', () {
      final g = ECPoint.generator;
      expect(g + g, g * BigInt.two);
      expect(g + g + g, g * BigInt.from(3));
    });

    test('addition is commutative', () {
      final a = ECPoint.generator * BigInt.from(7);
      final b = ECPoint.generator * BigInt.from(11);
      expect(a + b, b + a);
    });

    test('point plus its negation is infinity', () {
      final p = ECPoint.generator * BigInt.from(42);
      expect((p + (-p)).isInfinity, isTrue);
    });

    test('scalar multiplication distributes over addition of scalars', () {
      final a = BigInt.from(123);
      final b = BigInt.from(456);
      final lhs = ECPoint.generator * (a + b);
      final rhs = (ECPoint.generator * a) + (ECPoint.generator * b);
      expect(lhs, rhs);
    });

    test('infinity is the additive identity', () {
      final p = ECPoint.generator * BigInt.from(99);
      final inf = ECPoint.infinity();
      expect(p + inf, p);
      expect(inf + p, p);
    });
  });

  group('randomScalar', () {
    test('produces values in [1, n - 1]', () {
      final rnd = Random.secure();
      for (var i = 0; i < 50; i++) {
        final k = randomScalar(rnd);
        expect(k > BigInt.zero, isTrue);
        expect(k < secp256k1N, isTrue);
      }
    });
  });
}
