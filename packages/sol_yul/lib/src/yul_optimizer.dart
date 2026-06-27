import 'yul_ast.dart';

/// A small, conservative Yul optimiser.
///
/// Applies, to a fixed point:
///  * **Constant folding** — evaluates pure built-ins (`add`, `mul`, `and`,
///    `lt`, `shl`, …) whose arguments are all literals, using 256-bit EVM
///    semantics.
///  * **Algebraic simplification** — identities such as `add(x, 0) → x`,
///    `mul(x, 1) → x`, `mul(x, 0) → 0` (the last only when `x` is
///    side-effect-free).
///  * **Dead-code elimination** — removes statements after an unconditional
///    terminator (`return`, `revert`, `stop`, `leave`, `break`, `continue`)
///    and drops `let` bindings whose variables are never read or assigned (the
///    initializer is kept as an expression statement when it has side effects).
///  * **Function inlining** — expands small, non-recursive functions called in
///    statement context (`let ret := fn(args)` or `fn(args)`) directly at the
///    call site.  A function is eligible when its body has at most
///    [inlineThreshold] statements (counted recursively) and it does not call
///    itself directly or indirectly.
///
/// The optimiser is purely AST→AST and never changes observable behaviour.
class YulOptimizer {
  YulOptimizer({this.maxPasses = 10, this.inlineThreshold = 12});

  /// Upper bound on fixed-point iterations (a safety net; convergence is
  /// usually reached in 1–2 passes).
  final int maxPasses;

  /// Maximum (inclusive) number of statements a function body may contain for
  /// it to be considered eligible for inlining.
  final int inlineThreshold;

  static final BigInt _mask = (BigInt.one << 256) - BigInt.one;
  static final BigInt _signBit = BigInt.one << 255;

  /// Counter used to generate unique variable names for inlined copies.
  int _inlineCounter = 0;

  YulObject optimize(YulObject obj) => YulObject(
    obj.name,
    _fixBlock(obj.code),
    obj.subObjects.map(optimize).toList(),
    obj.data,
  );

  /// Optimises a standalone block (e.g. an inline-assembly body).
  YulBlock optimizeBlock(YulBlock block) => _fixBlock(block);

  // ── Fixed-point driver ────────────────────────────────────────────────────

  YulBlock _fixBlock(YulBlock block) {
    var current = block;
    for (var i = 0; i < maxPasses; i++) {
      final inlined = _inlineBlock(current);
      final next = _eliminateDead(_block(inlined));
      if (_printEq(next, current)) return next;
      current = next;
    }
    return current;
  }

  // ── Function inlining ─────────────────────────────────────────────────────

  /// Collects all [YulFunctionDefinition]s that appear as direct children of
  /// [block].
  Map<String, YulFunctionDefinition> _collectDefs(YulBlock block) {
    final defs = <String, YulFunctionDefinition>{};
    for (final s in block.statements) {
      if (s is YulFunctionDefinition) defs[s.name] = s;
    }
    return defs;
  }

  /// Whether [fn] is eligible for inlining:
  ///  * not part of any recursive cycle in the call graph (direct or mutual)
  ///  * AND (small enough OR called from exactly one site — single-callers are
  ///    always a size win because the body replaces the call instead of being
  ///    duplicated)
  bool _canInline(
    YulFunctionDefinition fn, {
    required Set<String> recursive,
    required Map<String, int> callCounts,
  }) {
    if (recursive.contains(fn.name)) return false;
    final singleCaller = (callCounts[fn.name] ?? 0) == 1;
    if (!singleCaller && _countStmts(fn.body) > inlineThreshold) return false;
    return true;
  }

