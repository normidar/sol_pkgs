import 'package:sol_ast/sol_ast.dart';
import 'package:sol_sema/sol_sema.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart' hide StateMutability;
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

SourceLocation _loc() =>
    const SourceLocation(sourceIndex: 0, offset: 0, length: 0);

SourceFile _sourceFile(List<ContractDefinition> contracts) =>
    SourceFile(_loc(), [], [], contracts);

ContractDefinition _contract(String name, List<AstNode> members) =>
    ContractDefinition(_loc(), ContractKind.contract, name, [], members);

FunctionDefinition _fn(
  String name, {
  List<Parameter> params = const [],
  List<Parameter> returns = const [],
  Block? body,
}) => FunctionDefinition(
  location: _loc(),
  kind: FunctionKind.function,
  name: name,
  parameters: params,
  returnParameters: returns,
  visibility: Visibility.public,
  stateMutability: StateMutability.nonpayable,
  isVirtual: false,
  overrideSpecifier: [],
  modifiers: [],
  body: body,
);

Parameter _param(String name, String typeName) =>
    Parameter(_loc(), ElementaryTypeName(_loc(), typeName), name, null);

Block _block(List<Statement> stmts) => Block(_loc(), stmts);

Identifier _id(String name) => Identifier(_loc(), name);

Literal _lit(String v) => Literal(_loc(), LiteralKind.number, v, null);

VariableDeclarationStatement _varDecl(
  String name,
  String typeName, [
  Expression? init,
]) => VariableDeclarationStatement(_loc(), [
  VariableDeclaration(_loc(), ElementaryTypeName(_loc(), typeName), name, null),
], init);

DiagnosticCollector _newDiags() => DiagnosticCollector();

// ── C3 linearisation ─────────────────────────────────────────────────────────

