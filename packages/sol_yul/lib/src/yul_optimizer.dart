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
///
/// The optimiser is purely AST→AST and never changes observable behaviour.
class YulOptimizer {
  const YulOptimizer({this.maxPasses = 10});

  /// Upper bound on fixed-point iterations (a safety net; convergence is
  /// usually reached in 1–2 passes).
  final int maxPasses;

  static final BigInt _mask = (BigInt.one << 256) - BigInt.one;
  static final BigInt _signBit = BigInt.one << 255;

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
      final next = _eliminateDead(_block(current));
      if (_printEq(next, current)) return next;
      current = next;
    }
    return current;
  }

  // ── Statement / block transformation (fold + simplify) ──────────────────────

  YulBlock _block(YulBlock block) =>
      YulBlock(block.statements.map(_statement).toList());

  YulStatement _statement(YulStatement s) {
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
