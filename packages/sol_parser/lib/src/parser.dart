import 'package:sol_ast/sol_ast.dart';
import 'package:sol_lexer/sol_lexer.dart';
import 'package:sol_support/sol_support.dart';

/// Recursive-descent parser: token list → [SourceFile] AST.
///
/// The parser is intentionally straightforward — one method per grammar rule,
/// no backtracking.  Errors are reported to [diagnostics] and parsing
/// continues where possible (error recovery via synchronisation).
class Parser {
  Parser({
    required this.tokens,
    required this.sourceIndex,
    required this.diagnostics,
  });

  final List<Token> tokens;
  final int sourceIndex;
  final DiagnosticCollector diagnostics;

  int _pos = 0;

  Token get _current => _pos < tokens.length ? tokens[_pos] : _eof;
  Token get _eof => Token(
        kind: TokenKind.Eof,
        location: SourceLocation(sourceIndex: sourceIndex, offset: 0, length: 0),
      );

  // ── Public entry point ────────────────────────────────────────────────────

  SourceFile parse() {
    final start = _current.location;
    final pragmas = <PragmaDirective>[];
    final imports = <ImportDirective>[];
    final contracts = <ContractDefinition>[];

    while (!_isEof) {
      if (_check(TokenKind.kPragma)) {
        pragmas.add(_parsePragma());
      } else if (_check(TokenKind.kImport)) {
        imports.add(_parseImport());
      } else if (_checkAny([
        TokenKind.kContract,
        TokenKind.kInterface,
        TokenKind.kLibrary,
        TokenKind.kAbstract,
      ])) {
        contracts.add(_parseContractDefinition());
      } else {
        diagnostics.error(
          'Unexpected token "${_current.lexeme}" at top level',
          location: _current.location,
        );
        _advance();
      }
    }

    return SourceFile(_locFrom(start), pragmas, imports, contracts);
  }

  // ── Pragmas & imports ─────────────────────────────────────────────────────

  PragmaDirective _parsePragma() {
    final start = _expect(TokenKind.kPragma).location;
    final literals = <String>[];
    while (!_check(TokenKind.Semicolon) && !_isEof) {
      literals.add(_current.lexeme.isEmpty
          ? _current.kind.name
          : _current.lexeme);
      _advance();
    }
    _expect(TokenKind.Semicolon);
    return PragmaDirective(_locFrom(start), literals);
  }

  ImportDirective _parseImport() {
    final start = _expect(TokenKind.kImport).location;
    String path;
    String? alias;
    final symbolAliases = <String, String?>{};

    if (_check(TokenKind.StringLiteral)) {
      path = _advance().lexeme;
      if (_tryConsume(TokenKind.kAs)) {
        alias = _expectIdentifier();
      }
    } else if (_check(TokenKind.Star)) {
      _advance();
      _expect(TokenKind.kAs);
      alias = _expectIdentifier();
      _expect(TokenKind.kFrom);
      path = _advance().lexeme;
    } else if (_check(TokenKind.LBrace)) {
      _advance();
      while (!_check(TokenKind.RBrace) && !_isEof) {
        final sym = _expectIdentifier();
        String? symAlias;
        if (_tryConsume(TokenKind.kAs)) symAlias = _expectIdentifier();
        symbolAliases[sym] = symAlias;
        if (!_tryConsume(TokenKind.Comma)) break;
      }
      _expect(TokenKind.RBrace);
      _expect(TokenKind.kFrom);
      path = _advance().lexeme;
    } else {
      diagnostics.error('Expected import path', location: _current.location);
      path = '';
    }

    _expect(TokenKind.Semicolon);
    return ImportDirective(_locFrom(start), path, alias, symbolAliases);
  }

  // ── Contract ──────────────────────────────────────────────────────────────

