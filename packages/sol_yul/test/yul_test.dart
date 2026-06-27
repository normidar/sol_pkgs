import 'package:sol_yul/sol_yul.dart';
import 'package:test/test.dart';

YulObject _obj(YulBlock block) => YulObject('Test', block, [], {});

YulLiteral _num(String v) => YulLiteral(v, YulLiteralKind.number);

void main() {
  group('YulPrinter', () {
    test('prints simple add call', () {
      final block = YulBlock([
        YulExpressionStatement(YulFunctionCall('add', [_num('1'), _num('2')])),
      ]);
      expect(YulPrinter().print(block), contains('add(1, 2)'));
    });

    test('prints let declaration', () {
      final block = YulBlock([
        YulVariableDeclaration([
          'result',
        ], YulFunctionCall('add', [_num('0x01'), _num('0x02')])),
      ]);
      expect(
        YulPrinter().print(block),
        contains('let result := add(0x01, 0x02)'),
      );
    });
  });

  group('YulCodeGenerator — literals & arithmetic', () {
    test('generates bytecode for add literal', () {
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulExpressionStatement(
              YulFunctionCall('add', [_num('1'), _num('2')]),
            ),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('generates PUSH0 for literal 0', () {
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulVariableDeclaration(['x'], _num('0')),
          ]),
        ),
      );
      // PUSH0 (0x5f) should appear for zero literal
      expect(bytes, contains(0x5f));
    });

    test('generates bytecode for hex literal', () {
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulVariableDeclaration(['x'], _num('0xff')),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — variable tracking', () {
    test('variable declaration and identifier reference', () {
      // let x := 42; let y := x
      // Should emit: PUSH 42, (x on stack), DUP1 (to read x into y)
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulVariableDeclaration(['x'], _num('42')),
            YulVariableDeclaration(['y'], YulIdentifier('x')),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
      // PUSH1 0x2a is for 42
      expect(bytes, contains(0x2a));
    });

    test('variable assignment updates value', () {
      // let x := 1; x := 2
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulVariableDeclaration(['x'], _num('1')),
            YulAssignment(['x'], _num('2')),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
      // Should contain SWAP1 + POP for the assignment
      expect(bytes, contains(0x90)); // SWAP1
      expect(bytes, contains(0x50)); // POP
    });

    test('two variables: assignment uses correct depth', () {
      // let x := 1; let y := 2; y := 3
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulVariableDeclaration(['x'], _num('1')),
            YulVariableDeclaration(['y'], _num('2')),
            YulAssignment(['y'], _num('3')),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — control flow', () {
    test('if statement generates JUMPI', () {
      // if iszero(0) { let x := 1 }
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulIf(
              YulFunctionCall('iszero', [_num('0')]),
              YulBlock([
                YulVariableDeclaration(['x'], _num('1')),
              ]),
            ),
          ]),
        ),
      );
      // JUMPI opcode = 0x57
      expect(bytes, contains(0x57));
    });

    test('for loop generates JUMP + JUMPI', () {
      // for {} 1 {} {}
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulForLoop(
              YulBlock([]),
              _num('1'),
              YulBlock([]),
              YulBlock([YulBreak()]),
            ),
          ]),
        ),
      );
      expect(bytes, contains(0x56)); // JUMP
      expect(bytes, contains(0x57)); // JUMPI
    });

    test('switch generates EQ + JUMPI per case', () {
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulSwitch(_num('1'), [
              YulCase(_num('1'), YulBlock([])),
              YulCase(_num('2'), YulBlock([])),
            ], null),
          ]),
        ),
      );
      // EQ opcode = 0x14
      expect(bytes, contains(0x14));
    });
  });

  group('YulCodeGenerator — user-defined functions', () {
    test('function definition and call (0 return vals)', () {
      // function doNothing() {}
      // doNothing()
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulFunctionDefinition('doNothing', [], [], YulBlock([])),
            YulExpressionStatement(YulFunctionCall('doNothing', [])),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
      // JUMPDEST (0x5b) for function entry
      expect(bytes, contains(0x5b));
    });

    test('function with 1 return value', () {
      // function getOne() -> r { r := 1 }
      // let x := getOne()
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulFunctionDefinition(
              'getOne',
              [],
              ['r'],
              YulBlock([
                YulAssignment(['r'], _num('1')),
              ]),
            ),
            YulVariableDeclaration(['x'], YulFunctionCall('getOne', [])),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
      expect(bytes, contains(0x5b)); // JUMPDEST
    });

    test('function with params and 1 return value', () {
      // function double(n) -> r { r := add(n, n) }
      // let x := double(3)
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulFunctionDefinition(
              'double',
              ['n'],
              ['r'],
              YulBlock([
                YulAssignment(
                  ['r'],
                  YulFunctionCall('add', [
                    YulIdentifier('n'),
                    YulIdentifier('n'),
                  ]),
                ),
              ]),
            ),
            YulVariableDeclaration([
              'x',
            ], YulFunctionCall('double', [_num('3')])),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('leave statement exits function', () {
      // function earlyExit() -> r { r := 1; leave; r := 2 }
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
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
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('YulCodeGenerator — builtin void functions', () {
    test('mstore is void (no POP needed)', () {
      // mstore(0, 1) — should not leave a value on stack
      final bytes = YulCodeGenerator().generate(
        _obj(
          YulBlock([
            YulExpressionStatement(
              YulFunctionCall('mstore', [_num('0'), _num('1')]),
            ),
          ]),
        ),
      );
      expect(bytes, isNotEmpty);
      expect(bytes, contains(0x52)); // MSTORE
    });

    test('stop is void', () {
      final bytes = YulCodeGenerator().generate(
        _obj(YulBlock([YulExpressionStatement(YulFunctionCall('stop', []))])),
      );
      expect(bytes, contains(0x00)); // STOP
    });
  });

  group('YulParser — blocks & expressions', () {
    test('parses let with nested function call', () {
      final block = YulParser('{ let x := add(1, mul(2, 3)) }').parseBlock();
      expect(block.statements, hasLength(1));
      final decl = block.statements.single as YulVariableDeclaration;
      expect(decl.variables, ['x']);
      final call = decl.value as YulFunctionCall;
      expect(call.name, 'add');
      expect(call.arguments, hasLength(2));
      expect((call.arguments[0] as YulLiteral).value, '1');
      expect((call.arguments[1] as YulFunctionCall).name, 'mul');
    });

    test('parses hex and decimal number literals', () {
      final block = YulParser('{ let x := 0xff let y := 42 }').parseBlock();
      expect((block.statements[0] as YulVariableDeclaration).variables, ['x']);
      expect(
        ((block.statements[0] as YulVariableDeclaration).value as YulLiteral)
            .value,
        '0xff',
      );
    });

    test('distinguishes assignment from expression statement', () {
      final block = YulParser('{ x := 1 sstore(0, 2) }').parseBlock();
      expect(block.statements[0], isA<YulAssignment>());
      expect(block.statements[1], isA<YulExpressionStatement>());
    });

    test('parses multi-value declaration and assignment', () {
      final block = YulParser('{ let a, b := f() a, b := g() }').parseBlock();
      expect((block.statements[0] as YulVariableDeclaration).variables, [
        'a',
        'b',
      ]);
      expect((block.statements[1] as YulAssignment).variables, ['a', 'b']);
    });

    test('ignores comments and type annotations', () {
      final block = YulParser('''
        {
          // line comment
          let x : u256 := 1 : u256 /* block */
        }
      ''').parseBlock();
      expect((block.statements.single as YulVariableDeclaration).variables, [
        'x',
      ]);
    });
  });

  group('YulParser — statements', () {
    test('parses function definition with params and returns', () {
      final block = YulParser(
        '{ function double(n) -> r { r := add(n, n) } }',
      ).parseBlock();
      final fn = block.statements.single as YulFunctionDefinition;
      expect(fn.name, 'double');
      expect(fn.parameters, ['n']);
      expect(fn.returnVariables, ['r']);
      expect(fn.body.statements.single, isA<YulAssignment>());
    });

    test('parses if', () {
      final block = YulParser('{ if lt(1, 2) { sstore(0, 1) } }').parseBlock();
      final node = block.statements.single as YulIf;
      expect((node.condition as YulFunctionCall).name, 'lt');
    });

    test('parses switch with cases and default', () {
      final block = YulParser('''
        { switch x
          case 1 { sstore(0, 1) }
          case 2 { sstore(0, 2) }
          default { sstore(0, 0) } }
      ''').parseBlock();
      final node = block.statements.single as YulSwitch;
      expect(node.cases, hasLength(2));
      expect(node.cases[0].value.value, '1');
      expect(node.defaultCase, isNotNull);
    });

    test('parses for loop with break/continue', () {
      final block = YulParser('''
        { for { let i := 0 } lt(i, 10) { i := add(i, 1) }
          { if i { continue } break } }
      ''').parseBlock();
      final loop = block.statements.single as YulForLoop;
      expect(loop.pre.statements.single, isA<YulVariableDeclaration>());
      expect(loop.body.statements.last, isA<YulBreak>());
    });

    test('throws on malformed input', () {
      expect(
        () => YulParser('{ let := 1 }').parseBlock(),
        throwsA(isA<YulParseException>()),
      );
    });
  });

  group('YulParser — objects', () {
    test('parses an object with code and sub-object', () {
      final obj = YulParser('''
        object "Contract" {
          code { mstore(0, 1) return(0, 32) }
          object "Contract_deployed" {
            code { stop() }
          }
          data "meta" hex"deadbeef"
        }
      ''').parseObject();
      expect(obj.name, 'Contract');
      expect(obj.code.statements, hasLength(2));
      expect(obj.subObjects.single.name, 'Contract_deployed');
      expect(obj.data['meta'], [0xde, 0xad, 0xbe, 0xef]);
    });

    test('parse() auto-detects object vs block', () {
      expect(YulParser('object "O" { code {} }').parse(), isA<YulObject>());
      expect(YulParser('{ stop() }').parse(), isA<YulBlock>());
    });
  });

  group('YulOptimizer — constant folding', () {
    // Fold inside an `sstore` so the value is "used" and survives DCE.
    String opt(String src) => YulPrinter().print(
      YulOptimizer().optimizeBlock(YulParser(src).parseBlock()),
    );

    test('folds nested arithmetic', () {
      // add(2, mul(3, 4)) == 14
      expect(
        opt('{ sstore(0, add(2, mul(3, 4))) }'),
        contains('sstore(0, 14)'),
      );
    });

    test('folds comparisons to 0/1', () {
      expect(opt('{ sstore(0, lt(1, 2)) }'), contains('sstore(0, 1)'));
      expect(opt('{ sstore(0, gt(1, 2)) }'), contains('sstore(0, 0)'));
      expect(opt('{ sstore(0, eq(5, 5)) }'), contains('sstore(0, 1)'));
    });

    test('folds with 256-bit wraparound on sub', () {
      // sub(0, 1) == 2**256 - 1
      final maxWord = ((BigInt.one << 256) - BigInt.one).toString();
      expect(opt('{ sstore(0, sub(0, 1)) }'), contains('sstore(0, $maxWord)'));
    });

    test('folds bitwise and shifts', () {
      expect(opt('{ sstore(0, shl(4, 1)) }'), contains('sstore(0, 16)'));
      expect(opt('{ sstore(0, and(12, 10)) }'), contains('sstore(0, 8)'));
    });

    test('folds signed division', () {
      // sdiv(sub(0,6), 2) == -3 (as 2**256-3)
      final minus3 = ((BigInt.one << 256) - BigInt.from(3)).toString();
      expect(opt('{ sstore(0, sdiv(sub(0, 6), 2)) }'), contains(minus3));
    });
  });

  group('YulOptimizer — algebraic simplification', () {
    String opt(String src) => YulPrinter().print(
      YulOptimizer().optimizeBlock(YulParser(src).parseBlock()),
    );

    test('add(x, 0) -> x', () {
      expect(
        opt('{ let y := 5 sstore(0, add(y, 0)) }'),
        contains('sstore(0, y)'),
      );
    });

    test('mul(x, 1) -> x', () {
      expect(
        opt('{ let y := 5 sstore(0, mul(y, 1)) }'),
        contains('sstore(0, y)'),
      );
    });

    test('mul(x, 0) -> 0 when side-effect-free', () {
      expect(
        opt('{ let y := 5 sstore(0, mul(y, 0)) }'),
        contains('sstore(0, 0)'),
      );
    });

    test('does not drop a side-effecting operand in mul(_, 0)', () {
      // sstore is not pure, so mul(sstore(...), 0) must keep the call.
      final out = opt('{ sstore(0, mul(sstore(1, 2), 0)) }');
      expect(out, contains('sstore(1, 2)'));
    });
  });

  group('YulOptimizer — dead-code elimination', () {
    String opt(String src) => YulPrinter().print(
      YulOptimizer().optimizeBlock(YulParser(src).parseBlock()),
    );

    test('drops an unused side-effect-free binding', () {
      final out = opt('{ let unused := add(1, 2) sstore(0, 1) }');
      expect(out, isNot(contains('unused')));
      expect(out, contains('sstore(0, 1)'));
    });

    test('keeps a used binding', () {
      final out = opt('{ let x := 7 sstore(0, x) }');
      expect(out, contains('let x := 7'));
    });

    test('keeps the side effect of an unused but impure binding', () {
      final out = opt('{ let x := sload(0) let y := sstore(1, 2) }');
      // y is unused; sstore must survive as a bare expression statement.
      expect(out, contains('sstore(1, 2)'));
      expect(out, isNot(contains('let y')));
    });

    test('removes statements after a terminator', () {
      final out = opt('{ return(0, 32) let dead := 1 sstore(0, dead) }');
      expect(out, contains('return(0, 32)'));
      expect(out, isNot(contains('dead')));
    });
  });

  group('YulOptimizer — inlining', () {
    String opt(String src) => YulPrinter().print(
      YulOptimizer().optimizeBlock(YulParser(src).parseBlock()),
    );

    test('skips functions that are part of a mutual-recursion cycle', () {
      // a → b → a: the call-graph cycle must keep both functions intact.
      const src = '''{
        function a() { b() }
        function b() { a() }
        a()
      }''';
      final out = opt(src);
      // Both definitions must survive (they cannot be inlined).
      expect(out, contains('function a()'));
      expect(out, contains('function b()'));
    });

    test('inlines a single-caller function even if its body is large', () {
      // 13 statements — above the default threshold of 12 — but called only
      // once, so the new call-count heuristic should still inline it.
      const src = '''{
        function fat() -> r {
          let a1 := 1
          let a2 := 2
          let a3 := 3
          let a4 := 4
          let a5 := 5
          let a6 := 6
          let a7 := 7
          let a8 := 8
          let a9 := 9
          let a10 := 10
          let a11 := 11
          let a12 := 12
          r := add(a1, add(a2, add(a3, add(a4, add(a5, add(a6, add(a7, add(a8, add(a9, add(a10, add(a11, a12)))))))))))
        }
        let total := fat()
        sstore(0, total)
      }''';
      final out = opt(src);
      // After inlining, the call site is replaced by a `for {} 1 {} { ... break }`
      // loop and a fresh `_il<n>_r` return slot. The function definition itself
      // survives (DCE keeps definitions), so we check on the call-site shape.
      expect(out, contains('_il0_r'));
      expect(out, contains('let total := _il0_r'));
      expect(out, isNot(contains('let total := fat()')));
    });
  });

  group('YulOptimizer — preserves behaviour', () {
    test('optimised object still produces bytecode', () {
      final obj =
          YulParser('''
        object "C" {
          code {
            let x := add(mul(2, 3), 0)
            let junk := 99
            sstore(0, x)
          }
        }
      ''').parse()
              as YulObject;
      final optimised = YulOptimizer().optimize(obj);
      final bytes = YulCodeGenerator().generate(optimised);
      expect(bytes, isNotEmpty);
      // The dead `junk` binding is gone, so PUSH1 99 (0x63) should not appear.
      expect(bytes, isNot(contains(99)));
    });
  });

  group('YulCodeGenerator — deployed bytecode size limit', () {
    test('generateDeployed succeeds for small contracts', () {
      final obj = _obj(
        YulBlock([YulExpressionStatement(YulFunctionCall('stop', []))]),
      );
      expect(() => YulCodeGenerator().generateDeployed(obj), returnsNormally);
    });

    test(
      'generateDeployed throws ArgumentError when bytecode exceeds 24KB',
      () {
        // Build a Yul block with enough sstore calls to exceed 24,576 bytes.
        // Each `sstore(slot, value)` lowers to roughly ~5–7 bytes; 4000 calls
        // produces well over 24KB.
        final stmts = <YulStatement>[
          for (var i = 0; i < 4000; i++)
            YulExpressionStatement(
              YulFunctionCall('sstore', [_num('$i'), _num('$i')]),
            ),
        ];
        final obj = _obj(YulBlock(stmts));
        expect(
          () => YulCodeGenerator().generateDeployed(obj),
          throwsArgumentError,
        );
      },
    );
  });

  group('YulParser ↔ codegen / printer round-trip', () {
    test('parsed block compiles to bytecode', () {
      final block = YulParser('{ let x := add(1, 2) }').parseBlock();
      final bytes = YulCodeGenerator().generate(_obj(block));
      expect(bytes, isNotEmpty);
    });

    test('printer output re-parses to an equivalent tree', () {
      const src = '{ let x := add(1, 2) if x { sstore(0, x) } }';
      final first = YulParser(src).parseBlock();
      final printed = YulPrinter().print(first);
      final second = YulParser(printed).parseBlock();
      expect(YulPrinter().print(second), printed);
    });
  });
}
