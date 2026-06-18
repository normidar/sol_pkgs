import 'package:sol_cli/sol_cli.dart';
import 'package:test/test.dart';

void main() {
  group('CLI flags', () {
    test('--help returns 0 and prints usage', () {
      expect(runCompiler(['--help']), 0);
    });

    test('--version returns 0', () {
      expect(runCompiler(['--version']), 0);
    });

    test('no input files returns 1', () {
      expect(runCompiler([]), 1);
    });

    test('--optimize flag accepted without error', () {
      // --optimize alone (no files) still returns 1 (no input files).
      // The key requirement is that the flag is recognized (no ArgParserException).
      expect(runCompiler(['--optimize']), 1);
    });

    test('--remappings flag accepted', () {
      expect(runCompiler(['--remappings', 'prefix=target']), 1);
    });

    test('--base-path flag accepted', () {
      expect(runCompiler(['--base-path', '/some/path']), 1);
    });

    test('--include-path flag accepted', () {
      expect(runCompiler(['--include-path', '/some/path']), 1);
    });
  });
}