  ContractDefinition _parseContractDefinition() {
    final start = _current.location;
    _tryConsume(TokenKind.kAbstract);
    final kindTok = _advance();
    final kind = switch (kindTok.kind) {
      TokenKind.kInterface => ContractKind.interface,
      TokenKind.kLibrary => ContractKind.library,
      _ => ContractKind.contract,
    };
    final name = _expectIdentifier();
    final bases = <InheritanceSpecifier>[];
    if (_tryConsume(TokenKind.kIs)) {
      do {
        final baseName = _expectIdentifier();
        final args = <Expression>[];
        if (_tryConsume(TokenKind.LParen)) {
          while (!_check(TokenKind.RParen) && !_isEof) {
            args.add(_parseExpression());
            if (!_tryConsume(TokenKind.Comma)) break;
          }
          _expect(TokenKind.RParen);
        }
        bases.add(InheritanceSpecifier(_locFrom(start), baseName, args));
      } while (_tryConsume(TokenKind.Comma));
    }

    _expect(TokenKind.LBrace);
    final members = <AstNode>[];
    while (!_check(TokenKind.RBrace) && !_isEof) {
      members.add(_parseContractMember());
    }
    _expect(TokenKind.RBrace);
    return ContractDefinition(_locFrom(start), kind, name, bases, members);
  }

  AstNode _parseContractMember() {
    if (_check(TokenKind.kFunction) ||
        _check(TokenKind.kConstructor) ||
        _check(TokenKind.kFallback) ||
        _check(TokenKind.kReceive)) {
      return _parseFunctionDefinition();
    }
    if (_check(TokenKind.kModifier)) return _parseModifierDefinition();
    if (_check(TokenKind.kEvent)) return _parseEventDefinition();
    if (_check(TokenKind.kError)) return _parseCustomErrorDefinition();
    if (_check(TokenKind.kStruct)) return _parseStructDefinition();
    if (_check(TokenKind.kEnum)) return _parseEnumDefinition();
    return _parseStateVariableDeclaration();
  }

  // ── Function definition ───────────────────────────────────────────────────

  FunctionDefinition _parseFunctionDefinition() {
    final start = _current.location;
    String? name;
    if (_tryConsume(TokenKind.kFunction)) {
      if (!_checkAny([TokenKind.LParen, TokenKind.kFallback, TokenKind.kReceive])) {
        name = _expectIdentifier();
      }
    } else {
      _advance(); // constructor / fallback / receive
    }

    _expect(TokenKind.LParen);
    final params = _parseParameterList();
    _expect(TokenKind.RParen);

    var visibility = Visibility.defaultVisibility;
    var mutability = StateMutability.nonpayable;
    var isVirtual = false;
    final overrides = <String>[];
    final modifiers = <ModifierInvocation>[];

    // parse specifiers
    loop:
    while (true) {
      switch (_current.kind) {
        case TokenKind.kPublic:
          visibility = Visibility.public;
          _advance();
        case TokenKind.kPrivate:
          visibility = Visibility.private;
          _advance();
        case TokenKind.kInternal:
          visibility = Visibility.internal;
          _advance();
        case TokenKind.kExternal:
          visibility = Visibility.external;
          _advance();
        case TokenKind.kPure:
          mutability = StateMutability.pure;
          _advance();
        case TokenKind.kView:
          mutability = StateMutability.view;
          _advance();
        case TokenKind.kPayable:
          mutability = StateMutability.payable;
          _advance();
        case TokenKind.kVirtual:
          isVirtual = true;
          _advance();
        case TokenKind.kOverride:
          _advance();
          if (_tryConsume(TokenKind.LParen)) {
            while (!_check(TokenKind.RParen) && !_isEof) {
              overrides.add(_expectIdentifier());
              if (!_tryConsume(TokenKind.Comma)) break;
            }
            _expect(TokenKind.RParen);
          }
        case TokenKind.Identifier:
          final name2 = _current.lexeme;
          _advance();
          final args = <Expression>[];
          if (_tryConsume(TokenKind.LParen)) {
            while (!_check(TokenKind.RParen) && !_isEof) {
              args.add(_parseExpression());
              if (!_tryConsume(TokenKind.Comma)) break;
            }
            _expect(TokenKind.RParen);
          }
          modifiers.add(ModifierInvocation(_current.location, name2, args));
        default:
          break loop;
      }
    }

    List<Parameter> returnParams = [];
    if (_tryConsume(TokenKind.kReturns)) {
      _expect(TokenKind.LParen);
      returnParams = _parseParameterList();
      _expect(TokenKind.RParen);
    }

    Block? body;
    if (_check(TokenKind.LBrace)) {
      body = _parseBlock();
    } else {
      _expect(TokenKind.Semicolon);
    }

    return FunctionDefinition(
      location: _locFrom(start),
      name: name,
      parameters: params,
      returnParameters: returnParams,
      visibility: visibility,
      stateMutability: mutability,
      isVirtual: isVirtual,
      overrideSpecifier: overrides,
      modifiers: modifiers,
      body: body,
    );
  }

