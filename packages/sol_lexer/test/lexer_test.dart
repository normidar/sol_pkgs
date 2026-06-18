import 'package:sol_lexer/sol_lexer.dart';
import 'package:test/test.dart';

List<Token> scan(String src) => Lexer(source: src, sourceIndex: 0).tokenize();

void main() {
  group('Lexer – keywords', () {
    test('recognises contract keyword', () {
      final toks = scan('contract');
      expect(toks.first.kind, TokenKind.kContract);
    });

    test('recognises uint256', () {
      final toks = scan('uint256');
      expect(toks.first.kind, TokenKind.UintN);
      expect(toks.first.intWidth, 256);
    });

    test('recognises int8', () {
      final toks = scan('int8');
      expect(toks.first.kind, TokenKind.IntN);
      expect(toks.first.intWidth, 8);
    });

    test('recognises bytes32', () {
      final toks = scan('bytes32');
      expect(toks.first.kind, TokenKind.BytesN);
      expect(toks.first.intWidth, 32);
    });

    test('pure / view / payable', () {
      final toks = scan('pure view payable');
      expect(toks.map((t) => t.kind).toList(), [
        TokenKind.kPure,
        TokenKind.kView,
        TokenKind.kPayable,
        TokenKind.Eof,
      ]);
    });
  });

  group('Lexer – literals', () {
    test('decimal number', () {
      final toks = scan('42');
      expect(toks.first.kind, TokenKind.NumberLiteral);
      expect(toks.first.lexeme, '42');
    });

    test('hex number', () {
      final toks = scan('0xFF');
      expect(toks.first.kind, TokenKind.NumberLiteral);
      expect(toks.first.lexeme, '0xFF');
    });

    test('string literal', () {
      final toks = scan('"hello"');
      expect(toks.first.kind, TokenKind.StringLiteral);
    });
  });

  group('Lexer – operators', () {
    test('** exponentiation', () {
      expect(scan('**').first.kind, TokenKind.StarStar);
    });

    test('>>> unsigned shift', () {
      expect(scan('>>>').first.kind, TokenKind.GtGtGt);
    });

    test('+= compound assignment', () {
      expect(scan('+=').first.kind, TokenKind.PlusEq);
    });
  });

  group('Lexer – simple contract', () {
    const src = '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';
    test('produces no error tokens', () {
      final toks = Lexer(source: src, sourceIndex: 0).tokenize();
      expect(toks.where((t) => t.kind == TokenKind.Error), isEmpty);
    });

    test('finds function keyword', () {
      final toks = Lexer(source: src, sourceIndex: 0).tokenize();
      expect(toks.any((t) => t.kind == TokenKind.kFunction), isTrue);
    });
  });
}
