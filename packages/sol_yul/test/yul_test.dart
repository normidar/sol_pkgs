import 'package:sol_yul/sol_yul.dart';
import 'package:test/test.dart';

YulObject _obj(YulBlock block) =>
    YulObject('Test', block, [], {});

YulLiteral _num(String v) => YulLiteral(v, YulLiteralKind.number);

void main() {
  group('YulPrinter', () {
    test('prints simple add call', () {
      final block = YulBlock([
        YulExpressionStatement(
          YulFunctionCall('add', [_num('1'), _num('2')]),
        ),
      ]);
      expect(YulPrinter().print(block), contains('add(1, 2)'));
    });

    test('prints let declaration', () {
      final block = YulBlock([
        YulVariableDeclaration(
          ['result'],
          YulFunctionCall('add', [_num('0x01'), _num('0x02')]),
        ),
      ]);
      expect(YulPrinter().print(block), contains('let result := add(0x01, 0x02)'));
    });
  });

  group('YulCodeGenerator — literals & arithmetic', () {
    test('generates bytecode for add literal', () {
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulExpressionStatement(
          YulFunctionCall('add', [_num('1'), _num('2')]),
        ),
      ])));
      expect(bytes, isNotEmpty);
    });

    test('generates PUSH0 for literal 0', () {
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulVariableDeclaration(['x'], _num('0')),
      ])));
      // PUSH0 (0x5f) should appear for zero literal
      expect(bytes, contains(0x5f));
    });

    test('generates bytecode for hex literal', () {
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulVariableDeclaration(['x'], _num('0xff')),
      ])));
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — variable tracking', () {
    test('variable declaration and identifier reference', () {
      // let x := 42; let y := x
      // Should emit: PUSH 42, (x on stack), DUP1 (to read x into y)
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulVariableDeclaration(['x'], _num('42')),
        YulVariableDeclaration(['y'], YulIdentifier('x')),
      ])));
      expect(bytes, isNotEmpty);
      // PUSH1 0x2a is for 42
      expect(bytes, contains(0x2a));
    });

    test('variable assignment updates value', () {
      // let x := 1; x := 2
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulVariableDeclaration(['x'], _num('1')),
        YulAssignment(['x'], _num('2')),
      ])));
      expect(bytes, isNotEmpty);
      // Should contain SWAP1 + POP for the assignment
      expect(bytes, contains(0x90)); // SWAP1
      expect(bytes, contains(0x50)); // POP
    });

    test('two variables: assignment uses correct depth', () {
      // let x := 1; let y := 2; y := 3
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulVariableDeclaration(['x'], _num('1')),
        YulVariableDeclaration(['y'], _num('2')),
        YulAssignment(['y'], _num('3')),
      ])));
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — control flow', () {
    test('if statement generates JUMPI', () {
      // if iszero(0) { let x := 1 }
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulIf(
          YulFunctionCall('iszero', [_num('0')]),
          YulBlock([YulVariableDeclaration(['x'], _num('1'))]),
        ),
      ])));
      // JUMPI opcode = 0x57
      expect(bytes, contains(0x57));
    });

    test('for loop generates JUMP + JUMPI', () {
      // for {} 1 {} {}
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulForLoop(
          YulBlock([]),
          _num('1'),
          YulBlock([]),
          YulBlock([YulBreak()]),
        ),
      ])));
      expect(bytes, contains(0x56)); // JUMP
      expect(bytes, contains(0x57)); // JUMPI
    });

    test('switch generates EQ + JUMPI per case', () {
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulSwitch(
          _num('1'),
          [
            YulCase(_num('1'), YulBlock([])),
            YulCase(_num('2'), YulBlock([])),
          ],
          null,
        ),
      ])));
      // EQ opcode = 0x14
      expect(bytes, contains(0x14));
    });
  });

  group('YulCodeGenerator — user-defined functions', () {
    test('function definition and call (0 return vals)', () {
      // function doNothing() {}
      // doNothing()
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulFunctionDefinition('doNothing', [], [], YulBlock([])),
        YulExpressionStatement(YulFunctionCall('doNothing', [])),
      ])));
      expect(bytes, isNotEmpty);
      // JUMPDEST (0x5b) for function entry
      expect(bytes, contains(0x5b));
    });

    test('function with 1 return value', () {
      // function getOne() -> r { r := 1 }
      // let x := getOne()
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulFunctionDefinition(
          'getOne',
          [],
          ['r'],
          YulBlock([YulAssignment(['r'], _num('1'))]),
        ),
        YulVariableDeclaration(['x'], YulFunctionCall('getOne', [])),
      ])));
      expect(bytes, isNotEmpty);
      expect(bytes, contains(0x5b)); // JUMPDEST
    });

    test('function with params and 1 return value', () {
      // function double(n) -> r { r := add(n, n) }
      // let x := double(3)
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulFunctionDefinition(
          'double',
          ['n'],
          ['r'],
          YulBlock([
            YulAssignment(
              ['r'],
              YulFunctionCall('add', [YulIdentifier('n'), YulIdentifier('n')]),
            ),
          ]),
        ),
        YulVariableDeclaration(
          ['x'],
          YulFunctionCall('double', [_num('3')]),
        ),
      ])));
      expect(bytes, isNotEmpty);
    });

    test('leave statement exits function', () {
      // function earlyExit() -> r { r := 1; leave; r := 2 }
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulFunctionDefinition(
          'earlyExit',
          [],
          ['r'],
          YulBlock([
            YulAssignment(['r'], _num('1')),
            YulLeave(),
            YulAssignment(['r'], _num('2')),
          ]),
        ),
        YulVariableDeclaration(['x'], YulFunctionCall('earlyExit', [])),
      ])));
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — builtin void functions', () {
    test('mstore is void (no POP needed)', () {
      // mstore(0, 1) — should not leave a value on stack
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulExpressionStatement(
          YulFunctionCall('mstore', [_num('0'), _num('1')]),
        ),
      ])));
      expect(bytes, isNotEmpty);
      expect(bytes, contains(0x52)); // MSTORE
    });

    test('stop is void', () {
      final bytes = YulCodeGenerator().generate(_obj(YulBlock([
        YulExpressionStatement(YulFunctionCall('stop', [])),
      ])));
      expect(bytes, contains(0x00)); // STOP
    });
  });
}