  List<Parameter> _parseParameterList() {
    final params = <Parameter>[];
    if (_check(TokenKind.RParen)) return params;
    do {
      final pStart = _current.location;
      final type = _parseTypeName();
      DataLocation? loc2;
      if (_check(TokenKind.kStorage)) {
        loc2 = DataLocation.storage;
        _advance();
      } else if (_check(TokenKind.kMemory)) {
        loc2 = DataLocation.memory;
        _advance();
      } else if (_check(TokenKind.kCalldata)) {
        loc2 = DataLocation.calldata;
        _advance();
      }
      String? pName;
      if (_check(TokenKind.Identifier)) pName = _advance().lexeme;
      params.add(Parameter(_locFrom(pStart), type, pName, loc2));
    } while (_tryConsume(TokenKind.Comma));
    return params;
  }

  // ── Modifier ──────────────────────────────────────────────────────────────

  ModifierDefinition _parseModifierDefinition() {
    final start = _expect(TokenKind.kModifier).location;
    final name = _expectIdentifier();
    _expect(TokenKind.LParen);
    final params = _parseParameterList();
    _expect(TokenKind.RParen);
    // skip virtual/override
    while (_checkAny([TokenKind.kVirtual, TokenKind.kOverride])) _advance();
    final body = _parseBlock();
    return ModifierDefinition(_locFrom(start), name, params, body);
  }

  // ── Event / Error ─────────────────────────────────────────────────────────

  EventDefinition _parseEventDefinition() {
    final start = _expect(TokenKind.kEvent).location;
    final name = _expectIdentifier();
    _expect(TokenKind.LParen);
    final params = _parseParameterList();
    _expect(TokenKind.RParen);
    final anon = _tryConsume(TokenKind.kPure); // anonymous keyword
    _expect(TokenKind.Semicolon);
    return EventDefinition(_locFrom(start), name, params, anon);
  }

  CustomErrorDefinition _parseCustomErrorDefinition() {
    final start = _expect(TokenKind.kError).location;
    final name = _expectIdentifier();
    _expect(TokenKind.LParen);
    final params = _parseParameterList();
    _expect(TokenKind.RParen);
    _expect(TokenKind.Semicolon);
    return CustomErrorDefinition(_locFrom(start), name, params);
  }

  // ── Struct / Enum ─────────────────────────────────────────────────────────

  StructDefinition _parseStructDefinition() {
    final start = _expect(TokenKind.kStruct).location;
    final name = _expectIdentifier();
    _expect(TokenKind.LBrace);
    final members = <VariableDeclaration>[];
    while (!_check(TokenKind.RBrace) && !_isEof) {
      final mStart = _current.location;
      final type = _parseTypeName();
      final mName = _expectIdentifier();
      _expect(TokenKind.Semicolon);
      members.add(VariableDeclaration(_locFrom(mStart), type, mName, null));
    }
    _expect(TokenKind.RBrace);
    return StructDefinition(_locFrom(start), name, members);
  }