  /// Builds a `caller → callees` graph for the function definitions in
  /// [block] and returns the set of functions that participate in any cycle
  /// (direct self-recursion or mutual recursion via other functions).
  ///
  /// Functions outside that set are safe to inline without risking infinite
  /// expansion.
  Set<String> _recursiveFunctions(Map<String, YulFunctionDefinition> defs) {
    final graph = <String, Set<String>>{};
    for (final entry in defs.entries) {
      graph[entry.key] = _collectCalleeNames(
        entry.value.body,
        defs.keys.toSet(),
      );
    }
    final recursive = <String>{};
    // A function is recursive iff it can reach itself in the call graph.
    for (final name in graph.keys) {
      final visited = <String>{};
      final stack = [...graph[name]!];
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        if (cur == name) {
          recursive.add(name);
          break;
        }
        if (!visited.add(cur)) continue;
        stack.addAll(graph[cur] ?? const <String>{});
      }
    }
    return recursive;
  }

  Set<String> _collectCalleeNames(YulNode node, Set<String> universe) {
    final out = <String>{};
    void visit(YulNode n) {
      switch (n) {
        case YulFunctionCall(:final name, :final arguments):
          if (universe.contains(name)) out.add(name);
          for (final a in arguments) {
            visit(a);
          }
        case YulBlock(:final statements):
          for (final s in statements) {
            visit(s);
          }
        case YulVariableDeclaration(:final value):
          if (value != null) visit(value);
        case YulAssignment(:final value):
          visit(value);
        case YulExpressionStatement(:final expression):
          visit(expression);
        case YulIf(:final condition, :final body):
          visit(condition);
          visit(body);
        case YulForLoop(:final pre, :final condition, :final post, :final body):
          visit(pre);
          visit(condition);
          visit(post);
          visit(body);
        case YulSwitch(:final expression, :final cases, :final defaultCase):
          visit(expression);
          for (final c in cases) {
            visit(c.body);
          }
          if (defaultCase != null) visit(defaultCase);
        case YulFunctionDefinition(:final body):
          visit(body);
        default:
          break;
      }
    }

    visit(node);
    return out;
  }

  /// Counts how many times each function in [defs] is called within [block].
  ///
  /// Used to single out functions with exactly one caller, which we always
  /// inline (replacing a call with the body never grows the program).
  Map<String, int> _countCalls(
    YulBlock block,
    Map<String, YulFunctionDefinition> defs,
  ) {
    final counts = <String, int>{for (final k in defs.keys) k: 0};
    void visit(YulNode n) {
      switch (n) {
        case YulFunctionCall(:final name, :final arguments):
          if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
          for (final a in arguments) {
            visit(a);
          }
        case YulBlock(:final statements):
          for (final s in statements) {
            visit(s);
          }
        case YulVariableDeclaration(:final value):
          if (value != null) visit(value);
        case YulAssignment(:final value):
          visit(value);
        case YulExpressionStatement(:final expression):
          visit(expression);
        case YulIf(:final condition, :final body):
          visit(condition);
          visit(body);
        case YulForLoop(:final pre, :final condition, :final post, :final body):
          visit(pre);
          visit(condition);
          visit(post);
          visit(body);
        case YulSwitch(:final expression, :final cases, :final defaultCase):
          visit(expression);
          for (final c in cases) {
            visit(c.body);
          }
          if (defaultCase != null) visit(defaultCase);
        case YulFunctionDefinition(:final body):
          visit(body);
        default:
          break;
      }
    }

    visit(block);
    return counts;
  }

  /// Counts statements recursively inside [block].
  int _countStmts(YulBlock block) {
    var n = 0;
    for (final s in block.statements) {
      n++;
      if (s is YulBlock) n += _countStmts(s);
      if (s is YulIf) n += _countStmts(s.body);
      if (s is YulForLoop) {
        n += _countStmts(s.pre) + _countStmts(s.post) + _countStmts(s.body);
      }
      if (s is YulSwitch) {
        for (final c in s.cases) {
          n += _countStmts(c.body);
        }
        if (s.defaultCase != null) n += _countStmts(s.defaultCase!);
      }
      if (s is YulFunctionDefinition) n += _countStmts(s.body);
    }
    return n;
  }

  /// Runs the inlining pass over [block]: replaces eligible calls in statement
  /// context with their expanded bodies.
  YulBlock _inlineBlock(YulBlock block) {
    final defs = _collectDefs(block);
    if (defs.isEmpty) return block;
    final recursive = _recursiveFunctions(defs);
    final callCounts = _countCalls(block, defs);

    final eligible = <String, YulFunctionDefinition>{};
    for (final entry in defs.entries) {
      if (_canInline(
        entry.value,
        recursive: recursive,
        callCounts: callCounts,
      )) {
        eligible[entry.key] = entry.value;
      }
    }
    if (eligible.isEmpty) return block;

    final out = <YulStatement>[];
    for (final s in block.statements) {
      out.addAll(_inlineStatement(s, eligible));
    }
    return YulBlock(out);
  }

  /// Tries to expand [stmt] if it is a direct call to an inlineable function.
  /// May return multiple statements (the expanded body). Recurses into nested
  /// blocks.
  List<YulStatement> _inlineStatement(
    YulStatement stmt,
    Map<String, YulFunctionDefinition> eligible,
  ) {
    switch (stmt) {
      // ── let vars := fn(args) ──
      case YulVariableDeclaration(:final variables, :final value)
          when value is YulFunctionCall && eligible.containsKey(value.name):
        final fn = eligible[value.name]!;
        final expanded = _expandCall(fn, value.arguments);
        if (expanded == null) break;
        final (preStmts, retVarNames) = expanded;
        // Assign the inlined return variable(s) to `variables`.
        if (variables.length == retVarNames.length) {
          final out = <YulStatement>[...preStmts];
          for (var i = 0; i < variables.length; i++) {
            out.add(
              YulVariableDeclaration([
                variables[i],
              ], YulIdentifier(retVarNames[i])),
            );
          }
          return out;
        }
        break;

      // ── fn(args) as a bare expression statement ──
      case YulExpressionStatement(
            expression: YulFunctionCall(:final name, :final arguments),
          )
          when eligible.containsKey(name):
        final fn = eligible[name]!;
        final expanded = _expandCall(fn, arguments);
        if (expanded != null) {
          final (preStmts, _) = expanded;
          return preStmts;
        }
        break;

      // ── Recurse into nested blocks ──
      case YulBlock():
        return [_inlineBlock(stmt)];
      case YulIf(:final condition, :final body):
        return [YulIf(condition, _inlineBlock(body))];
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        return [
          YulForLoop(
            _inlineBlock(pre),
            condition,
            _inlineBlock(post),
            _inlineBlock(body),
          ),
        ];
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        return [
          YulSwitch(
            expression,
            cases.map((c) => YulCase(c.value, _inlineBlock(c.body))).toList(),
            defaultCase == null ? null : _inlineBlock(defaultCase),
          ),
        ];
      case YulFunctionDefinition(
        :final name,
        :final parameters,
        :final returnVariables,
        :final body,
      ):
        return [
          YulFunctionDefinition(
            name,
            parameters,
            returnVariables,
            _inlineBlock(body),
          ),
        ];
      default:
        break;
    }
    return [stmt];
  }

  /// Expands a call to [fn] with [args]:
  ///   1. Declares fresh locals for each parameter, initialised from [args].
  ///   2. Declares fresh locals for each return variable, initialised to 0.
  ///   3. Wraps the body in `for {} 1 {} { <body> break }` so that `leave`
  ///      (renamed to `break`) exits the inlined scope, not the outer function.
  ///
  /// Returns `([pre-statements], [fresh-return-var-names])` or `null` when the
  /// call cannot be safely expanded (e.g. wrong argument count).
  (List<YulStatement>, List<String>)? _expandCall(
    YulFunctionDefinition fn,
    List<YulExpression> args,
  ) {
    if (args.length != fn.parameters.length) return null;

    final id = _inlineCounter++;
    final rename = <String, String>{};

    // Map each parameter name to a fresh local.
    for (final p in fn.parameters) {
      rename[p] = '_il${id}_$p';
    }
    // Map each return variable to a fresh local.
    for (final r in fn.returnVariables) {
      rename[r] = '_il${id}_$r';
    }

    final stmts = <YulStatement>[];

    // Declare parameter locals.
    for (var i = 0; i < fn.parameters.length; i++) {
      stmts.add(YulVariableDeclaration([rename[fn.parameters[i]]!], args[i]));
    }

    // Declare return locals (default zero).
    for (final r in fn.returnVariables) {
      stmts.add(
        YulVariableDeclaration([
          rename[r]!,
        ], YulLiteral('0', YulLiteralKind.number)),
      );
    }

    // Build the inlined body (rename + replace leave→break).
    final inlinedBody = _substituteBlock(fn.body, rename, leaveToBreak: true);

    // Wrap in for {} 1 {} { <body>; break } so that leave (now break) exits.
    stmts.add(
      YulForLoop(
        YulBlock(const []),
        YulLiteral('1', YulLiteralKind.number),
        YulBlock(const []),
        YulBlock([...inlinedBody.statements, YulBreak()]),
      ),
    );

    final retNames = fn.returnVariables.map((r) => rename[r]!).toList();
    return (stmts, retNames);
  }

  // ── Variable substitution ─────────────────────────────────────────────────

  YulBlock _substituteBlock(
    YulBlock block,
    Map<String, String> rename, {
    bool leaveToBreak = false,
  }) {
    return YulBlock(
      block.statements
          .map((s) => _substituteStmt(s, rename, leaveToBreak: leaveToBreak))
          .toList(),
    );
  }

  YulStatement _substituteStmt(
    YulStatement s,
    Map<String, String> rename, {
    bool leaveToBreak = false,
  }) {
    final out = _substituteStmtBody(s, rename, leaveToBreak: leaveToBreak);
    out.location ??= s.location;
    return out;
  }

  YulStatement _substituteStmtBody(
    YulStatement s,
    Map<String, String> rename, {
    bool leaveToBreak = false,
  }) {
    switch (s) {
      case YulLeave() when leaveToBreak:
        return YulBreak();
      case YulVariableDeclaration(:final variables, :final value):
        return YulVariableDeclaration(
          variables.map((v) => rename[v] ?? v).toList(),
          value == null ? null : _substituteExpr(value, rename),
        );
      case YulAssignment(:final variables, :final value):
        return YulAssignment(
          variables.map((v) => rename[v] ?? v).toList(),
          _substituteExpr(value, rename),
        );
      case YulExpressionStatement(:final expression):
        return YulExpressionStatement(_substituteExpr(expression, rename));
      case YulBlock():
        return _substituteBlock(s, rename, leaveToBreak: leaveToBreak);
      case YulIf(:final condition, :final body):
        return YulIf(
          _substituteExpr(condition, rename),
          _substituteBlock(body, rename, leaveToBreak: leaveToBreak),
        );
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        // Note: `leave` inside a for loop means "leave the function", so we
        // continue substituting it to break; `break`/`continue` remain as-is.
        return YulForLoop(
          _substituteBlock(pre, rename, leaveToBreak: leaveToBreak),
          _substituteExpr(condition, rename),
          _substituteBlock(post, rename, leaveToBreak: leaveToBreak),
          _substituteBlock(body, rename, leaveToBreak: leaveToBreak),
        );
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        return YulSwitch(
          _substituteExpr(expression, rename),
          cases
              .map(
                (c) => YulCase(
                  c.value,
                  _substituteBlock(c.body, rename, leaveToBreak: leaveToBreak),
                ),
              )
              .toList(),
          defaultCase == null
              ? null
              : _substituteBlock(
                  defaultCase,
                  rename,
                  leaveToBreak: leaveToBreak,
                ),
        );
      // Inner function definitions: do NOT substitute leave→break inside them
      // (leave exits their own function, not the inlined one).
      case YulFunctionDefinition(
        :final name,
        :final parameters,
        :final returnVariables,
        :final body,
      ):
        return YulFunctionDefinition(
          name,
          parameters,
          returnVariables,
          _substituteBlock(body, rename, leaveToBreak: false),
        );
      default:
        return s;
    }
  }

  YulExpression _substituteExpr(YulExpression e, Map<String, String> rename) {
    final out = _substituteExprBody(e, rename);
    out.location ??= e.location;
    return out;
  }

  YulExpression _substituteExprBody(
    YulExpression e,
    Map<String, String> rename,
  ) {
    switch (e) {
      case YulIdentifier(:final name):
        final newName = rename[name];
        return newName == null ? e : YulIdentifier(newName);
      case YulFunctionCall(:final name, :final arguments):
        return YulFunctionCall(
          name,
          arguments.map((a) => _substituteExpr(a, rename)).toList(),
        );
      default:
        return e; // YulLiteral — no substitution needed
    }
  }

  // ── Statement / block transformation (fold + simplify) ──────────────────────

  YulBlock _block(YulBlock block) =>
      YulBlock(block.statements.map(_statement).toList());

  YulStatement _statement(YulStatement s) {
    final out = _statementBody(s);
    out.location ??= s.location;
    return out;
  }

  YulStatement _statementBody(YulStatement s) {
    switch (s) {
      case YulBlock():
        return _block(s);
      case YulVariableDeclaration(:final variables, :final value):
        return YulVariableDeclaration(
          variables,
          value == null ? null : _expr(value),
        );
      case YulAssignment(:final variables, :final value):
        return YulAssignment(variables, _expr(value));
      case YulExpressionStatement(:final expression):
        return YulExpressionStatement(_expr(expression));
      case YulIf(:final condition, :final body):
        return YulIf(_expr(condition), _block(body));
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        return YulSwitch(
          _expr(expression),
          cases.map((c) => YulCase(c.value, _block(c.body))).toList(),
          defaultCase == null ? null : _block(defaultCase),
        );
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        return YulForLoop(
          _block(pre),
          _expr(condition),
          _block(post),
          _block(body),
        );
      case YulFunctionDefinition(
        :final name,
        :final parameters,
        :final returnVariables,
        :final body,
      ):
        return YulFunctionDefinition(
          name,
          parameters,
          returnVariables,
          _fixBlock(body),
        );
      case YulBreak():
      case YulContinue():
      case YulLeave():
        return s;
    }
  }

  // ── Expression transformation ───────────────────────────────────────────────

  YulExpression _expr(YulExpression e) {
    final out = _exprBody(e);
    out.location ??= e.location;
    return out;
  }

  YulExpression _exprBody(YulExpression e) {
    if (e is! YulFunctionCall) return e;
    final args = e.arguments.map(_expr).toList();
    final call = YulFunctionCall(e.name, args);

    // Constant folding: all arguments are number/bool literals.
    final consts = _asConstants(args);
    if (consts != null) {
      final folded = _fold(e.name, consts);
      if (folded != null) return _numLiteral(folded);
    }

    return _simplify(call) ?? call;
  }

  /// Algebraic identities. Returns the replacement expression or null.
  YulExpression? _simplify(YulFunctionCall call) {
    final a = call.arguments.isNotEmpty ? call.arguments[0] : null;
    final b = call.arguments.length > 1 ? call.arguments[1] : null;
    if (a == null || b == null || call.arguments.length != 2) return null;

    final av = _constValue(a);
    final bv = _constValue(b);

    switch (call.name) {
      case 'add':
      case 'or':
      case 'xor':
        if (bv == BigInt.zero) return a;
        if (av == BigInt.zero) return b;
      case 'sub':
        if (bv == BigInt.zero) return a;
      case 'mul':
        if (bv == BigInt.one) return a;
        if (av == BigInt.one) return b;
        if (bv == BigInt.zero && _isSideEffectFree(a)) {
          return _numLiteral(BigInt.zero);
        }
        if (av == BigInt.zero && _isSideEffectFree(b)) {
          return _numLiteral(BigInt.zero);
        }
      case 'div':
        if (bv == BigInt.one) return a;
      case 'and':
        if (bv == BigInt.zero && _isSideEffectFree(a)) {
          return _numLiteral(BigInt.zero);
        }
        if (av == BigInt.zero && _isSideEffectFree(b)) {
          return _numLiteral(BigInt.zero);
        }
        if (bv == _mask) return a;
        if (av == _mask) return b;
      case 'shl':
      case 'shr':
      case 'sar':
        // shift(0, value) == value
        if (av == BigInt.zero) return b;
    }
    return null;
  }

  // ── Dead-code elimination ─────────────────────────────────────────────────

  YulBlock _eliminateDead(YulBlock block) {
    final reads = <String>{};
    final assigns = <String>{};
    _collectUses(block, reads, assigns);
    return _dceBlock(block, reads, assigns);
  }

  YulBlock _dceBlock(YulBlock block, Set<String> reads, Set<String> assigns) {
    final out = <YulStatement>[];
    var terminated = false;
    for (final s in block.statements) {
      // Statements after an unconditional terminator are unreachable —
      // EXCEPT function definitions (and statements containing them), which
      // are hoisted and reached via jumps, not fall-through. Dropping a
      // hoisted function would leave dangling jumps.
      if (terminated && !_hasFunctionDef(s)) continue;
      final stmt = _dceStatement(s, reads, assigns);
      if (stmt != null) out.add(stmt);
      if (!terminated && _isTerminator(s)) terminated = true;
    }
    return YulBlock(out);
  }

  /// Whether [node] contains a (possibly nested) function definition.
  static bool _hasFunctionDef(YulNode node) {
    switch (node) {
      case YulFunctionDefinition():
        return true;
      case YulBlock(:final statements):
        return statements.any(_hasFunctionDef);
      case YulIf(:final body):
        return _hasFunctionDef(body);
      case YulForLoop(:final pre, :final post, :final body):
        return _hasFunctionDef(pre) ||
            _hasFunctionDef(post) ||
            _hasFunctionDef(body);
      case YulSwitch(:final cases, :final defaultCase):
        return cases.any((c) => _hasFunctionDef(c.body)) ||
            (defaultCase != null && _hasFunctionDef(defaultCase));
      default:
        return false;
    }
  }

  YulStatement? _dceStatement(
    YulStatement s,
    Set<String> reads,
    Set<String> assigns,
  ) {
    switch (s) {
      case YulVariableDeclaration(:final variables, :final value):
        final used = variables.any(
          (v) => reads.contains(v) || assigns.contains(v),
        );
        if (used) return s;
        // No variable is ever read or assigned: the binding is dead.
        if (value == null || _isSideEffectFree(value)) return null;
        // Preserve a side-effecting initialiser as a bare expression.
        return YulExpressionStatement(value);
      case YulBlock():
        return _dceBlock(s, reads, assigns);
      case YulIf(:final condition, :final body):
        return YulIf(condition, _dceBlock(body, reads, assigns));
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        return YulForLoop(
          _dceBlock(pre, reads, assigns),
          condition,
          _dceBlock(post, reads, assigns),
          _dceBlock(body, reads, assigns),
        );
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        return YulSwitch(
          expression,
          cases
              .map((c) => YulCase(c.value, _dceBlock(c.body, reads, assigns)))
              .toList(),
          defaultCase == null ? null : _dceBlock(defaultCase, reads, assigns),
        );
      case YulFunctionDefinition(
        :final name,
        :final parameters,
        :final returnVariables,
        :final body,
      ):
        // Re-run full local analysis inside the function body.
        return YulFunctionDefinition(
          name,
          parameters,
          returnVariables,
          _eliminateDead(body),
        );
      default:
        return s;
    }
  }

  static bool _isTerminator(YulStatement s) {
    if (s is YulBreak || s is YulContinue || s is YulLeave) return true;
    if (s is YulExpressionStatement) {
      final e = s.expression;
      return e is YulFunctionCall && _terminatingBuiltins.contains(e.name);
    }
    return false;
  }

  static const _terminatingBuiltins = {
    'return',
    'revert',
    'stop',
    'invalid',
    'selfdestruct',
  };

  void _collectUses(YulNode node, Set<String> reads, Set<String> assigns) {
    switch (node) {
      case YulIdentifier(:final name):
        reads.add(name);
      case YulFunctionCall(:final arguments):
        for (final a in arguments) {
          _collectUses(a, reads, assigns);
        }
      case YulAssignment(:final variables, :final value):
        assigns.addAll(variables);
        _collectUses(value, reads, assigns);
      case YulVariableDeclaration(:final value):
        if (value != null) _collectUses(value, reads, assigns);
      case YulExpressionStatement(:final expression):
        _collectUses(expression, reads, assigns);
      case YulBlock(:final statements):
        for (final s in statements) {
          _collectUses(s, reads, assigns);
        }
      case YulIf(:final condition, :final body):
        _collectUses(condition, reads, assigns);
        _collectUses(body, reads, assigns);
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        _collectUses(expression, reads, assigns);
        for (final c in cases) {
          _collectUses(c.body, reads, assigns);
        }
        if (defaultCase != null) _collectUses(defaultCase, reads, assigns);
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        _collectUses(pre, reads, assigns);
        _collectUses(condition, reads, assigns);
        _collectUses(post, reads, assigns);
        _collectUses(body, reads, assigns);
      case YulFunctionDefinition(:final body):
        _collectUses(body, reads, assigns);
      default:
        break;
    }
  }

  // ── Constant folding ──────────────────────────────────────────────────────

  List<BigInt>? _asConstants(List<YulExpression> args) {
    final out = <BigInt>[];
    for (final a in args) {
      final v = _constValue(a);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  /// Returns the literal value of [e], or null if it is not a numeric literal.
  BigInt? _constValue(YulExpression e) {
    if (e is! YulLiteral) return null;
    switch (e.kind) {
      case YulLiteralKind.number:
        final v = e.value.replaceAll('_', '');
        final n = v.startsWith('0x') || v.startsWith('0X')
            ? BigInt.tryParse(v.substring(2), radix: 16)
            : BigInt.tryParse(v);
        return n == null ? null : n & _mask;
      case YulLiteralKind.bool$:
        return e.value == 'true' ? BigInt.one : BigInt.zero;
      case YulLiteralKind.string:
        return null;
    }
  }

  YulLiteral _numLiteral(BigInt v) =>
      YulLiteral((v & _mask).toString(), YulLiteralKind.number);

  BigInt? _fold(String op, List<BigInt> a) {
    BigInt u(int i) => a[i] & _mask;
    BigInt s(int i) => _toSigned(a[i]);
    switch (op) {
      case 'add' when a.length == 2:
        return (u(0) + u(1)) & _mask;
      case 'sub' when a.length == 2:
        return (u(0) - u(1)) & _mask;
      case 'mul' when a.length == 2:
        return (u(0) * u(1)) & _mask;
      case 'div' when a.length == 2:
        return u(1) == BigInt.zero ? BigInt.zero : u(0) ~/ u(1);
      case 'sdiv' when a.length == 2:
        return s(1) == BigInt.zero ? BigInt.zero : (s(0) ~/ s(1)) & _mask;
      case 'mod' when a.length == 2:
        return u(1) == BigInt.zero ? BigInt.zero : u(0) % u(1);
      case 'smod' when a.length == 2:
        return s(1) == BigInt.zero
            ? BigInt.zero
            : (s(0).remainder(s(1))) & _mask;
      case 'exp' when a.length == 2:
        return u(0).modPow(u(1), BigInt.one << 256);
      case 'not' when a.length == 1:
        return _mask - u(0);
      case 'lt' when a.length == 2:
        return u(0) < u(1) ? BigInt.one : BigInt.zero;
      case 'gt' when a.length == 2:
        return u(0) > u(1) ? BigInt.one : BigInt.zero;
      case 'slt' when a.length == 2:
        return s(0) < s(1) ? BigInt.one : BigInt.zero;
      case 'sgt' when a.length == 2:
        return s(0) > s(1) ? BigInt.one : BigInt.zero;
      case 'eq' when a.length == 2:
        return u(0) == u(1) ? BigInt.one : BigInt.zero;
      case 'iszero' when a.length == 1:
        return u(0) == BigInt.zero ? BigInt.one : BigInt.zero;
      case 'and' when a.length == 2:
        return u(0) & u(1);
      case 'or' when a.length == 2:
        return u(0) | u(1);
      case 'xor' when a.length == 2:
        return u(0) ^ u(1);
      case 'shl' when a.length == 2:
        return u(0) >= BigInt.from(256)
            ? BigInt.zero
            : (u(1) << u(0).toInt()) & _mask;
      case 'shr' when a.length == 2:
        return u(0) >= BigInt.from(256) ? BigInt.zero : u(1) >> u(0).toInt();
      case 'sar' when a.length == 2:
        return _sar(u(0), a[1]);
      case 'byte' when a.length == 2:
        if (u(0) >= BigInt.from(32)) return BigInt.zero;
        final shift = (31 - u(0).toInt()) * 8;
        return (u(1) >> shift) & BigInt.from(0xff);
      case 'signextend' when a.length == 2:
        return _signextend(u(0), u(1));
      case 'addmod' when a.length == 3:
        return u(2) == BigInt.zero ? BigInt.zero : (u(0) + u(1)) % u(2);
      case 'mulmod' when a.length == 3:
        return u(2) == BigInt.zero ? BigInt.zero : (u(0) * u(1)) % u(2);
      default:
        return null;
    }
  }

  BigInt _sar(BigInt shift, BigInt value) {
    final v = _toSigned(value);
    if (shift >= BigInt.from(256)) return v.isNegative ? _mask : BigInt.zero;
    return (v >> shift.toInt()) & _mask;
  }

  BigInt _signextend(BigInt b, BigInt x) {
    if (b >= BigInt.from(31)) return x & _mask;
    final bits = (b.toInt() + 1) * 8;
    final signBit = BigInt.one << (bits - 1);
    final mask = (BigInt.one << bits) - BigInt.one;
    final lower = x & mask;
    return (lower & signBit) != BigInt.zero ? (lower | (~mask & _mask)) : lower;
  }

  static BigInt _toSigned(BigInt v) {
    final u = v & _mask;
    return (u & _signBit) != BigInt.zero ? u - (BigInt.one << 256) : u;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isSideEffectFree(YulExpression e) {
    switch (e) {
      case YulLiteral():
      case YulIdentifier():
        return true;
      case YulFunctionCall(:final name, :final arguments):
        return _pureBuiltins.contains(name) &&
            arguments.every(_isSideEffectFree);
    }
  }

  bool _printEq(YulNode a, YulNode b) => _Stringify.of(a) == _Stringify.of(b);

  /// Built-ins with no state/memory/control side effects (safe to drop).
  static const _pureBuiltins = {
    'add', 'sub', 'mul', 'div', 'sdiv', 'mod', 'smod', 'exp', 'not',
    'lt', 'gt', 'slt', 'sgt', 'eq', 'iszero', 'and', 'or', 'xor', 'byte',
    'shl', 'shr', 'sar', 'addmod', 'mulmod', 'signextend',
    // environment reads (no writes):
    'address', 'caller', 'callvalue', 'calldatasize', 'calldataload',
    'codesize', 'gas', 'timestamp', 'number', 'chainid', 'origin',
    'gasprice', 'coinbase', 'gaslimit', 'basefee', 'selfbalance',
    'mload', 'sload', 'msize', 'returndatasize',
  };
}

/// A minimal structural fingerprint of a Yul subtree, used only to detect
/// fixed-point convergence between optimiser passes.
class _Stringify {
  static String of(YulNode node) {
    final b = StringBuffer();
    _write(node, b);
    return b.toString();
  }

  static void _write(YulNode node, StringBuffer b) {
    switch (node) {
      case YulObject(:final name, :final code, :final subObjects):
        b.write('obj($name');
        _write(code, b);
        for (final s in subObjects) {
          _write(s, b);
        }
        b.write(')');
      case YulBlock(:final statements):
        b.write('{');
        for (final s in statements) {
          _write(s, b);
          b.write(';');
        }
        b.write('}');
      case YulFunctionDefinition(
        :final name,
        :final parameters,
        :final returnVariables,
        :final body,
      ):
        b.write(
          'fn $name(${parameters.join(',')})->${returnVariables.join(',')}',
        );
        _write(body, b);
      case YulVariableDeclaration(:final variables, :final value):
        b.write('let ${variables.join(',')}=');
        if (value != null) _write(value, b);
      case YulAssignment(:final variables, :final value):
        b.write('${variables.join(',')}=');
        _write(value, b);
      case YulExpressionStatement(:final expression):
        _write(expression, b);
      case YulIf(:final condition, :final body):
        b.write('if');
        _write(condition, b);
        _write(body, b);
      case YulSwitch(:final expression, :final cases, :final defaultCase):
        b.write('switch');
        _write(expression, b);
        for (final c in cases) {
          b.write('case ${c.value.value}');
          _write(c.body, b);
        }
        if (defaultCase != null) {
          b.write('default');
          _write(defaultCase, b);
        }
      case YulForLoop(:final pre, :final condition, :final post, :final body):
        b.write('for');
        _write(pre, b);
        _write(condition, b);
        _write(post, b);
        _write(body, b);
      case YulBreak():
        b.write('break');
      case YulContinue():
        b.write('continue');
      case YulLeave():
        b.write('leave');
      case YulLiteral(:final value, :final kind):
        b.write('$value:${kind.name}');
      case YulIdentifier(:final name):
        b.write(name);
      case YulFunctionCall(:final name, :final arguments):
        b.write('$name(');
        for (final a in arguments) {
          _write(a, b);
          b.write(',');
        }
        b.write(')');
      case YulCase():
        break;
    }
  }
}
