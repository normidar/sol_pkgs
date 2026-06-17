import 'package:sol_support/sol_support.dart';
import 'token.dart';
import 'token_kind.dart';

/// Tokenises Solidity source text.
///
/// Usage:
/// ```dart
/// final lexer = Lexer(source: src, sourceIndex: 0);
/// for (final tok in lexer.tokenize()) {
///   print(tok);
/// }
/// ```
class Lexer {
  Lexer({required this.source, required this.sourceIndex});

  final String source;
  final int sourceIndex;

  int _pos = 0;

  // ── public API ────────────────────────────────────────────────────────────

  /// Returns all tokens (including EOF), skipping whitespace/comments.
  List<Token> tokenize({bool includeTrivia = false}) {
    final tokens = <Token>[];
    while (true) {
      final tok = nextToken();
      if (!includeTrivia &&
          (tok.kind == TokenKind.Whitespace ||
              tok.kind == TokenKind.Comment)) {
        if (tok.isEof) {
          tokens.add(tok);
          break;
        }
        continue;
      }
      tokens.add(tok);
      if (tok.isEof) break;
    }
    return tokens;
  }

  /// Scan and return one token (including whitespace/comment trivia).
  Token nextToken() {
    if (_pos >= source.length) return _tok(TokenKind.Eof, _pos, 0);

    final start = _pos;
    final ch = source.codeUnitAt(_pos);

    // ── Whitespace ────────────────────────────────────────────────────────
    if (_isWhitespace(ch)) {
      while (_pos < source.length && _isWhitespace(source.codeUnitAt(_pos))) {
        _pos++;
      }
      return _tok(TokenKind.Whitespace, start, _pos - start);
    }

    // ── Line comment ──────────────────────────────────────────────────────
    if (ch == 0x2F && _peek(1) == 0x2F) {
      _pos += 2;
      while (_pos < source.length && source.codeUnitAt(_pos) != 0x0A) _pos++;
      return _tok(TokenKind.Comment, start, _pos - start);
    }

    // ── Block comment ─────────────────────────────────────────────────────
    if (ch == 0x2F && _peek(1) == 0x2A) {
      _pos += 2;
      while (_pos < source.length - 1) {
        if (source.codeUnitAt(_pos) == 0x2A &&
            source.codeUnitAt(_pos + 1) == 0x2F) {
          _pos += 2;
          break;
        }
        _pos++;
      }
      return _tok(TokenKind.Comment, start, _pos - start);
    }

    // ── String literals ───────────────────────────────────────────────────
    if (ch == 0x22 /* " */ || ch == 0x27 /* ' */) {
      return _scanString(start, ch);
    }
    if (_matchKeyword('unicode"') || _matchKeyword("unicode'")) {
      return _scanString(start, source.codeUnitAt(_pos - 1),
          kind: TokenKind.UnicodeStringLiteral);
    }
    if (_matchKeyword('hex"') || _matchKeyword("hex'")) {
      return _scanString(start, source.codeUnitAt(_pos - 1),
          kind: TokenKind.HexStringLiteral);
    }

    // ── Hex number ────────────────────────────────────────────────────────
    if (ch == 0x30 && _peek(1) == 0x78 /* 0x */) {
      _pos += 2;
      while (_pos < source.length && _isHexDigit(source.codeUnitAt(_pos))) {
        _pos++;
      }
      return _tokLex(TokenKind.NumberLiteral, start);
    }

    // ── Decimal number ────────────────────────────────────────────────────
    if (_isDigit(ch)) {
      while (_pos < source.length && _isDigit(source.codeUnitAt(_pos))) _pos++;
      if (_pos < source.length && source.codeUnitAt(_pos) == 0x2E /* . */) {
        _pos++;
        while (_pos < source.length && _isDigit(source.codeUnitAt(_pos))) {
          _pos++;
        }
      }
      if (_pos < source.length &&
          (source.codeUnitAt(_pos) == 0x65 /* e */ ||
              source.codeUnitAt(_pos) == 0x45 /* E */)) {
        _pos++;
        if (_pos < source.length &&
            (source.codeUnitAt(_pos) == 0x2B /* + */ ||
                source.codeUnitAt(_pos) == 0x2D /* - */)) {
          _pos++;
        }
        while (_pos < source.length && _isDigit(source.codeUnitAt(_pos))) {
          _pos++;
        }
      }
      return _tokLex(TokenKind.NumberLiteral, start);
    }

    // ── Identifiers & keywords ────────────────────────────────────────────
    if (_isIdentStart(ch)) {
      while (_pos < source.length && _isIdentCont(source.codeUnitAt(_pos))) {
        _pos++;
      }
      final text = source.substring(start, _pos);
      final kind = keywordOrIdentifier(text);
      int width = 0;
      if (kind == TokenKind.UintN) {
        width = int.parse(text.substring(4));
      } else if (kind == TokenKind.IntN) {
        width = int.parse(text.substring(3));
      } else if (kind == TokenKind.BytesN) {
        width = int.parse(text.substring(5));
      }
      return Token(
        kind: kind,
        location: _loc(start, _pos - start),
        lexeme: text,
        intWidth: width,
      );
    }

    // ── Punctuation & operators ───────────────────────────────────────────
    _pos++;
    switch (ch) {
      case 0x28: return _tok(TokenKind.LParen, start, 1);
      case 0x29: return _tok(TokenKind.RParen, start, 1);
      case 0x5B: return _tok(TokenKind.LBracket, start, 1);
      case 0x5D: return _tok(TokenKind.RBracket, start, 1);
      case 0x7B: return _tok(TokenKind.LBrace, start, 1);
      case 0x7D: return _tok(TokenKind.RBrace, start, 1);
      case 0x3B: return _tok(TokenKind.Semicolon, start, 1);
      case 0x2C: return _tok(TokenKind.Comma, start, 1);
      case 0x7E: return _tok(TokenKind.Tilde, start, 1);
      case 0x3F: return _tok(TokenKind.Question, start, 1);

      case 0x2B: // +
        if (_consume(0x2B)) return _tok(TokenKind.PlusPlus, start, 2);
        if (_consume(0x3D)) return _tok(TokenKind.PlusEq, start, 2);
        return _tok(TokenKind.Plus, start, 1);

      case 0x2D: // -
        if (_consume(0x2D)) return _tok(TokenKind.MinusMinus, start, 2);
        if (_consume(0x3D)) return _tok(TokenKind.MinusEq, start, 2);
        if (_consume(0x3E)) return _tok(TokenKind.RightArrow, start, 2);
        return _tok(TokenKind.Minus, start, 1);

      case 0x2A: // *
        if (_consume(0x2A)) return _tok(TokenKind.StarStar, start, 2);
        if (_consume(0x3D)) return _tok(TokenKind.StarEq, start, 2);
        return _tok(TokenKind.Star, start, 1);

      case 0x2F: // /
        if (_consume(0x3D)) return _tok(TokenKind.SlashEq, start, 2);
        return _tok(TokenKind.Slash, start, 1);

      case 0x25: // %
        if (_consume(0x3D)) return _tok(TokenKind.PercentEq, start, 2);
        return _tok(TokenKind.Percent, start, 1);

      case 0x26: // &
        if (_consume(0x26)) return _tok(TokenKind.AmpAmp, start, 2);
        if (_consume(0x3D)) return _tok(TokenKind.AmpEq, start, 2);
        return _tok(TokenKind.Ampersand, start, 1);

      case 0x7C: // |
        if (_consume(0x7C)) return _tok(TokenKind.PipePipe, start, 2);
        if (_consume(0x3D)) return _tok(TokenKind.PipeEq, start, 2);
        return _tok(TokenKind.Pipe, start, 1);

      case 0x5E: // ^
        if (_consume(0x3D)) return _tok(TokenKind.CaretEq, start, 2);
        return _tok(TokenKind.Caret, start, 1);

      case 0x21: // !
        if (_consume(0x3D)) return _tok(TokenKind.BangEq, start, 2);
        return _tok(TokenKind.Bang, start, 1);

      case 0x3D: // =
        if (_consume(0x3D)) return _tok(TokenKind.EqEq, start, 2);
        if (_consume(0x3E)) return _tok(TokenKind.Arrow, start, 2);
        return _tok(TokenKind.Eq, start, 1);

      case 0x3C: // <
        if (_consume(0x3C)) {
          if (_consume(0x3D)) return _tok(TokenKind.LtLtEq, start, 3);
          return _tok(TokenKind.LtLt, start, 2);
        }
        if (_consume(0x3D)) return _tok(TokenKind.LtEq, start, 2);
        return _tok(TokenKind.Lt, start, 1);

      case 0x3E: // >
        if (_consume(0x3E)) {
          if (_consume(0x3E)) {
            if (_consume(0x3D)) return _tok(TokenKind.GtGtGtEq, start, 4);
            return _tok(TokenKind.GtGtGt, start, 3);
          }
          if (_consume(0x3D)) return _tok(TokenKind.GtGtEq, start, 3);
          return _tok(TokenKind.GtGt, start, 2);
        }
        if (_consume(0x3D)) return _tok(TokenKind.GtEq, start, 2);
        return _tok(TokenKind.Gt, start, 1);

      case 0x2E: // .
        if (_consume(0x2E) && _consume(0x2E)) {
          return _tok(TokenKind.DotDotDot, start, 3);
        }
        return _tok(TokenKind.Dot, start, 1);

      case 0x3A: // :
        if (_consume(0x3A)) return _tok(TokenKind.ColonColon, start, 2);
        return _tok(TokenKind.Colon, start, 1);

      default:
        return _tok(TokenKind.Error, start, 1);
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  Token _scanString(int start, int quote,
      {TokenKind kind = TokenKind.StringLiteral}) {
    while (_pos < source.length) {
      final c = source.codeUnitAt(_pos++);
      if (c == 0x5C /* \ */) {
        _pos++; // skip escape
      } else if (c == quote) {
        break;
      }
    }
    return _tokLex(kind, start);
  }

  bool _matchKeyword(String kw) {
    if (_pos + kw.length > source.length) return false;
    if (source.startsWith(kw, _pos)) {
      _pos += kw.length;
      return true;
    }
    return false;
  }

  bool _consume(int code) {
    if (_pos < source.length && source.codeUnitAt(_pos) == code) {
      _pos++;
      return true;
    }
    return false;
  }

  int _peek(int offset) {
    final i = _pos + offset;
    return i < source.length ? source.codeUnitAt(i) : -1;
  }

  Token _tok(TokenKind kind, int start, int length) =>
      Token(kind: kind, location: _loc(start, length));

  Token _tokLex(TokenKind kind, int start) => Token(
        kind: kind,
        location: _loc(start, _pos - start),
        lexeme: source.substring(start, _pos),
      );

  SourceLocation _loc(int start, int length) =>
      SourceLocation(sourceIndex: sourceIndex, offset: start, length: length);

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isHexDigit(int c) =>
      _isDigit(c) ||
      (c >= 0x41 && c <= 0x46) ||
      (c >= 0x61 && c <= 0x66);

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _isIdentCont(int c) => _isIdentStart(c) || _isDigit(c);
}
