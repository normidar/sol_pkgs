import 'package:sol_yul/sol_yul.dart';
import 'package:test/test.dart';

void main() {
  group('YulPrinter', () {
    test('prints simple add call', () {
      final block = YulBlock([
        YulExpressionStatement(
          YulFunctionCall('add', [
            YulLiteral('1', YulLiteralKind.number),
            YulLiteral('2', YulLiteralKind.number),
          ]),
        ),
      ]);
      final text = YulPrinter().print(block);
      expect(text, contains('add(1, 2)'));
    });

    test('prints let declaration', () {
      final block = YulBlock([
        YulVariableDeclaration(
          ['result'],
          YulFunctionCall('add', [
            YulLiteral('0x01', YulLiteralKind.number),
            YulLiteral('0x02', YulLiteralKind.number),
          ]),
        ),
      ]);
      final text = YulPrinter().print(block);
      expect(text, contains('let result := add(0x01, 0x02)'));
    });
  });

  group('YulCodeGenerator', () {
    test('generates bytecode for add literal', () {
      final obj = YulObject(
        'Test',
        YulBlock([
          YulExpressionStatement(
            YulFunctionCall('add', [
              YulLiteral('1', YulLiteralKind.number),
              YulLiteral('2', YulLiteralKind.number),
            ]),
          ),
        ]),
        [],
        {},
      );
      final bytes = YulCodeGenerator().generate(obj);
      expect(bytes, isNotEmpty);
    });
  });
}