  EnumDefinition _parseEnumDefinition() {
    final start = _expect(TokenKind.kEnum).location;
    final name = _expectIdentifier();
    _expect(TokenKind.LBrace);
    final values = <String>[];
    while (!_check(TokenKind.RBrace) && !_isEof) {
      values.add(_expectIdentifier());
      if (!_tryConsume(TokenKind.Comma)) break;
    }
    _expect(TokenKind.RBrace);
    return EnumDefinition(_locFrom(start), name, values);
  }

  // ── State variable ────────────────────────────────────────────────────────

  StateVariableDeclaration _parseStateVariableDeclaration() {
    final start = _current.location;
    final type = _parseTypeName();
    var visibility = Visibility.internal;
    var mutability = VariableMutability.mutable;

    loop:
    while (true) {
      switch (_current.kind) {
        case TokenKind.kPublic:
          visibility = Visibility.public;
          _advance();
        case TokenKind.kPrivate:
          visibility = Visibility.private;
          _advance();
        case TokenKind.kInternal:
          visibility = Visibility.internal;
          _advance();
        case TokenKind.kImmutable:
          mutability = VariableMutability.immutable;
          _advance();
        case TokenKind.kConstant:
          mutability = VariableMutability.constant;
          _advance();
        default:
          break loop;
      }
    }

    final name = _expectIdentifier();
    Expression? init;
    if (_tryConsume(TokenKind.Eq)) init = _parseExpression();
    _expect(TokenKind.Semicolon);
    return StateVariableDeclaration(
        _locFrom(start), type, name, visibility, mutability, init);
  }

  // ── Statements ────────────────────────────────────────────────────────────

  Block _parseBlock() {
    final start = _expect(TokenKind.LBrace).location;
    final stmts = <Statement>[];
    while (!_check(TokenKind.RBrace) && !_isEof) {
      stmts.add(_parseStatement());
    }
    _expect(TokenKind.RBrace);
    return Block(_locFrom(start), stmts);
  }

  Statement _parseStatement() {
    switch (_current.kind) {
      case TokenKind.LBrace:
        return _parseBlock();
      case TokenKind.kReturn:
        return _parseReturn();
      case TokenKind.kIf:
        return _parseIf();
      case TokenKind.kWhile:
        return _parseWhile();
      case TokenKind.kFor:
        return _parseFor();
      case TokenKind.kDo:
        return _parseDo();
      case TokenKind.kBreak:
        final s = _advance().location;
        _expect(TokenKind.Semicolon);
        return BreakStatement(_locFrom(s));
      case TokenKind.kContinue:
        final s = _advance().location;
        _expect(TokenKind.Semicolon);
        return ContinueStatement(_locFrom(s));
      case TokenKind.kEmit:
        return _parseEmit();
      case TokenKind.kRevert:
        return _parseRevert();
      case TokenKind.kAssembly:
        return _parseAssembly();
      default:
        return _parseExpressionOrDeclarationStatement();
    }
  }

  ReturnStatement _parseReturn() {
    final start = _expect(TokenKind.kReturn).location;
    Expression? expr;
    if (!_check(TokenKind.Semicolon)) expr = _parseExpression();
    _expect(TokenKind.Semicolon);
    return ReturnStatement(_locFrom(start), expr);
  }

  IfStatement _parseIf() {
    final start = _expect(TokenKind.kIf).location;
    _expect(TokenKind.LParen);
    final cond = _parseExpression();
    _expect(TokenKind.RParen);
    final then = _parseStatement();
    Statement? els;
    if (_tryConsume(TokenKind.kElse)) els = _parseStatement();
    return IfStatement(_locFrom(start), cond, then, els);
  }

  WhileStatement _parseWhile() {
    final start = _expect(TokenKind.kWhile).location;
    _expect(TokenKind.LParen);
    final cond = _parseExpression();
    _expect(TokenKind.RParen);
    return WhileStatement(_locFrom(start), cond, _parseStatement());
  }

