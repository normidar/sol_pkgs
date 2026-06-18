import 'package:sol_support/sol_support.dart';
import 'token.dart';
import 'token_kind.dart';

/// Tokenises Solidity 0.8.x source text.
///
/// Usage:
/// ```dart
/// final tokens = Lexer(source: src, sourceIndex: 0).tokenize();
/// ```
class Lexer {
  Lexer({required this.source, required this.sourceIndex});

  final String source;
  final int sourceIndex;

  int _pos = 0;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all tokens (excluding whitespace/plain comments) up to and
  /// including [TokenKind.Eof].  NatSpec tokens are kept.
  List<Token> tokenize({bool includeTrivia = false}) {
    final tokens = <Token>[];
    while (true) {
      final tok = nextToken();
      final skip =
          !includeTrivia &&
          (tok.kind == TokenKind.Whitespace || tok.kind == TokenKind.Comment);
      if (!skip) tokens.add(tok);
      if (tok.kind == TokenKind.Eof) break;
    }
    return tokens;
  }

  /// Scans and returns one raw token (including trivia).
  Token nextToken() {
    if (_pos >= source.length) {
      return _tok(TokenKind.Eof, _pos, 0);
    }

    final start = _pos;
    final ch = _cu(_pos);

    // ── Whitespace ────────────────────────────────────────────────────────
    if (_isWs(ch)) {
      while (_pos < source.length && _isWs(_cu(_pos))) _pos++;
      return _tok(TokenKind.Whitespace, start, _pos - start);
    }

    // ── Comments ──────────────────────────────────────────────────────────
    if (ch == 0x2F) {
      final next = _peek(1);
      // NatSpec line  ///
      if (next == 0x2F && _peek(2) == 0x2F) {
        _pos += 3;
        while (_pos < source.length && _cu(_pos) != 0x0A) _pos++;
        return _tokLex(TokenKind.NatSpecLine, start);
      }
      // Line comment //
      if (next == 0x2F) {
        _pos += 2;
        while (_pos < source.length && _cu(_pos) != 0x0A) _pos++;
        return _tok(TokenKind.Comment, start, _pos - start);
      }
      // NatSpec block  /**
      if (next == 0x2A && _peek(2) == 0x2A && _peek(3) != 0x2F) {
        _pos += 3;
        while (_pos < source.length - 1) {
          if (_cu(_pos) == 0x2A && _cu(_pos + 1) == 0x2F) {
            _pos += 2;
            break;
          }
          _pos++;
        }
        return _tokLex(TokenKind.NatSpecBlock, start);
      }
      // Block comment /*
      if (next == 0x2A) {
        _pos += 2;
        while (_pos < source.length - 1) {
          if (_cu(_pos) == 0x2A && _cu(_pos + 1) == 0x2F) {
            _pos += 2;
            break;
          }
          _pos++;
        }
        return _tok(TokenKind.Comment, start, _pos - start);
      }
    }

    // ── String prefixes: unicode"…" hex"…" ───────────────────────────────
    if (_isIdentStart(ch)) {
      // Peek ahead for string prefixes before falling through to identifier.
      if (_matchPrefix('unicode')) {
        final q = _cu(_pos);
        if (q == 0x22 || q == 0x27) {
          return _scanString(start, q, kind: TokenKind.UnicodeStringLiteral);
        }
        // Not a string: rewind and lex as identifier.
        _pos = start;
      } else if (_matchPrefix('hex')) {
        final q = _cu(_pos);
        if (q == 0x22 || q == 0x27) {
          return _scanString(start, q, kind: TokenKind.HexStringLiteral);
        }
        _pos = start;
      }
    }

    // ── Plain string literals ─────────────────────────────────────────────
    if (ch == 0x22 /* " */ || ch == 0x27 /* ' */ ) {
      return _scanString(start, ch);
    }

    // ── Hex number  0x… ───────────────────────────────────────────────────
    if (ch == 0x30 && _peek(1) == 0x78) {
      _pos += 2;
      while (_pos < source.length && _isHexDigit(_cu(_pos))) _pos++;
      // optional underscores (0x1_000)
      while (_pos < source.length && _cu(_pos) == 0x5F) {
        _pos++;
        while (_pos < source.length && _isHexDigit(_cu(_pos))) _pos++;
      }
      return _tokLex(TokenKind.NumberLiteral, start);
    }

    // ── Decimal numbers ────────────────────────────────────────────────────
    if (_isDigit(ch)) {
      _scanDecimalDigits();
      if (_pos < source.length &&
          _cu(_pos) == 0x2E /* . */ &&
          _pos + 1 < source.length &&
          _isDigit(_cu(_pos + 1))) {
        _pos++;
        _scanDecimalDigits();
      }
      if (_pos < source.length &&
          (_cu(_pos) == 0x65 /* e */ || _cu(_pos) == 0x45 /* E */ )) {
        _pos++;
        if (_pos < source.length &&
            (_cu(_pos) == 0x2B /* + */ || _cu(_pos) == 0x2D /* - */ )) {
          _pos++;
        }
        _scanDecimalDigits();
      }
      return _tokLex(TokenKind.NumberLiteral, start);
    }

    // ── Identifiers & keywords ────────────────────────────────────────────
    if (_isIdentStart(ch)) {
      while (_pos < source.length && _isIdentCont(_cu(_pos))) _pos++;
      final text = source.substring(start, _pos);
      final kind = keywordOrIdentifier(text);
      int width = 0;
      if (kind == TokenKind.UintN) width = int.parse(text.substring(4));
      if (kind == TokenKind.IntN) width = int.parse(text.substring(3));
      if (kind == TokenKind.BytesN) width = int.parse(text.substring(5));
      return Token(
        kind: kind,
        location: _loc(start, _pos - start),
        lexeme: text,
        intWidth: width,
      );
    }

    // ── Punctuation & operators ────────────────────────────────────────────
    _pos++;
    switch (ch) {
      case 0x28:
        return _tok(TokenKind.LParen, start, 1);
      case 0x29:
        return _tok(TokenKind.RParen, start, 1);
      case 0x5B:
        return _tok(TokenKind.LBracket, start, 1);
      case 0x5D:
        return _tok(TokenKind.RBracket, start, 1);
      case 0x7B:
        return _tok(TokenKind.LBrace, start, 1);
      case 0x7D:
        return _tok(TokenKind.RBrace, start, 1);
      case 0x3B:
        return _tok(TokenKind.Semicolon, start, 1);
      case 0x2C:
        return _tok(TokenKind.Comma, start, 1);
      case 0x7E:
        return _tok(TokenKind.Tilde, start, 1);
      case 0x3F:
        return _tok(TokenKind.Question, start, 1);

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

      case 0x2F: // / (not comment — comments handled above)
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
        if (_peek(0) == 0x2E && _peek(1) == 0x2E) {
          _pos += 2;
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

  // ── Internal helpers ──────────────────────────────────────────────────────

  Token _scanString(
    int start,
    int quote, {
    TokenKind kind = TokenKind.StringLiteral,
  }) {
    _pos++; // consume opening quote
    while (_pos < source.length) {
      final c = _cu(_pos++);
      if (c == 0x5C /* \ */ ) {
        if (_pos < source.length) _pos++; // skip escape
      } else if (c == quote) {
        break;
      }
    }
    return _tokLex(kind, start);
  }

  void _scanDecimalDigits() {
    while (_pos < source.length && (_isDigit(_cu(_pos)) || _cu(_pos) == 0x5F)) {
      _pos++;
    }
  }

  /// Tries to match [prefix] at [_pos]. On success advances [_pos] past it.
  bool _matchPrefix(String prefix) {
    if (_pos + prefix.length > source.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (source.codeUnitAt(_pos + i) != prefix.codeUnitAt(i)) return false;
    }
    _pos += prefix.length;
    return true;
  }

  bool _consume(int code) {
    if (_pos < source.length && _cu(_pos) == code) {
      _pos++;
      return true;
    }
    return false;
  }

  int _cu(int pos) => source.codeUnitAt(pos);
  int _peek(int offset) {
    final i = _pos + offset;
    return i < source.length ? _cu(i) : -1;
  }

  Token _tok(TokenKind kind, int start, int length) => Token(
    kind: kind,
    location: _loc(start, length),
    lexeme: source.substring(start, start + length),
  );

  Token _tokLex(TokenKind kind, int start) => Token(
    kind: kind,
    location: _loc(start, _pos - start),
    lexeme: source.substring(start, _pos),
  );

  SourceLocation _loc(int start, int length) =>
      SourceLocation(sourceIndex: sourceIndex, offset: start, length: length);

  static bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isHexDigit(int c) =>
      _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _isIdentCont(int c) => _isIdentStart(c) || _isDigit(c);
}
