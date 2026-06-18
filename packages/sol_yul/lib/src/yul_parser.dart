import 'yul_ast.dart';

/// Thrown when Yul source cannot be parsed.
class YulParseException implements Exception {
  YulParseException(this.message, this.position);
  final String message;
  final int position;

  @override
  String toString() => 'YulParseException at $position: $message';
}

/// A recursive-descent parser for the Yul language (and inline-assembly
/// blocks), producing the [YulNode] AST consumed by [YulCodeGenerator].
///
/// Grammar reference: https://docs.soliditylang.org/en/latest/yul.html#specification-of-yul
///
/// Type annotations on typed identifiers and literals (`x : uint256`,
/// `1 : u256`) are accepted and discarded — the code generator treats every
/// value as a 256-bit word.
class YulParser {
  YulParser(String source) : _tokens = _YulLexer(source).tokenize();

  final List<_Token> _tokens;
  int _pos = 0;

  // ── Public entry points ─────────────────────────────────────────────────

  /// Parses a top-level construct: an `object "…" { … }` or a bare block.
  YulNode parse() {
    final node = _peek().isKeyword('object') ? parseObject() : parseBlock();
    _expect(_TokenKind.eof);
    return node;
  }

  /// Parses a single `{ … }` block (the shape of an inline-assembly body).
  YulBlock parseBlock() {
    _expectPunct('{');
    final statements = <YulStatement>[];
    while (!_check(_TokenKind.punct, '}') && !_check(_TokenKind.eof)) {
      statements.add(_parseStatement());
    }
    _expectPunct('}');
    return YulBlock(statements);
  }

  /// Parses an `object "name" { code { … } <sub-objects> <data> }`.
  YulObject parseObject() {
    _expectKeyword('object');
    final name = _expect(_TokenKind.string).value;
    _expectPunct('{');
    _expectKeyword('code');
    final code = parseBlock();

    final subObjects = <YulObject>[];
    final data = <String, List<int>>{};
    while (!_check(_TokenKind.punct, '}') && !_check(_TokenKind.eof)) {
      if (_peek().isKeyword('object')) {
        subObjects.add(parseObject());
      } else if (_peek().isKeyword('data')) {
        _advance();
        final dataName = _expect(_TokenKind.string).value;
        final tok = _advance();
        if (tok.kind == _TokenKind.hexString) {
          data[dataName] = _hexToBytes(tok.value);
        } else if (tok.kind == _TokenKind.string) {
          data[dataName] = tok.value.codeUnits;
        } else {
          throw _error('expected string or hex literal after data "$dataName"');
        }
      } else {
        throw _error('unexpected token "${_peek().value}" in object body');
      }
    }
    _expectPunct('}');
    return YulObject(name, code, subObjects, data);
  }

  // ── Statements ──────────────────────────────────────────────────────────

  YulStatement _parseStatement() {
    final tok = _peek();
    if (tok.kind == _TokenKind.punct && tok.value == '{') return parseBlock();
    if (tok.kind == _TokenKind.keyword) {
      switch (tok.value) {
        case 'let':
          return _parseVariableDeclaration();
        case 'function':
          return _parseFunctionDefinition();
        case 'if':
          return _parseIf();
        case 'switch':
          return _parseSwitch();
        case 'for':
          return _parseForLoop();
        case 'break':
          _advance();
          return YulBreak();
        case 'continue':
          _advance();
          return YulContinue();
        case 'leave':
          _advance();
          return YulLeave();
      }
    }
    // Identifier: either an assignment (`a := …`, `a, b := …`) or a function
    // call used as an expression statement.
    if (tok.kind == _TokenKind.identifier) {
      if (_peekAt(1).isPunct('(')) {
        return YulExpressionStatement(_parseExpression());
      }
      return _parseAssignment();
    }
    throw _error('unexpected token "${tok.value}"');
  }

  YulVariableDeclaration _parseVariableDeclaration() {
    _expectKeyword('let');
    final names = _parseTypedIdentifierList();
    YulExpression? value;
    if (_check(_TokenKind.assign)) {
      _advance();
      value = _parseExpression();
    }
    return YulVariableDeclaration(names, value);
  }

  YulAssignment _parseAssignment() {
    final names = <String>[_expect(_TokenKind.identifier).value];
    while (_check(_TokenKind.punct, ',')) {
      _advance();
      names.add(_expect(_TokenKind.identifier).value);
    }
    _expect(_TokenKind.assign);
    return YulAssignment(names, _parseExpression());
  }

