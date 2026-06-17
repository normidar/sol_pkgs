import 'package:sol_support/sol_support.dart';
import 'package:test/test.dart';

void main() {
  group('SourceMap', () {
    test('single-line offset → line 1 col n', () {
      final map = SourceMap('hello world');
      expect(map.locationOf(0), equals(LineColumn(1, 1)));
      expect(map.locationOf(6).toString(), equals('1:7'));
    });

    test('multi-line offset', () {
      final map = SourceMap('abc\ndef\nghi');
      expect(map.locationOf(4).toString(), equals('2:1'));
      expect(map.locationOf(8).toString(), equals('3:1'));
    });
  });

  group('SourceLocation.combine', () {
    test('merges two spans in the same file', () {
      const a = SourceLocation(sourceIndex: 0, offset: 2, length: 3);
      const b = SourceLocation(sourceIndex: 0, offset: 7, length: 2);
      final c = a.combine(b);
      expect(c.offset, 2);
      expect(c.length, 7); // 2..9
    });
  });

  group('DiagnosticCollector', () {
    test('records warnings without throwing', () {
      final col = DiagnosticCollector();
      col.warning('unused variable');
      expect(col.diagnostics.length, 1);
      expect(col.hasErrors, isFalse);
    });

    test('records errors and sets hasErrors', () {
      final col = DiagnosticCollector();
      col.error('type mismatch');
      expect(col.hasErrors, isTrue);
    });

    test('fatalError throws FatalErrorException', () {
      final col = DiagnosticCollector();
      expect(() => col.fatalError('file not found'),
          throwsA(isA<FatalErrorException>()));
    });
  });

  group('ImportRemapper', () {
    test('applies prefix remapping', () {
      final r = ImportRemapper([
        ImportRemapping.parse('@openzeppelin/=lib/openzeppelin-contracts/'),
      ]);
      expect(
        r.resolve('@openzeppelin/contracts/token/ERC20.sol', 'src/Token.sol'),
        'lib/openzeppelin-contracts/contracts/token/ERC20.sol',
      );
    });

    test('context-specific remapping wins over global', () {
      final r = ImportRemapper([
        ImportRemapping.parse('foo/=lib/foo/'),
        ImportRemapping.parse('src/:foo/=lib/src_foo/'),
      ]);
      expect(r.resolve('foo/bar.sol', 'src/main.sol'), 'lib/src_foo/bar.sol');
      expect(r.resolve('foo/bar.sol', 'other/main.sol'), 'lib/foo/bar.sol');
    });
  });
}
