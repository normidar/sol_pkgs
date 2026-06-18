import 'package:sol_support/sol_support.dart';
import 'token_kind.dart';

class Token {
  const Token({
    required this.kind,
    required this.location,
    this.lexeme = '',
    this.intWidth = 0,
  });

  final TokenKind kind;
  final SourceLocation location;

  /// Raw text from the source (identifier name, number literal text, etc.).
  final String lexeme;

  /// For `IntN`, `UintN`, `BytesN`: the numeric width (8, 16, …, 256 / 1…32).
  final int intWidth;

  bool get isEof => kind == TokenKind.Eof;

  @override
  String toString() =>
      'Token(${kind.name}, ${lexeme.isEmpty ? "" : '"$lexeme"'}, $location)';
}