  ForStatement _parseFor() {
    final start = _expect(TokenKind.kFor).location;
    _expect(TokenKind.LParen);
    Statement? init;
    if (!_check(TokenKind.Semicolon)) init = _parseStatement();
    else _expect(TokenKind.Semicolon);
    Expression? cond;
    if (!_check(TokenKind.Semicolon)) cond = _parseExpression();
    _expect(TokenKind.Semicolon);
    ExpressionStatement? loop2;
    if (!_check(TokenKind.RParen)) {
      final e = _parseExpression();
      loop2 = ExpressionStatement(e.location, e);
    }
    _expect(TokenKind.RParen);
    return ForStatement(_locFrom(start), init, cond, loop2, _parseStatement());
  }

  DoWhileStatement _parseDo() {
    final start = _expect(TokenKind.kDo).location;
    final body = _parseStatement();
    _expect(TokenKind.kWhile);
    _expect(TokenKind.LParen);
    final cond = _parseExpression();
    _expect(TokenKind.RParen);
    _expect(TokenKind.Semicolon);
    return DoWhileStatement(_locFrom(start), body, cond);
  }

  EmitStatement _parseEmit() {
    final start = _expect(TokenKind.kEmit).location;
    final call = _parseExpression();
    _expect(TokenKind.Semicolon);
    return EmitStatement(_locFrom(start), call);
  }

  RevertStatement _parseRevert() {
    final start = _expect(TokenKind.kRevert).location;
    final expr = _parseExpression();
    _expect(TokenKind.Semicolon);
    return RevertStatement(_locFrom(start), expr);
  }

  AssemblyStatement _parseAssembly() {
    final start = _expect(TokenKind.kAssembly).location;
    String? dialect;
    if (_check(TokenKind.StringLiteral)) dialect = _advance().lexeme;
    _expect(TokenKind.LBrace);
    final buf = StringBuffer();
    var depth = 1;
    while (!_isEof && depth > 0) {
      if (_check(TokenKind.LBrace)) depth++;
      if (_check(TokenKind.RBrace)) {
        depth--;
        if (depth == 0) break;
      }
      buf.write(_current.lexeme.isEmpty ? _current.kind.name : _current.lexeme);
      buf.write(' ');
      _advance();
    }
    _expect(TokenKind.RBrace);
    return AssemblyStatement(_locFrom(start), dialect, buf.toString().trim());
  }

  Statement _parseExpressionOrDeclarationStatement() {
    final start = _current.location;
    // Heuristic: if it looks like a type name, try variable declaration.
    if (_looksLikeTypeName()) {
      final type = _parseTypeName();
      DataLocation? dataLoc;
      if (_check(TokenKind.kStorage)) {
        dataLoc = DataLocation.storage; _advance();
      } else if (_check(TokenKind.kMemory)) {
        dataLoc = DataLocation.memory; _advance();
      } else if (_check(TokenKind.kCalldata)) {
        dataLoc = DataLocation.calldata; _advance();
      }
      final decl = VariableDeclaration(_locFrom(start), type, _expectIdentifier(), dataLoc);
      Expression? init;
      if (_tryConsume(TokenKind.Eq)) init = _parseExpression();
      _expect(TokenKind.Semicolon);
      return VariableDeclarationStatement(_locFrom(start), [decl], init);
    }
    final expr = _parseExpression();
    _expect(TokenKind.Semicolon);
    return ExpressionStatement(_locFrom(start), expr);
  }

  // ── Expressions ───────────────────────────────────────────────────────────

  Expression _parseExpression() => _parseAssignment();

