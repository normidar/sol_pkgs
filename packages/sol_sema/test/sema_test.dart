import 'package:sol_sema/sol_sema.dart';
import 'package:test/test.dart';

void main() {
  group('C3 linearisation', () {
    test('single contract no bases', () {
      final mro = c3Linearise('A', (_) => []);
      expect(mro, ['A']);
    });

    test('simple chain A → B → C', () {
      final bases = {'A': ['B'], 'B': ['C'], 'C': <String>[]};
      final mro = c3Linearise('A', (n) => bases[n]!);
      expect(mro, ['A', 'B', 'C']);
    });

    test('diamond inheritance', () {
      // D → B, C; B → A; C → A
      final bases = {
        'D': ['B', 'C'],
        'B': ['A'],
        'C': ['A'],
        'A': <String>[],
      };
      final mro = c3Linearise('D', (n) => bases[n]!);
      expect(mro, ['D', 'B', 'C', 'A']);
    });

    test('cycle throws', () {
      final bases = {'A': ['B'], 'B': ['A']};
      expect(
        () => c3Linearise('A', (n) => bases[n]!),
        throwsA(isA<C3LinearisationError>()),
      );
    });
  });
}