  YulFunctionDefinition _parseFunctionDefinition() {
    _expectKeyword('function');
    final name = _expect(_TokenKind.identifier).value;
    _expectPunct('(');
    final params = _check(_TokenKind.punct, ')')
        ? <String>[]
        : _parseTypedIdentifierList();
    _expectPunct(')');
    final returns = <String>[];
    if (_check(_TokenKind.arrow)) {
      _advance();
      returns.addAll(_parseTypedIdentifierList());
    }
    final body = parseBlock();
    return YulFunctionDefinition(name, params, returns, body);
  }

  YulIf _parseIf() {
    _expectKeyword('if');
    final cond = _parseExpression();
    final body = parseBlock();
    return YulIf(cond, body);
  }

  YulSwitch _parseSwitch() {
    _expectKeyword('switch');
    final expr = _parseExpression();
    final cases = <YulCase>[];
    YulBlock? defaultCase;
    while (_peek().isKeyword('case') || _peek().isKeyword('default')) {
      if (_peek().isKeyword('case')) {
        _advance();
        final lit = _parseLiteral();
        cases.add(YulCase(lit, parseBlock()));
      } else {
        _advance();
        defaultCase = parseBlock();
        break; // default is always last
      }
    }
    if (cases.isEmpty && defaultCase == null) {
      throw _error('switch requires at least one case or a default');
    }
    return YulSwitch(expr, cases, defaultCase);
  }

  YulForLoop _parseForLoop() {
    _expectKeyword('for');
    final pre = parseBlock();
    final cond = _parseExpression();
    final post = parseBlock();
    final body = parseBlock();
    return YulForLoop(pre, cond, post, body);
  }

  // ── Expressions ─────────────────────────────────────────────────────────

  YulExpression _parseExpression() {
    final tok = _peek();
    switch (tok.kind) {
      case _TokenKind.number:
      case _TokenKind.string:
      case _TokenKind.hexString:
      case _TokenKind.boolean:
        return _parseLiteral();
      case _TokenKind.identifier:
        final name = _advance().value;
        if (_check(_TokenKind.punct, '(')) {
          return YulFunctionCall(name, _parseCallArguments());
        }
        return YulIdentifier(name);
      default:
        throw _error('expected an expression, found "${tok.value}"');
    }
  }

  List<YulExpression> _parseCallArguments() {
    _expectPunct('(');
    final args = <YulExpression>[];
    if (!_check(_TokenKind.punct, ')')) {
      args.add(_parseExpression());
      while (_check(_TokenKind.punct, ',')) {
        _advance();
        args.add(_parseExpression());
      }
    }
    _expectPunct(')');
    return args;
  }

  YulLiteral _parseLiteral() {
    final tok = _advance();
    _skipTypeAnnotation();
    switch (tok.kind) {
      case _TokenKind.number:
        return YulLiteral(tok.value, YulLiteralKind.number);
      case _TokenKind.boolean:
        return YulLiteral(tok.value, YulLiteralKind.bool$);
      case _TokenKind.string:
      case _TokenKind.hexString:
        return YulLiteral(tok.value, YulLiteralKind.string);
      default:
        throw _error('expected a literal, found "${tok.value}"');
    }
  }

  // ── Identifier / type lists ───────────────────────────────────────────────

  /// Parses `id (':' type)? (',' id (':' type)?)*`, discarding type names.
  List<String> _parseTypedIdentifierList() {
    final names = <String>[_expect(_TokenKind.identifier).value];
    _skipTypeAnnotation();
    while (_check(_TokenKind.punct, ',')) {
      _advance();
      names.add(_expect(_TokenKind.identifier).value);
      _skipTypeAnnotation();
    }
    return names;
  }