  Expression _parseAssignment() {
    final left = _parseTernary();
    const assignOps = {
      TokenKind.Eq, TokenKind.PlusEq, TokenKind.MinusEq, TokenKind.StarEq,
      TokenKind.SlashEq, TokenKind.PercentEq, TokenKind.AmpEq,
      TokenKind.PipeEq, TokenKind.CaretEq, TokenKind.LtLtEq,
      TokenKind.GtGtEq, TokenKind.GtGtGtEq,
    };
    if (assignOps.contains(_current.kind)) {
      final op = _advance().lexeme;
      final right = _parseAssignment();
      return Assignment(left.location.combine(right.location), op, left, right);
    }
    return left;
  }

  Expression _parseTernary() {
    final cond = _parseOr();
    if (_tryConsume(TokenKind.Question)) {
      final t = _parseExpression();
      _expect(TokenKind.Colon);
      final f = _parseExpression();
      return Conditional(cond.location.combine(f.location), cond, t, f);
    }
    return cond;
  }

  Expression _parseBinary(List<Set<TokenKind>> precedence, int level,
      Expression Function() next) {
    if (level >= precedence.length) return next();
    var left = _parseBinary(precedence, level + 1, next);
    while (precedence[level].contains(_current.kind)) {
      final op = _advance().lexeme;
      final right = _parseBinary(precedence, level + 1, next);
      left = BinaryOperation(left.location.combine(right.location), op, left, right);
    }
    return left;
  }

  static const _binaryPrecedence = [
    {TokenKind.PipePipe},
    {TokenKind.AmpAmp},
    {TokenKind.Pipe},
    {TokenKind.Caret},
    {TokenKind.Ampersand},
    {TokenKind.EqEq, TokenKind.BangEq},
    {TokenKind.Lt, TokenKind.LtEq, TokenKind.Gt, TokenKind.GtEq},
    {TokenKind.LtLt, TokenKind.GtGt, TokenKind.GtGtGt},
    {TokenKind.Plus, TokenKind.Minus},
    {TokenKind.Star, TokenKind.Slash, TokenKind.Percent},
    {TokenKind.StarStar},
  ];

  Expression _parseOr() =>
      _parseBinary(_binaryPrecedence, 0, _parseUnary);

  Expression _parseUnary() {
    final start = _current.location;
    switch (_current.kind) {
      case TokenKind.Bang:
      case TokenKind.Tilde:
      case TokenKind.Minus:
        final op = _advance().lexeme;
        final sub = _parseUnary();
        return UnaryOperation(_locFrom(start), op, sub, true);
      case TokenKind.PlusPlus:
      case TokenKind.MinusMinus:
        final op = _advance().lexeme;
        final sub = _parseUnary();
        return UnaryOperation(_locFrom(start), op, sub, true);
      default:
        return _parsePostfix();
    }
  }

  Expression _parsePostfix() {
    var expr = _parsePrimary();
    loop:
    while (true) {
      switch (_current.kind) {
        case TokenKind.Dot:
          _advance();
          final member = _expectIdentifier();
          expr = MemberAccess(expr.location, expr, member);
        case TokenKind.LBracket:
          _advance();
          Expression? idx;
          if (!_check(TokenKind.RBracket)) idx = _parseExpression();
          _expect(TokenKind.RBracket);
          expr = IndexAccess(expr.location, expr, idx);
        case TokenKind.LParen:
          _advance();
          final args = <Expression>[];
          final names = <String?>[];
          while (!_check(TokenKind.RParen) && !_isEof) {
            // named argument
            if (_check(TokenKind.Identifier) && _peekKind(1) == TokenKind.Colon) {
              names.add(_advance().lexeme);
              _advance(); // :
            } else {
              names.add(null);
            }
            args.add(_parseExpression());
            if (!_tryConsume(TokenKind.Comma)) break;
          }
          _expect(TokenKind.RParen);
          expr = FunctionCall(expr.location, expr, args, names);
        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
          final op = _advance().lexeme;
          expr = UnaryOperation(expr.location, op, expr, false);
        default:
          break loop;
      }
    }
    return expr;
  }

