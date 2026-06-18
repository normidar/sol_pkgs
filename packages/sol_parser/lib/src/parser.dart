import 'package:sol_ast/sol_ast.dart';
import 'package:sol_lexer/sol_lexer.dart';
import 'package:sol_support/sol_support.dart';

/// Recursive-descent Solidity 0.8.x parser.
///
/// Converts a flat token list (from [Lexer]) into a [SourceFile] AST.
/// All errors are reported via [diagnostics]; parsing continues where
/// possible (panic-mode error recovery on synchronisation tokens).
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

  /// When > 0, [_error] suppresses diagnostics (used during [_speculate]).
  int _suppressErrors = 0;

  Token get _cur => _pos < tokens.length ? tokens[_pos] : _eofToken;
  Token get _eofToken => Token(
        kind: TokenKind.Eof,
        location: SourceLocation(
            sourceIndex: sourceIndex, offset: 0, length: 0),
      );

  // ── Entry point ───────────────────────────────────────────────────────────

  SourceFile parse() {
    final start = _cur.location;
    final pragmas = <PragmaDirective>[];
    final imports = <ImportDirective>[];
    final contracts = <ContractDefinition>[];

    while (!_isEof) {
      try {
        if (_at(TokenKind.kPragma)) {
          pragmas.add(_parsePragma());
        } else if (_at(TokenKind.kImport)) {
          imports.add(_parseImport());
        } else if (_atAny([
          TokenKind.kContract,
          TokenKind.kInterface,
          TokenKind.kLibrary,
          TokenKind.kAbstract,
        ])) {
          contracts.add(_parseContractDefinition());
        } else {
          _errorAndSync('Unexpected token "${_cur.lexeme.isEmpty ? _cur.kind.name : _cur.lexeme}" at top level');
        }
      } on _ParseError {
        _synchronize({
          TokenKind.kContract, TokenKind.kInterface,
          TokenKind.kLibrary, TokenKind.kAbstract,
          TokenKind.kPragma, TokenKind.kImport,
        });
      }
    }

    return SourceFile(_locFrom(start), pragmas, imports, contracts);
  }

  // ── Pragmas & imports ─────────────────────────────────────────────────────

  PragmaDirective _parsePragma() {
    final start = _expect(TokenKind.kPragma).location;
    final literals = <String>[];
    while (!_at(TokenKind.Semicolon) && !_isEof) {
      literals.add(
          _cur.lexeme.isEmpty ? _cur.kind.name : _cur.lexeme);
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

    if (_atAny([TokenKind.StringLiteral, TokenKind.UnicodeStringLiteral])) {
      path = _advance().lexeme;
      if (_tryConsume(TokenKind.kAs)) alias = _ident();
    } else if (_at(TokenKind.Star)) {
      _advance();
      _expect(TokenKind.kAs);
      alias = _ident();
      _expect(TokenKind.kFrom);
      path = _advance().lexeme;
    } else if (_at(TokenKind.LBrace)) {
      _advance();
      while (!_at(TokenKind.RBrace) && !_isEof) {
        final sym = _ident();
        String? symAlias;
        if (_tryConsume(TokenKind.kAs)) symAlias = _ident();
        symbolAliases[sym] = symAlias;
        if (!_tryConsume(TokenKind.Comma)) break;
      }
      _expect(TokenKind.RBrace);
      _expect(TokenKind.kFrom);
      path = _advance().lexeme;
    } else {
      _error('Expected import path');
      path = '';
    }
    _expect(TokenKind.Semicolon);
    return ImportDirective(_locFrom(start), path, alias, symbolAliases);
  }

  // ── Contract / interface / library ────────────────────────────────────────

  ContractDefinition _parseContractDefinition() {
    final start = _cur.location;
    final isAbstract = _tryConsume(TokenKind.kAbstract);

    final kindTok = _advance();
    final kind = switch (kindTok.kind) {
      TokenKind.kInterface => ContractKind.interface,
      TokenKind.kLibrary => ContractKind.library,
      _ => ContractKind.contract,
    };

    final name = _ident();

    final bases = <InheritanceSpecifier>[];
    if (_tryConsume(TokenKind.kIs)) {
      do {
        final bStart = _cur.location;
        final bName = _qualifiedName();
        final args = <Expression>[];
        if (_tryConsume(TokenKind.LParen)) {
          if (!_at(TokenKind.RParen)) {
            args.add(_parseExpression());
            while (_tryConsume(TokenKind.Comma)) args.add(_parseExpression());
          }
          _expect(TokenKind.RParen);
        }
        bases.add(InheritanceSpecifier(_locFrom(bStart), bName, args));
      } while (_tryConsume(TokenKind.Comma));
    }

    _expect(TokenKind.LBrace);
    final members = <AstNode>[];
    while (!_at(TokenKind.RBrace) && !_isEof) {
      try {
        members.add(_parseContractMember());
      } on _ParseError {
        _synchronize({TokenKind.RBrace, TokenKind.Semicolon});
        _tryConsume(TokenKind.Semicolon);
      }
    }
    _expect(TokenKind.RBrace);

    return ContractDefinition(
      _locFrom(start), kind, name, bases, members,
      isAbstract: isAbstract,
    );
  }

  AstNode _parseContractMember() {
    // Skip NatSpec attached to the next member.
    while (_atAny([TokenKind.NatSpecLine, TokenKind.NatSpecBlock])) _advance();

    if (_at(TokenKind.kFunction) ||
        _at(TokenKind.kConstructor) ||
        _at(TokenKind.kFallback) ||
        _at(TokenKind.kReceive)) {
      return _parseFunctionDefinition();
    }
    if (_at(TokenKind.kModifier)) return _parseModifierDefinition();
    if (_at(TokenKind.kEvent)) return _parseEventDefinition();
    if (_at(TokenKind.kError)) return _parseCustomErrorDefinition();
    if (_at(TokenKind.kStruct)) return _parseStructDefinition();
    if (_at(TokenKind.kEnum)) return _parseEnumDefinition();
    if (_at(TokenKind.kUsing)) return _parseUsingDirective();
    if (_at(TokenKind.kType)) return _parseUserDefinedValueType();

    return _parseStateVariableDeclaration();
  }

  // ── Function definition ───────────────────────────────────────────────────

  FunctionDefinition _parseFunctionDefinition() {
    final start = _cur.location;

    FunctionKind kind;
    String? name;

    if (_at(TokenKind.kConstructor)) {
      _advance();
      kind = FunctionKind.constructor;
    } else if (_at(TokenKind.kFallback)) {
      _advance();
      kind = FunctionKind.fallback;
    } else if (_at(TokenKind.kReceive)) {
      _advance();
      kind = FunctionKind.receive;
    } else {
      _expect(TokenKind.kFunction);
      kind = FunctionKind.function;
      // function name is optional (anonymous function types) but required here.
      if (!_at(TokenKind.LParen)) name = _ident();
    }

    _expect(TokenKind.LParen);
    final params = _parseParameterList(allowIndexed: false);
    _expect(TokenKind.RParen);

    var visibility = Visibility.defaultVisibility;
    var mutability = StateMutability.nonpayable;
    var isVirtual = false;
    final overrides = <String>[];
    final modifiers = <ModifierInvocation>[];

    loop:
    while (true) {
      switch (_cur.kind) {
        case TokenKind.kPublic:
          visibility = Visibility.public; _advance();
        case TokenKind.kPrivate:
          visibility = Visibility.private; _advance();
        case TokenKind.kInternal:
          visibility = Visibility.internal; _advance();
        case TokenKind.kExternal:
          visibility = Visibility.external; _advance();
        case TokenKind.kPure:
          mutability = StateMutability.pure; _advance();
        case TokenKind.kView:
          mutability = StateMutability.view; _advance();
        case TokenKind.kPayable:
          mutability = StateMutability.payable; _advance();
        case TokenKind.kVirtual:
          isVirtual = true; _advance();
        case TokenKind.kOverride:
          _advance();
          if (_tryConsume(TokenKind.LParen)) {
            overrides.add(_ident());
            while (_tryConsume(TokenKind.Comma)) overrides.add(_ident());
            _expect(TokenKind.RParen);
          }
        case TokenKind.Identifier:
          // Modifier invocation
          final mStart = _cur.location;
          final mName = _advance().lexeme;
          final mArgs = <Expression>[];
          if (_tryConsume(TokenKind.LParen)) {
            if (!_at(TokenKind.RParen)) {
              mArgs.add(_parseExpression());
              while (_tryConsume(TokenKind.Comma)) {
                mArgs.add(_parseExpression());
              }
            }
            _expect(TokenKind.RParen);
          }
          modifiers.add(ModifierInvocation(_locFrom(mStart), mName, mArgs));
        default:
          break loop;
      }
    }

    var returnParams = <Parameter>[];
    if (_tryConsume(TokenKind.kReturns)) {
      _expect(TokenKind.LParen);
      returnParams = _parseParameterList(allowIndexed: false);
      _expect(TokenKind.RParen);
    }

    Block? body;
    if (_at(TokenKind.LBrace)) {
      body = _parseBlock();
    } else {
      _expect(TokenKind.Semicolon);
    }

    return FunctionDefinition(
      location: _locFrom(start),
      kind: kind,
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

  List<Parameter> _parseParameterList({bool allowIndexed = false}) {
    final params = <Parameter>[];
    if (_at(TokenKind.RParen)) return params;
    do {
      final pStart = _cur.location;
      final type = _parseTypeName();
      var indexed = false;
      DataLocation? loc;
      if (allowIndexed && _tryConsume(TokenKind.kIndexed)) {
        indexed = true;
      } else {
        loc = _tryParseDataLocation();
      }
      String? pName;
      if (_isIdentifier()) pName = _advance().lexeme;
      params.add(Parameter(
        _locFrom(pStart), type, pName, loc,
        indexed: indexed,
      ));
    } while (_tryConsume(TokenKind.Comma));
    return params;
  }

  // ── Modifier ──────────────────────────────────────────────────────────────

  ModifierDefinition _parseModifierDefinition() {
    final start = _expect(TokenKind.kModifier).location;
    final name = _ident();
    var params = <Parameter>[];
    if (_at(TokenKind.LParen)) {
      _advance();
      params = _parseParameterList(allowIndexed: false);
      _expect(TokenKind.RParen);
    }
    var isVirtual = false;
    final overrides = <String>[];
    while (true) {
      if (_tryConsume(TokenKind.kVirtual)) { isVirtual = true; continue; }
      if (_at(TokenKind.kOverride)) {
        _advance();
        if (_tryConsume(TokenKind.LParen)) {
          overrides.add(_ident());
          while (_tryConsume(TokenKind.Comma)) overrides.add(_ident());
          _expect(TokenKind.RParen);
        }
        continue;
      }
      break;
    }
    final body = _parseBlock();
    return ModifierDefinition(
      _locFrom(start), name, params, body,
      isVirtual: isVirtual,
      overrideSpecifier: overrides,
    );
  }

  // ── Event / error ─────────────────────────────────────────────────────────

  EventDefinition _parseEventDefinition() {
    final start = _expect(TokenKind.kEvent).location;
    final name = _ident();
    _expect(TokenKind.LParen);
    final params = _parseParameterList(allowIndexed: true);
    _expect(TokenKind.RParen);
    final anonymous = _tryConsume(TokenKind.kAnonymous);
    _expect(TokenKind.Semicolon);
    return EventDefinition(_locFrom(start), name, params, anonymous);
  }

  CustomErrorDefinition _parseCustomErrorDefinition() {
    final start = _expect(TokenKind.kError).location;
    final name = _ident();
    _expect(TokenKind.LParen);
    final params = _parseParameterList(allowIndexed: false);
    _expect(TokenKind.RParen);
    _expect(TokenKind.Semicolon);
    return CustomErrorDefinition(_locFrom(start), name, params);
  }

  // ── Struct / enum ─────────────────────────────────────────────────────────

  StructDefinition _parseStructDefinition() {
    final start = _expect(TokenKind.kStruct).location;
    final name = _ident();
    _expect(TokenKind.LBrace);
    final members = <VariableDeclaration>[];
    while (!_at(TokenKind.RBrace) && !_isEof) {
      final mStart = _cur.location;
      final type = _parseTypeName();
      final mName = _ident();
      _expect(TokenKind.Semicolon);
      members.add(VariableDeclaration(_locFrom(mStart), type, mName, null));
    }
    _expect(TokenKind.RBrace);
    return StructDefinition(_locFrom(start), name, members);
  }

  EnumDefinition _parseEnumDefinition() {
    final start = _expect(TokenKind.kEnum).location;
    final name = _ident();
    _expect(TokenKind.LBrace);
    final values = <String>[];
    if (!_at(TokenKind.RBrace)) {
      values.add(_ident());
      while (_tryConsume(TokenKind.Comma) && !_at(TokenKind.RBrace)) {
        values.add(_ident());
      }
    }
    _expect(TokenKind.RBrace);
    return EnumDefinition(_locFrom(start), name, values);
  }

  // ── Using directive ───────────────────────────────────────────────────────

  UsingDirective _parseUsingDirective() {
    final start = _expect(TokenKind.kUsing).location;
    final libName = _qualifiedName();
    _expect(TokenKind.kFor);
    TypeName? forType;
    if (!_at(TokenKind.Star)) forType = _parseTypeName();
    else _advance();
    _expect(TokenKind.Semicolon);
    return UsingDirective(_locFrom(start), libName, forType);
  }

  // ── User-defined value type ────────────────────────────────────────────────

  UserDefinedValueTypeDefinition _parseUserDefinedValueType() {
    final start = _expect(TokenKind.kType).location;
    final name = _ident();
    _expect(TokenKind.kIs);
    final underlying = _parseTypeName();
    _expect(TokenKind.Semicolon);
    return UserDefinedValueTypeDefinition(_locFrom(start), name, underlying);
  }

  // ── State variable ─────────────────────────────────────────────────────────

  StateVariableDeclaration _parseStateVariableDeclaration() {
    final start = _cur.location;
    final type = _parseTypeName();
    var visibility = Visibility.internal;
    var mutability = VariableMutability.mutable;

    loop:
    while (true) {
      switch (_cur.kind) {
        case TokenKind.kPublic:
          visibility = Visibility.public; _advance();
        case TokenKind.kPrivate:
          visibility = Visibility.private; _advance();
        case TokenKind.kInternal:
          visibility = Visibility.internal; _advance();
        case TokenKind.kImmutable:
          mutability = VariableMutability.immutable; _advance();
        case TokenKind.kConstant:
          mutability = VariableMutability.constant; _advance();
        case TokenKind.kOverride:
          _advance();
          if (_tryConsume(TokenKind.LParen)) {
            _ident();
            while (_tryConsume(TokenKind.Comma)) _ident();
            _expect(TokenKind.RParen);
          }
        default:
          break loop;
      }
    }

    final name = _ident();
    Expression? init;
    if (_tryConsume(TokenKind.Eq)) init = _parseExpression();
    _expect(TokenKind.Semicolon);
    return StateVariableDeclaration(
        _locFrom(start), type, name, visibility, mutability, init);
  }

  // ── Statements ─────────────────────────────────────────────────────────────

  Block _parseBlock() {
    final start = _expect(TokenKind.LBrace).location;
    final stmts = <Statement>[];
    while (!_at(TokenKind.RBrace) && !_isEof) {
      try {
        stmts.add(_parseStatement());
      } on _ParseError {
        _synchronize({TokenKind.Semicolon, TokenKind.RBrace});
        _tryConsume(TokenKind.Semicolon);
      }
    }
    _expect(TokenKind.RBrace);
    return Block(_locFrom(start), stmts);
  }

  Statement _parseStatement() {
    switch (_cur.kind) {
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
      case TokenKind.kUnchecked:
        return _parseUnchecked();
      case TokenKind.kTry:
        return _parseTry();
      default:
        return _parseExprOrVarDecl();
    }
  }

  ReturnStatement _parseReturn() {
    final start = _expect(TokenKind.kReturn).location;
    Expression? expr;
    if (!_at(TokenKind.Semicolon)) expr = _parseExpression();
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
    if (!_at(TokenKind.Semicolon)) {
      init = _parseExprOrVarDecl();
    } else {
      _advance(); // consume `;`
    }
    Expression? cond;
    if (!_at(TokenKind.Semicolon)) cond = _parseExpression();
    _expect(TokenKind.Semicolon);
    ExpressionStatement? loop;
    if (!_at(TokenKind.RParen)) {
      final e = _parseExpression();
      loop = ExpressionStatement(e.location, e);
    }
    _expect(TokenKind.RParen);
    return ForStatement(_locFrom(start), init, cond, loop, _parseStatement());
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
    // Optional: bare `revert;`
    if (_at(TokenKind.Semicolon)) {
      _advance();
      final loc = _locFrom(start);
      return RevertStatement(
        loc,
        FunctionCall(
          loc,
          Identifier(loc, 'revert'),
          const [],
          const [],
        ),
      );
    }
    final expr = _parseExpression();
    _expect(TokenKind.Semicolon);
    return RevertStatement(_locFrom(start), expr);
  }

  UncheckedStatement _parseUnchecked() {
    final start = _expect(TokenKind.kUnchecked).location;
    final body = _parseBlock();
    return UncheckedStatement(_locFrom(start), body);
  }

  AssemblyStatement _parseAssembly() {
    final start = _expect(TokenKind.kAssembly).location;
    String? dialect;
    if (_at(TokenKind.StringLiteral)) dialect = _advance().lexeme;
    _expect(TokenKind.LBrace);
    final buf = StringBuffer();
    var depth = 1;
    while (!_isEof && depth > 0) {
      if (_at(TokenKind.LBrace)) depth++;
      if (_at(TokenKind.RBrace)) {
        depth--;
        if (depth == 0) break;
      }
      final lex = _cur.lexeme;
      buf.write(lex.isEmpty ? _cur.kind.name : lex);
      buf.write(' ');
      _advance();
    }
    _expect(TokenKind.RBrace);
    return AssemblyStatement(_locFrom(start), dialect, buf.toString().trim());
  }

  TryStatement _parseTry() {
    final start = _expect(TokenKind.kTry).location;
    final call = _parseExpression(); // external call
    // optional returns clause
    if (_tryConsume(TokenKind.kReturns)) {
      _expect(TokenKind.LParen);
      _parseParameterList(allowIndexed: false);
      _expect(TokenKind.RParen);
    }
    final clauses = <CatchClause>[];
    // at least one catch block required
    do {
      clauses.add(_parseCatchClause());
    } while (_at(TokenKind.kCatch));
    return TryStatement(_locFrom(start), call, clauses);
  }

  CatchClause _parseCatchClause() {
    final start = _expect(TokenKind.kCatch).location;
    String? errorName;
    var params = <Parameter>[];
    if (!_at(TokenKind.LBrace)) {
      if (_isIdentifier()) errorName = _advance().lexeme;
      if (_at(TokenKind.LParen)) {
        _advance();
        params = _parseParameterList(allowIndexed: false);
        _expect(TokenKind.RParen);
      }
    }
    final body = _parseBlock();
    return CatchClause(_locFrom(start), errorName, params, body);
  }

  /// Parses either a local variable declaration or an expression statement.
  Statement _parseExprOrVarDecl() {
    final start = _cur.location;

    // Tuple destructuring: `(T x, T y) = expr;` or `(x, y) = expr;`
    if (_at(TokenKind.LParen)) {
      // Could be a tuple expression or a tuple-destructuring var-decl.
      // Try the declaration; fall back to expression if it doesn't fit.
      final decl = _speculate(() => _parseTupleVarDecl(start));
      if (decl != null) return decl;
    }

    if (_looksLikeTypeName()) {
      // `Ident[…]`, `Ident.Ident`, etc. are ambiguous: a user-defined-type
      // variable declaration (`Foo[] xs;`) looks identical to an index/member
      // assignment (`xs[i] = v;`). Try the declaration speculatively, and on
      // failure parse it as an expression statement instead.
      final decl = _speculate(() => _parseVarDecl(start));
      if (decl != null) return decl;
    }

    final expr = _parseExpression();
    _expect(TokenKind.Semicolon);
    return ExpressionStatement(_locFrom(start), expr);
  }

  Statement _parseTupleVarDecl(SourceLocation start) {
    _expect(TokenKind.LParen);
    final decls = <VariableDeclaration?>[];
    do {
      if (_at(TokenKind.Comma) || _at(TokenKind.RParen)) {
        decls.add(null);
      } else if (_looksLikeTypeName()) {
        final dStart = _cur.location;
        final type = _parseTypeName();
        final loc = _tryParseDataLocation();
        final name = _ident();
        decls.add(VariableDeclaration(_locFrom(dStart), type, name, loc));
      } else {
        throw _ParseError();
      }
    } while (_tryConsume(TokenKind.Comma));
    _expect(TokenKind.RParen);
    _expect(TokenKind.Eq);
    final init = _parseExpression();
    _expect(TokenKind.Semicolon);
    return VariableDeclarationStatement(_locFrom(start), decls, init);
  }

  Statement _parseVarDecl(SourceLocation start) {
    final type = _parseTypeName();
    final loc = _tryParseDataLocation();
    final name = _ident();
    Expression? init;
    if (_tryConsume(TokenKind.Eq)) init = _parseExpression();
    _expect(TokenKind.Semicolon);
    final decl = VariableDeclaration(_locFrom(start), type, name, loc);
    return VariableDeclarationStatement(_locFrom(start), [decl], init);
  }

  // ── Expressions ───────────────────────────────────────────────────────────

  Expression _parseExpression() => _parseAssignment();

  Expression _parseAssignment() {
    final left = _parseTernary();
    const assignOps = {
      TokenKind.Eq, TokenKind.PlusEq, TokenKind.MinusEq,
      TokenKind.StarEq, TokenKind.SlashEq, TokenKind.PercentEq,
      TokenKind.AmpEq, TokenKind.PipeEq, TokenKind.CaretEq,
      TokenKind.LtLtEq, TokenKind.GtGtEq, TokenKind.GtGtGtEq,
    };
    if (assignOps.contains(_cur.kind)) {
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

  static const _precTable = [
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

  Expression _parseOr() => _parseBinaryAt(0);

  Expression _parseBinaryAt(int level) {
    if (level >= _precTable.length) return _parseUnary();
    var left = _parseBinaryAt(level + 1);
    while (_precTable[level].contains(_cur.kind)) {
      final op = _advance().lexeme;
      final right = _parseBinaryAt(level + 1);
      left = BinaryOperation(
          left.location.combine(right.location), op, left, right);
    }
    return left;
  }

  Expression _parseUnary() {
    final start = _cur.location;
    switch (_cur.kind) {
      case TokenKind.Bang:
      case TokenKind.Tilde:
      case TokenKind.Minus:
        final op = _advance().lexeme;
        return UnaryOperation(_locFrom(start), op, _parseUnary(), true);
      case TokenKind.PlusPlus:
      case TokenKind.MinusMinus:
        final op = _advance().lexeme;
        return UnaryOperation(_locFrom(start), op, _parseUnary(), true);
      case TokenKind.kDelete:
        _advance();
        return DeleteExpression(_locFrom(start), _parseUnary());
      default:
        return _parsePostfix();
    }
  }

  Expression _parsePostfix() {
    var expr = _parsePrimary();
    outer:
    while (true) {
      switch (_cur.kind) {
        case TokenKind.Dot:
          _advance();
          final member = _ident();
          expr = MemberAccess(expr.location, expr, member);

        case TokenKind.LBracket:
          _advance();
          if (_at(TokenKind.Colon)) {
            // `arr[:]` or `arr[:n]`
            _advance();
            final end = _at(TokenKind.RBracket) ? null : _parseExpression();
            _expect(TokenKind.RBracket);
            expr = IndexRangeAccess(expr.location, expr, null, end);
          } else {
            final idx = _parseExpression();
            if (_tryConsume(TokenKind.Colon)) {
              final end = _at(TokenKind.RBracket) ? null : _parseExpression();
              _expect(TokenKind.RBracket);
              expr = IndexRangeAccess(expr.location, expr, idx, end);
            } else {
              _expect(TokenKind.RBracket);
              expr = IndexAccess(expr.location, expr, idx);
            }
          }

        case TokenKind.LBrace:
          // `f{value: v}(…)` call options
          _advance();
          final opts = <String, Expression>{};
          while (!_at(TokenKind.RBrace) && !_isEof) {
            final k = _ident();
            _expect(TokenKind.Colon);
            opts[k] = _parseExpression();
            if (!_tryConsume(TokenKind.Comma)) break;
          }
          _expect(TokenKind.RBrace);
          expr = FunctionCallOptions(expr.location, expr, opts);

        case TokenKind.LParen:
          _advance();
          final args = <Expression>[];
          final names = <String?>[];
          // Named arguments: `{a: 1, b: 2}` syntax inside parens
          if (_at(TokenKind.LBrace)) {
            _advance();
            while (!_at(TokenKind.RBrace) && !_isEof) {
              names.add(_ident());
              _expect(TokenKind.Colon);
              args.add(_parseExpression());
              if (!_tryConsume(TokenKind.Comma)) break;
            }
            _expect(TokenKind.RBrace);
          } else {
            while (!_at(TokenKind.RParen) && !_isEof) {
              names.add(null);
              args.add(_parseExpression());
              if (!_tryConsume(TokenKind.Comma)) break;
            }
          }
          _expect(TokenKind.RParen);
          expr = FunctionCall(expr.location, expr, args, names);

        case TokenKind.PlusPlus:
          expr = UnaryOperation(expr.location, _advance().lexeme, expr, false);
        case TokenKind.MinusMinus:
          expr = UnaryOperation(expr.location, _advance().lexeme, expr, false);

        default:
          break outer;
      }
    }
    return expr;
  }

  Expression _parsePrimary() {
    final start = _cur.location;

    switch (_cur.kind) {
      // ── Literals ────────────────────────────────────────────────────────
      case TokenKind.NumberLiteral:
        final val = _advance().lexeme;
        String? sub;
        if (_atAny([
          TokenKind.kWei, TokenKind.kGwei, TokenKind.kEther,
          TokenKind.kSeconds, TokenKind.kMinutes, TokenKind.kHours,
          TokenKind.kDays, TokenKind.kWeeks,
        ])) {
          sub = _advance().lexeme;
        }
        return Literal(_locFrom(start), LiteralKind.number, val, sub);

      case TokenKind.StringLiteral:
        // Concatenated string literals: `"a" "b"` → one node.
        final buf = StringBuffer(_advance().lexeme);
        while (_at(TokenKind.StringLiteral)) buf.write(_advance().lexeme);
        return Literal(_locFrom(start), LiteralKind.string, buf.toString(), null);

      case TokenKind.UnicodeStringLiteral:
        return Literal(
            _locFrom(start), LiteralKind.unicodeString, _advance().lexeme, null);

      case TokenKind.HexStringLiteral:
        return Literal(
            _locFrom(start), LiteralKind.hexString, _advance().lexeme, null);

      case TokenKind.TrueLiteral:
        _advance();
        return Literal(_locFrom(start), LiteralKind.bool$, 'true', null);

      case TokenKind.FalseLiteral:
        _advance();
        return Literal(_locFrom(start), LiteralKind.bool$, 'false', null);

      // ── this / super ────────────────────────────────────────────────────
      case TokenKind.kThis:
        _advance();
        return Identifier(_locFrom(start), 'this');

      case TokenKind.kSuper:
        _advance();
        return Identifier(_locFrom(start), 'super');

      // ── type(X) ─────────────────────────────────────────────────────────
      case TokenKind.kType:
        _advance();
        _expect(TokenKind.LParen);
        final typeName = _parseTypeName();
        _expect(TokenKind.RParen);
        return TypeExpression(_locFrom(start), typeName);

      // ── new T ────────────────────────────────────────────────────────────
      case TokenKind.kNew:
        _advance();
        return NewExpression(_locFrom(start), _parseTypeName());

      // ── Parenthesised / tuple ────────────────────────────────────────────
      case TokenKind.LParen:
        _advance();
        if (_at(TokenKind.RParen)) {
          _advance();
          return TupleExpression(_locFrom(start), [], false);
        }
        final first = _parseExpression();
        if (_at(TokenKind.RParen)) {
          _advance();
          return first; // plain parenthesised expression
        }
        // Tuple
        final components = <Expression?>[first];
        while (_tryConsume(TokenKind.Comma)) {
          if (_at(TokenKind.RParen) || _at(TokenKind.Comma)) {
            components.add(null);
          } else {
            components.add(_parseExpression());
          }
        }
        _expect(TokenKind.RParen);
        return TupleExpression(_locFrom(start), components, false);

      // ── Array literal [a, b, c] ──────────────────────────────────────────
      case TokenKind.LBracket:
        _advance();
        final items = <Expression?>[];
        if (!_at(TokenKind.RBracket)) {
          items.add(_parseExpression());
          while (_tryConsume(TokenKind.Comma)) {
            if (_at(TokenKind.RBracket)) break;
            items.add(_parseExpression());
          }
        }
        _expect(TokenKind.RBracket);
        return TupleExpression(_locFrom(start), items, true);

      // ── Type conversion / identifier ─────────────────────────────────────
      default:
        // Elementary type conversion: `uint256(x)`, `address(y)`, etc.
        if (_isElementaryType(_cur.kind)) {
          final typeName = _parseTypeName();
          _expect(TokenKind.LParen);
          final inner = _parseExpression();
          _expect(TokenKind.RParen);
          return TypeConversion(_locFrom(start), typeName, inner);
        }

        if (_at(TokenKind.Identifier)) {
          return Identifier(_locFrom(start), _advance().lexeme);
        }

        // Keywords that are valid as identifiers in expression position.
        if (_isKeywordUsableAsIdentifier(_cur.kind)) {
          return Identifier(_locFrom(start), _advance().lexeme);
        }

        _error(
          'Expected expression, got "${_cur.lexeme.isEmpty ? _cur.kind.name : _cur.lexeme}"',
        );
        _advance();
        return Literal(_locFrom(start), LiteralKind.number, '0', null);
    }
  }

  // ── Type names ─────────────────────────────────────────────────────────────

  TypeName _parseTypeName() {
    final start = _cur.location;
    TypeName base;

    if (_at(TokenKind.kMapping)) {
      _advance();
      _expect(TokenKind.LParen);
      final key = _parseTypeName();
      _expect(TokenKind.Arrow);
      final val = _parseTypeName();
      _expect(TokenKind.RParen);
      base = MappingTypeName(_locFrom(start), key, val);
    } else if (_at(TokenKind.kFunction)) {
      base = _parseFunctionTypeName();
    } else if (_isElementaryType(_cur.kind)) {
      final name = _cur.lexeme.isEmpty ? _cur.kind.name : _cur.lexeme;
      final width = _cur.intWidth;
      _advance();
      // `address payable`
      if (name == 'address' && _tryConsume(TokenKind.kPayable)) {
        return ElementaryTypeName(
            _locFrom(start), 'address payable', intWidth: 0);
      }
      base = ElementaryTypeName(_locFrom(start), name, intWidth: width);
    } else {
      // User-defined (possibly qualified: A.B)
      final parts = [_ident()];
      while (_at(TokenKind.Dot)) {
        _advance();
        parts.add(_ident());
      }
      base = UserDefinedTypeName(_locFrom(start), parts);
    }

    // Array suffixes
    while (_at(TokenKind.LBracket)) {
      _advance();
      Expression? len;
      if (!_at(TokenKind.RBracket)) len = _parseExpression();
      _expect(TokenKind.RBracket);
      base = ArrayTypeName(_locFrom(start), base, len);
    }

    return base;
  }

  FunctionTypeName _parseFunctionTypeName() {
    final start = _expect(TokenKind.kFunction).location;
    _expect(TokenKind.LParen);
    final params = _parseParameterList(allowIndexed: false);
    _expect(TokenKind.RParen);
    var vis = Visibility.internal;
    var mut = StateMutability.nonpayable;
    while (true) {
      switch (_cur.kind) {
        case TokenKind.kPublic: vis = Visibility.public; _advance();
        case TokenKind.kExternal: vis = Visibility.external; _advance();
        case TokenKind.kInternal: vis = Visibility.internal; _advance();
        case TokenKind.kPrivate: vis = Visibility.private; _advance();
        case TokenKind.kPure: mut = StateMutability.pure; _advance();
        case TokenKind.kView: mut = StateMutability.view; _advance();
        case TokenKind.kPayable: mut = StateMutability.payable; _advance();
        default: break;
      }
      break;
    }
    var returnParams = <Parameter>[];
    if (_tryConsume(TokenKind.kReturns)) {
      _expect(TokenKind.LParen);
      returnParams = _parseParameterList(allowIndexed: false);
      _expect(TokenKind.RParen);
    }
    return FunctionTypeName(_locFrom(start), params, returnParams, mut, vis);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _isEof => _cur.kind == TokenKind.Eof;

  bool _at(TokenKind k) => _cur.kind == k;

  bool _atAny(List<TokenKind> ks) => ks.contains(_cur.kind);

  Token _advance() {
    final t = _cur;
    if (_pos < tokens.length) _pos++;
    return t;
  }

  Token _expect(TokenKind kind) {
    if (_cur.kind == kind) return _advance();
    _error('Expected ${kind.name}, got ${_cur.kind.name}');
    throw _ParseError();
  }

  bool _tryConsume(TokenKind kind) {
    if (_cur.kind == kind) { _advance(); return true; }
    return false;
  }

  /// Parses a (possibly qualified) identifier name: `A` or `A.B`.
  String _qualifiedName() {
    final buf = StringBuffer(_ident());
    while (_at(TokenKind.Dot)) {
      _advance();
      buf.write('.');
      buf.write(_ident());
    }
    return buf.toString();
  }

  /// Parses a single identifier, accepting some keywords as identifiers.
  String _ident() {
    if (_at(TokenKind.Identifier)) return _advance().lexeme;
    if (_isKeywordUsableAsIdentifier(_cur.kind)) return _advance().lexeme;
    _error('Expected identifier, got ${_cur.kind.name}');
    throw _ParseError();
  }

  bool _isIdentifier() =>
      _at(TokenKind.Identifier) || _isKeywordUsableAsIdentifier(_cur.kind);

  DataLocation? _tryParseDataLocation() {
    switch (_cur.kind) {
      case TokenKind.kStorage: _advance(); return DataLocation.storage;
      case TokenKind.kMemory: _advance(); return DataLocation.memory;
      case TokenKind.kCalldata: _advance(); return DataLocation.calldata;
      default: return null;
    }
  }

  SourceLocation _locFrom(SourceLocation start) =>
      start.combine(_cur.location);

  /// Attempts [parse] speculatively: on a parse error, rewinds the token
  /// stream and returns null without recording any diagnostics. Used to
  /// disambiguate constructs that share a prefix (e.g. `Foo[] xs;` vs
  /// `xs[i] = v;`).
  R? _speculate<R>(R Function() parse) {
    final saved = _pos;
    _suppressErrors++;
    try {
      return parse();
    } on _ParseError {
      _pos = saved;
      return null;
    } finally {
      _suppressErrors--;
    }
  }

  void _error(String msg) {
    if (_suppressErrors > 0) return;
    diagnostics.error(msg, location: _cur.location);
  }

  void _errorAndSync(String msg) {
    _error(msg);
    _advance();
  }

  void _synchronize(Set<TokenKind> stopAt) {
    while (!_isEof && !stopAt.contains(_cur.kind)) _advance();
  }

  bool _looksLikeTypeName() {
    if (_isElementaryType(_cur.kind)) return true;
    if (_at(TokenKind.kMapping) || _at(TokenKind.kFunction)) return true;
    // `Identifier` followed by `[`, `.`, or another identifier → type name.
    if (_at(TokenKind.Identifier)) {
      final next = _peekKind(1);
      return next == TokenKind.LBracket ||
          next == TokenKind.Dot ||
          next == TokenKind.Identifier ||
          next == TokenKind.kMemory ||
          next == TokenKind.kStorage ||
          next == TokenKind.kCalldata;
    }
    return false;
  }

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

  /// Keywords that Solidity allows as identifiers in certain positions
  /// (member names, event names, etc.).
  static bool _isKeywordUsableAsIdentifier(TokenKind k) => const {
        TokenKind.kFrom,
        TokenKind.kError,
        TokenKind.kRevert,
        TokenKind.kType,
      }.contains(k);

  TokenKind _peekKind(int offset) {
    final i = _pos + offset;
    return i < tokens.length ? tokens[i].kind : TokenKind.Eof;
  }
}

// ── Internal error class for structured error recovery ────────────────────────

class _ParseError implements Exception {}