  void _skipTypeAnnotation() {
    if (_check(_TokenKind.punct, ':')) {
      _advance();
      _expect(_TokenKind.identifier); // the type name
    }
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  _Token _peek() => _tokens[_pos];
  _Token _peekAt(int n) =>
      _pos + n < _tokens.length ? _tokens[_pos + n] : _tokens.last;
  _Token _advance() => _tokens[_pos++];

  bool _check(_TokenKind kind, [String? value]) {
    final t = _peek();
    return t.kind == kind && (value == null || t.value == value);
  }

  _Token _expect(_TokenKind kind) {
    if (_peek().kind != kind) {
      throw _error('expected $kind, found "${_peek().value}"');
    }
    return _advance();
  }

  void _expectPunct(String value) {
    if (!_check(_TokenKind.punct, value)) {
      throw _error('expected "$value", found "${_peek().value}"');
    }
    _advance();
  }

  void _expectKeyword(String value) {
    if (!_peek().isKeyword(value)) {
      throw _error('expected "$value", found "${_peek().value}"');
    }
    _advance();
  }

  YulParseException _error(String message) =>
      YulParseException(message, _peek().position);

  static List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll('_', '');
    final out = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

// ── Lexer ─────────────────────────────────────────────────────────────────

enum _TokenKind {
  identifier,
  keyword,
  number,
  string,
  hexString,
  boolean,
  punct, // { } ( ) , :
  assign, // :=
  arrow, // ->
  eof,
}

class _Token {
  _Token(this.kind, this.value, this.position);
  final _TokenKind kind;
  final String value;
  final int position;

  bool isKeyword(String v) => kind == _TokenKind.keyword && value == v;
  bool isPunct(String v) => kind == _TokenKind.punct && value == v;
}

class _YulLexer {
  _YulLexer(this._src);
  final String _src;
  int _i = 0;

  static const _keywords = {
    'let',
    'function',
    'if',
    'switch',
    'case',
    'default',
    'for',
    'break',
    'continue',
    'leave',
    'object',
    'code',
    'data',
  };

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (true) {
      _skipTrivia();
      if (_i >= _src.length) break;
      tokens.add(_next());
    }
    tokens.add(_Token(_TokenKind.eof, '<eof>', _i));
    return tokens;
  }

  _Token _next() {
    final start = _i;
    final c = _src[_i];

    // hex"…" string literal.
    if ((c == 'h') && _src.startsWith('hex"', _i)) {
      _i += 3;
      return _Token(_TokenKind.hexString, _readQuoted(), start);
    }
    if (c == '"' || c == "'") {
      return _Token(_TokenKind.string, _readQuoted(), start);
    }

    if (_isDigit(c)) return _Token(_TokenKind.number, _readNumber(), start);

    if (_isIdentStart(c)) {
      final word = _readIdentifier();
      if (word == 'true' || word == 'false') {
        return _Token(_TokenKind.boolean, word, start);
      }
      if (_keywords.contains(word)) {
        return _Token(_TokenKind.keyword, word, start);
      }
      return _Token(_TokenKind.identifier, word, start);
    }

    // Multi-char operators.
    if (_src.startsWith(':=', _i)) {
      _i += 2;
      return _Token(_TokenKind.assign, ':=', start);
    }
    if (_src.startsWith('->', _i)) {
      _i += 2;
      return _Token(_TokenKind.arrow, '->', start);
    }

    // Single-char punctuation.
    if ('{}(),:'.contains(c)) {
      _i++;
      return _Token(_TokenKind.punct, c, start);
    }

    throw YulParseException('unexpected character "$c"', start);
  }

  void _skipTrivia() {
    while (_i < _src.length) {
      final c = _src[_i];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        _i++;
      } else if (_src.startsWith('//', _i)) {
        while (_i < _src.length && _src[_i] != '\n') {
          _i++;
        }
      } else if (_src.startsWith('/*', _i)) {
        _i += 2;
        while (_i < _src.length && !_src.startsWith('*/', _i)) {
          _i++;
        }
        _i += 2;
      } else {
        break;
      }
    }
  }

  String _readQuoted() {
    final quote = _src[_i];
    _i++; // opening quote
    final sb = StringBuffer();
    while (_i < _src.length && _src[_i] != quote) {
      if (_src[_i] == r'\' && _i + 1 < _src.length) {
        _i++;
        sb.write(_unescape(_src[_i]));
      } else {
        sb.write(_src[_i]);
      }
      _i++;
    }
    if (_i >= _src.length) {
      throw YulParseException('unterminated string literal', _i);
    }
    _i++; // closing quote
    return sb.toString();
  }

  String _unescape(String c) => switch (c) {
    'n' => '\n',
    't' => '\t',
    'r' => '\r',
    '0' => '\x00',
    _ => c,
  };

  String _readNumber() {
    final start = _i;
    if (_src.startsWith('0x', _i) || _src.startsWith('0X', _i)) {
      _i += 2;
      while (_i < _src.length && _isHex(_src[_i])) {
        _i++;
      }
    } else {
      while (_i < _src.length && (_isDigit(_src[_i]) || _src[_i] == '_')) {
        _i++;
      }
    }
    return _src.substring(start, _i);
  }

  String _readIdentifier() {
    final start = _i;
    while (_i < _src.length && _isIdentPart(_src[_i])) {
      _i++;
    }
    return _src.substring(start, _i);
  }

  static bool _isDigit(String c) =>
      c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  static bool _isHex(String c) =>
      _isDigit(c) ||
      (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('F') <= 0);
  static bool _isIdentStart(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_' ||
      c == r'$';
  static bool _isIdentPart(String c) =>
      _isIdentStart(c) || _isDigit(c) || c == '.';
}
