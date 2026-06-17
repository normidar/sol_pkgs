import 'package:sol_ast/sol_ast.dart';
import 'package:sol_lexer/sol_lexer.dart';
import 'package:sol_parser/sol_parser.dart';
import 'package:sol_support/sol_support.dart';
import 'package:test/test.dart';

SourceFile parse(String src) {
  final diagnostics = DiagnosticCollector();
  final tokens = Lexer(source: src, sourceIndex: 0).tokenize();
  return Parser(tokens: tokens, sourceIndex: 0, diagnostics: diagnostics)
      .parse();
}

void main() {
  group('Parser – pragma', () {
    test('parses pragma solidity', () {
      final ast = parse('pragma solidity ^0.8.0;');
      expect(ast.pragmas, hasLength(1));
      expect(ast.pragmas.first.literals, contains('solidity'));
    });
  });

  group('Parser – contract', () {
    test('parses empty contract', () {
      final ast = parse('contract Foo {}');
      expect(ast.declarations, hasLength(1));
      expect(ast.declarations.first.name, 'Foo');
    });

    test('parses contract with inheritance', () {
      final ast = parse('contract Bar is Foo {}');
      expect(ast.declarations.first.baseContracts, hasLength(1));
      expect(ast.declarations.first.baseContracts.first.name, 'Foo');
    });
  });

  group('Parser – function', () {
    const src = '''
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

    test('parses pure function', () {
      final ast = parse(src);
      final fn = ast.declarations.first.members.first as FunctionDefinition;
      expect(fn.name, 'getSum');
      expect(fn.stateMutability, StateMutability.pure);
      expect(fn.visibility, Visibility.public);
      expect(fn.parameters, hasLength(2));
      expect(fn.returnParameters, hasLength(1));
    });

    test('function body has return statement', () {
      final ast = parse(src);
      final fn = ast.declarations.first.members.first as FunctionDefinition;
      final ret = fn.body!.statements.first as ReturnStatement;
      final bin = ret.expression as BinaryOperation;
      expect(bin.operator$, '+');
    });
  });

  group('Parser – state variable', () {
    test('parses uint256 public constant', () {
      final ast = parse('contract C { uint256 public constant MAX = 100; }');
      final sv = ast.declarations.first.members.first as StateVariableDeclaration;
      expect(sv.name, 'MAX');
      expect(sv.mutability, VariableMutability.constant);
    });
  });

  group('Parser – import', () {
    test('parses plain import', () {
      final ast = parse('import "path/to/File.sol";');
      expect(ast.imports, hasLength(1));
      expect(ast.imports.first.path, '"path/to/File.sol"');
    });
  });
}