  Expression _parsePrimary() {
    final start = _current.location;
    switch (_current.kind) {
      case TokenKind.NumberLiteral:
        final val = _advance().lexeme;
        String? sub;
        if (_checkAny([
          TokenKind.kWei, TokenKind.kGwei, TokenKind.kEther,
          TokenKind.kSeconds, TokenKind.kMinutes, TokenKind.kHours,
          TokenKind.kDays, TokenKind.kWeeks,
        ])) {
          sub = _advance().lexeme;
        }
        return Literal(_locFrom(start), LiteralKind.number, val, sub);

      case TokenKind.StringLiteral:
        return Literal(_locFrom(start), LiteralKind.string, _advance().lexeme, null);

      case TokenKind.UnicodeStringLiteral:
        return Literal(_locFrom(start), LiteralKind.unicodeString, _advance().lexeme, null);

      case TokenKind.HexStringLiteral:
        return Literal(_locFrom(start), LiteralKind.hexString, _advance().lexeme, null);

      case TokenKind.TrueLiteral:
        _advance();
        return Literal(_locFrom(start), LiteralKind.bool$, 'true', null);

      case TokenKind.FalseLiteral:
        _advance();
        return Literal(_locFrom(start), LiteralKind.bool$, 'false', null);

      case TokenKind.kThis:
        _advance();
        return Identifier(_locFrom(start), 'this');

      case TokenKind.kSuper:
        _advance();
        return Identifier(_locFrom(start), 'super');

      case TokenKind.LParen:
        _advance();
        if (_check(TokenKind.RParen)) {
          _advance();
          return TupleExpression(_locFrom(start), [], false);
        }
        final expr = _parseExpression();
        if (_tryConsume(TokenKind.Comma)) {
          final components = <Expression?>[expr];
          while (!_check(TokenKind.RParen) && !_isEof) {
            if (_check(TokenKind.Comma)) {
              components.add(null);
            } else {
              components.add(_parseExpression());
            }
            if (!_tryConsume(TokenKind.Comma)) break;
          }
          _expect(TokenKind.RParen);
          return TupleExpression(_locFrom(start), components, false);
        }
        _expect(TokenKind.RParen);
        return expr;

      case TokenKind.kNew:
        _advance();
        final type = _parseTypeName();
        return NewExpression(_locFrom(start), type);

      case TokenKind.Identifier:
        return Identifier(_locFrom(start), _advance().lexeme);

      default:
        if (_looksLikeTypeName()) {
          final type = _parseTypeName();
          _expect(TokenKind.LParen);
          final inner = _parseExpression();
          _expect(TokenKind.RParen);
          return TypeConversion(_locFrom(start), type, inner);
        }
        diagnostics.error(
          'Expected expression, got "${_current.kind.name}"',
          location: _current.location,
        );
        _advance();
        return Literal(_locFrom(start), LiteralKind.number, '0', null);
    }
  }

  // ── Type names ────────────────────────────────────────────────────────────

  TypeName _parseTypeName() {
    final start = _current.location;
    TypeName base;

    if (_check(TokenKind.kMapping)) {
      base = _parseMapping();
    } else if (_check(TokenKind.kFunction)) {
      base = _parseFunctionTypeName();
    } else if (_isElementaryType(_current.kind)) {
      final name = _current.lexeme.isEmpty ? _current.kind.name : _current.lexeme;
      final width = _current.intWidth;
      _advance();
      base = ElementaryTypeName(_locFrom(start), name, intWidth: width);
    } else {
      final parts = [_expectIdentifier()];
      while (_check(TokenKind.Dot)) {
        _advance();
        parts.add(_expectIdentifier());
      }
      base = UserDefinedTypeName(_locFrom(start), parts);
    }

    while (_check(TokenKind.LBracket)) {
      _advance();
      Expression? len;
      if (!_check(TokenKind.RBracket)) len = _parseExpression();
      _expect(TokenKind.RBracket);
      base = ArrayTypeName(_locFrom(start), base, len);
    }

    return base;
  }