void main() {
  group('C3 linearisation', () {
    test('single contract no bases', () {
      expect(c3Linearise('A', (_) => []), ['A']);
    });

    test('simple chain A → B → C', () {
      final bases = {
        'A': ['B'],
        'B': ['C'],
        'C': <String>[],
      };
      expect(c3Linearise('A', (n) => bases[n]!), ['A', 'B', 'C']);
    });

    test('diamond inheritance', () {
      final bases = {
        'D': ['B', 'C'],
        'B': ['A'],
        'C': ['A'],
        'A': <String>[],
      };
      expect(c3Linearise('D', (n) => bases[n]!), ['D', 'B', 'C', 'A']);
    });

    test('cycle throws', () {
      final bases = {
        'A': ['B'],
        'B': ['A'],
      };
      expect(
        () => c3Linearise('A', (n) => bases[n]!),
        throwsA(isA<C3LinearisationError>()),
      );
    });

    test('three-way linearisation', () {
      // C → A, B; A → Base; B → Base
      final bases = {
        'C': ['A', 'B'],
        'A': ['Base'],
        'B': ['Base'],
        'Base': <String>[],
      };
      expect(c3Linearise('C', (n) => bases[n]!), ['C', 'A', 'B', 'Base']);
    });
  });

  // ── Resolver ──────────────────────────────────────────────────────────────

  group('Resolver', () {
    test('hoists function name — reference from another function works', () {
      final diags = _newDiags();
      final callExpr = _id('foo');
      final file = _sourceFile([
        _contract('C', [
          _fn('bar', body: _block([ExpressionStatement(_loc(), callExpr)])),
          _fn('foo', body: _block([])),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(
        diags.diagnostics,
        isEmpty,
        reason: 'forward reference to foo should resolve',
      );
      expect(callExpr.annotation, isNotNull);
    });

    test('hoists state variable', () {
      final diags = _newDiags();
      final ref = _id('x');
      final file = _sourceFile([
        _contract('C', [
          _fn('getX', body: _block([ReturnStatement(_loc(), ref)])),
          StateVariableDeclaration(
            _loc(),
            ElementaryTypeName(_loc(), 'uint256'),
            'x',
            Visibility.private,
            VariableMutability.mutable,
            null,
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
      expect(ref.annotation, isNotNull);
    });

    test('hoists event', () {
      final diags = _newDiags();
      final ref = _id('Transfer');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'emit_',
            body: _block([
              EmitStatement(_loc(), FunctionCall(_loc(), ref, [], [])),
            ]),
          ),
          EventDefinition(_loc(), 'Transfer', [], false),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
    });

    test('hoists custom error', () {
      final diags = _newDiags();
      final ref = _id('MyError');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            body: _block([
              RevertStatement(_loc(), FunctionCall(_loc(), ref, [], [])),
            ]),
          ),
          CustomErrorDefinition(_loc(), 'MyError', []),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
    });

    test('hoists struct name', () {
      final diags = _newDiags();
      final ref = _id('MyStruct');
      final file = _sourceFile([
        _contract('C', [
          _fn('f', body: _block([ExpressionStatement(_loc(), ref)])),
          StructDefinition(_loc(), 'MyStruct', []),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
    });

    test('hoists enum name', () {
      final diags = _newDiags();
      final ref = _id('Color');
      final file = _sourceFile([
        _contract('C', [
          _fn('f', body: _block([ExpressionStatement(_loc(), ref)])),
          EnumDefinition(_loc(), 'Color', ['Red', 'Green']),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
    });

    test('undeclared identifier reports error', () {
      final diags = _newDiags();
      final file = _sourceFile([
        _contract('C', [
          _fn('f', body: _block([ExpressionStatement(_loc(), _id('unknown'))])),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isNotEmpty);
      expect(diags.diagnostics.first.message, contains('unknown'));
    });

    test('local variable declared in block is visible', () {
      final diags = _newDiags();
      final ref = _id('local');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            body: _block([
              _varDecl('local', 'uint256', _lit('0')),
              ExpressionStatement(_loc(), ref),
            ]),
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
      expect(ref.annotation, isNotNull);
    });

    test('parameter is in scope inside function body', () {
      final diags = _newDiags();
      final ref = _id('a');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            params: [_param('a', 'uint256')],
            body: _block([ReturnStatement(_loc(), ref)]),
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
      expect(ref.annotation, isNotNull);
    });

    test('named return parameter is in scope', () {
      final diags = _newDiags();
      final ref = _id('result');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            returns: [_param('result', 'uint256')],
            body: _block([
              ExpressionStatement(
                _loc(),
                Assignment(_loc(), '=', ref, _lit('42')),
              ),
            ]),
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
    });

    test('built-in names suppressed (msg, block, this, etc.)', () {
      final diags = _newDiags();
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            body: _block([
              ExpressionStatement(_loc(), _id('msg')),
              ExpressionStatement(_loc(), _id('block')),
              ExpressionStatement(_loc(), _id('this')),
              ExpressionStatement(_loc(), _id('super')),
            ]),
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(
        diags.diagnostics,
        isEmpty,
        reason: 'built-in names should not cause undeclared errors',
      );
    });

    test('local variable not visible outside its block', () {
      final diags = _newDiags();
      final ref = _id('inner');
      final file = _sourceFile([
        _contract('C', [
          _fn(
            'f',
            body: _block([
              _block([_varDecl('inner', 'uint256')]),
              ExpressionStatement(_loc(), ref), // out-of-scope use
            ]),
          ),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(
        diags.diagnostics,
        isNotEmpty,
        reason: 'inner should be out of scope here',
      );
    });

    test('if statement visits condition and branches', () {
      final diags = _newDiags();
      final cond = _id('flag');
      final file = _sourceFile([
        _contract('C', [
          StateVariableDeclaration(
            _loc(),
            ElementaryTypeName(_loc(), 'bool'),
            'flag',
            Visibility.public,
            VariableMutability.mutable,
            null,
          ),
          _fn('f', body: _block([IfStatement(_loc(), cond, _block([]), null)])),
        ]),
      ]);
      Resolver(diags).resolve(file);
      expect(diags.diagnostics, isEmpty);
      expect(cond.annotation, isNotNull);
    });
  });

  // ── TypeChecker ──────────────────────────────────────────────────────────

  group('TypeChecker', () {
    SolType _check(Expression expr) {
      final diags = _newDiags();
      final fn = _fn('f', body: _block([ReturnStatement(_loc(), expr)]));
      final file = _sourceFile([
        _contract('C', [fn]),
      ]);
      Resolver(diags).resolve(file);
      TypeChecker(diags).check(file);
      return expr.annotation is SolType
          ? expr.annotation as SolType
          : errorType;
    }

    test('number literal → uint256', () {
      expect(_check(_lit('42')), isA<IntType>());
    });

    test('bool literal → bool', () {
      final expr = Literal(_loc(), LiteralKind.bool$, 'true', null);
      expect(_check(expr), equals(boolType));
    });

    test('string literal → string', () {
      final expr = Literal(_loc(), LiteralKind.string, 'hello', null);
      expect(_check(expr), isA<StringType>());
    });

    test('binary op uint256 + uint256 → uint256', () {
      final expr = BinaryOperation(_loc(), '+', _lit('1'), _lit('2'));
      final t = _check(expr);
      expect(t, isA<IntType>());
    });

    test('comparison returns bool', () {
      final expr = BinaryOperation(_loc(), '<', _lit('1'), _lit('2'));
      expect(_check(expr), equals(boolType));
    });

    test('logical && returns bool', () {
      final l = Literal(_loc(), LiteralKind.bool$, 'true', null);
      final r = Literal(_loc(), LiteralKind.bool$, 'false', null);
      final expr = BinaryOperation(_loc(), '&&', l, r);
      expect(_check(expr), equals(boolType));
    });

    test('unary ! returns bool', () {
      final inner = Literal(_loc(), LiteralKind.bool$, 'true', null);
      final expr = UnaryOperation(_loc(), '!', inner, true);
      expect(_check(expr), equals(boolType));
    });

    test('unary - preserves type', () {
      final expr = UnaryOperation(_loc(), '-', _lit('1'), true);
      final t = _check(expr);
      expect(t, isA<IntType>());
    });

    test('if statement visited', () {
      final diags = _newDiags();
      final cond = Literal(_loc(), LiteralKind.bool$, 'true', null);
      final file = _sourceFile([
        _contract('C', [
          _fn('f', body: _block([IfStatement(_loc(), cond, _block([]), null)])),
        ]),
      ]);
      Resolver(diags).resolve(file);
      TypeChecker(diags).check(file);
      expect(diags.diagnostics, isEmpty);
      expect(cond.annotation, equals(boolType));
    });

    test('variable declaration annotated with type', () {
      final diags = _newDiags();
      final varDecl = _varDecl('x', 'uint256', _lit('0'));
      final file = _sourceFile([
        _contract('C', [
          _fn('f', body: _block([varDecl])),
        ]),
      ]);
      Resolver(diags).resolve(file);
      TypeChecker(diags).check(file);
      expect(diags.diagnostics, isEmpty);
      expect(varDecl.declarations.first?.annotation, isA<IntType>());
    });

    test('resolver assigns the declared (signed) type to a parameter', () {
      final diags = _newDiags();
      final id = _id('x');
      final fn = _fn(
        'f',
        params: [_param('x', 'int128')],
        body: _block([ExpressionStatement(_loc(), id)]),
      );
      final file = _sourceFile([
        _contract('C', [fn]),
      ]);
      Resolver(diags).resolve(file);
      TypeChecker(diags).check(file);
      final t = id.annotation;
      expect(t, isA<IntType>());
      expect((t as IntType).bits, 128);
      expect(t.signed, isTrue);
    });

    test('int256 minus a number literal is allowed and stays signed', () {
      // Regression: number literals adapt to the other operand's integer type,
      // so `x - 1` with `int256 x` must not raise a type-mismatch error.
      final diags = _newDiags();
      final expr = BinaryOperation(_loc(), '-', _id('x'), _lit('1'));
      final fn = _fn(
        'f',
        params: [_param('x', 'int256')],
        returns: [_param('', 'int256')],
        body: _block([ReturnStatement(_loc(), expr)]),
      );
      final file = _sourceFile([
        _contract('C', [fn]),
      ]);
      Resolver(diags).resolve(file);
      TypeChecker(diags).check(file);
      expect(
        diags.diagnostics.where((d) => d.isError),
        isEmpty,
        reason: 'literal should adapt to int256',
      );
      final t = expr.annotation;
      expect(t, isA<IntType>());
      expect((t as IntType).signed, isTrue);
    });
  });
}