  MappingTypeName _parseMapping() {
    final start = _expect(TokenKind.kMapping).location;
    _expect(TokenKind.LParen);
    final key = _parseTypeName();
    _expect(TokenKind.Arrow);
    final value = _parseTypeName();
    _expect(TokenKind.RParen);
    return MappingTypeName(_locFrom(start), key, value);
  }

  FunctionTypeName _parseFunctionTypeName() {
    final start = _expect(TokenKind.kFunction).location;
    _expect(TokenKind.LParen);
    final params = _parseParameterList();
    _expect(TokenKind.RParen);
    var vis = Visibility.internal;
    var mut = StateMutability.nonpayable;
    while (true) {
      if (_checkAny([TokenKind.kPublic, TokenKind.kExternal,
          TokenKind.kInternal, TokenKind.kPrivate])) {
        vis = _visibilityFrom(_advance().kind);
      } else if (_checkAny([TokenKind.kPure, TokenKind.kView, TokenKind.kPayable])) {
        mut = _mutabilityFrom(_advance().kind);
      } else break;
    }
    var returnParams = <Parameter>[];
    if (_tryConsume(TokenKind.kReturns)) {
      _expect(TokenKind.LParen);
      returnParams = _parseParameterList();
      _expect(TokenKind.RParen);
    }
    return FunctionTypeName(_locFrom(start), params, returnParams, mut, vis);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _isEof => _current.kind == TokenKind.Eof;

  bool _check(TokenKind kind) => _current.kind == kind;

  bool _checkAny(List<TokenKind> kinds) => kinds.contains(_current.kind);

  Token _advance() {
    final t = _current;
    if (_pos < tokens.length) _pos++;
    return t;
  }

  Token _expect(TokenKind kind) {
    if (_current.kind == kind) return _advance();
    diagnostics.error(
      'Expected ${kind.name}, got ${_current.kind.name}',
      location: _current.location,
    );
    return _current;
  }

  bool _tryConsume(TokenKind kind) {
    if (_current.kind == kind) {
      _advance();
      return true;
    }
    return false;
  }

  String _expectIdentifier() {
    if (_check(TokenKind.Identifier)) return _advance().lexeme;
    // Some keywords are also valid identifiers in certain positions.
    if (_current.lexeme.isNotEmpty) return _advance().lexeme;
    diagnostics.error('Expected identifier', location: _current.location);
    return '';
  }

  TokenKind _peekKind(int offset) {
    final i = _pos + offset;
    return i < tokens.length ? tokens[i].kind : TokenKind.Eof;
  }

  SourceLocation _locFrom(SourceLocation start) =>
      start.combine(_current.location);

  bool _looksLikeTypeName() => _isElementaryType(_current.kind) ||
      _check(TokenKind.kMapping) ||
      _check(TokenKind.kFunction) ||
      (_check(TokenKind.Identifier) &&
          (_peekKind(1) == TokenKind.Dot ||
              _peekKind(1) == TokenKind.LBracket ||
              _peekKind(1) == TokenKind.Identifier));

  static bool _isElementaryType(TokenKind k) => const {
        TokenKind.kAddress,
        TokenKind.kBool,
        TokenKind.kString,
        TokenKind.kBytes,
        TokenKind.kInt,
        TokenKind.kUint,
        TokenKind.IntN,
        TokenKind.UintN,
        TokenKind.BytesN,
      }.contains(k);

  static Visibility _visibilityFrom(TokenKind k) => switch (k) {
        TokenKind.kPublic => Visibility.public,
        TokenKind.kPrivate => Visibility.private,
        TokenKind.kExternal => Visibility.external,
        _ => Visibility.internal,
      };

  static StateMutability _mutabilityFrom(TokenKind k) => switch (k) {
        TokenKind.kPure => StateMutability.pure,
        TokenKind.kView => StateMutability.view,
        TokenKind.kPayable => StateMutability.payable,
        _ => StateMutability.nonpayable,
      };
}
