import 'dart:typed_data';
import 'package:sol_evm/sol_evm.dart';
import 'yul_ast.dart';

/// Tracks the EVM stack as a list of named slots.
///
/// Index 0 = top of stack. Null name means an anonymous (temporary) value.
class _Frame {
  final List<String?> _slots = [];

  void push([String? name]) => _slots.insert(0, name);

  void pop() {
    assert(_slots.isNotEmpty, '_Frame underflow');
    _slots.removeAt(0);
  }

  /// 1-indexed depth from the top (1 = top).
  int depthOf(String name) {
    final i = _slots.indexOf(name);
    if (i < 0) throw StateError('Variable "$name" not on EVM stack');
    return i + 1;
  }

  bool contains(String name) => _slots.contains(name);
  int get size => _slots.length;
}

class _LoopContext {
  _LoopContext({required this.breakLabel, required this.continueLabel});
  final String breakLabel;
  final String continueLabel;
}

class _FunctionContext {
  _FunctionContext({required this.paramCount, required this.returnCount});
  final int paramCount;
  final int returnCount;
}

/// Compiles a [YulObject] to EVM bytecode.
///
/// Supports variables (single-assignment and re-assignment), if, for, switch,
/// user-defined Yul functions (0–1 return values), break, continue, and leave.
class YulCodeGenerator {
  final Assembler _asm = Assembler();
  _Frame _frame = _Frame();
  final List<_LoopContext> _loopStack = [];
  _FunctionContext? _currentFunction;
  int _labelCounter = 0;

  /// Number of return values for each user-defined function, so call sites know
  /// how many results to keep/pop (void functions leave none).
  final Map<String, int> _functionReturnCounts = {};

  /// The name and byte size of the embedded deployed (runtime) sub-object,
  /// used to resolve `dataoffset(...)` / `datasize(...)` in creation code.
  String? _deployedName;
  int _deployedSize = 0;

  /// Generates the **creation** bytecode for [obj].
  ///
  /// When [obj] has a deployed sub-object (the runtime code), it is compiled
  /// separately and concatenated after the creation code; `dataoffset` /
  /// `datasize` references in the creation code resolve to its location/size.
  Uint8List generate(YulObject obj) {
    if (obj.subObjects.isNotEmpty) {
      final deployed = obj.subObjects.first;
      final runtimeBytes = YulCodeGenerator().generate(deployed);
      _deployedName = deployed.name;
      _deployedSize = runtimeBytes.length;

      _generateBlock(obj.code, hoistFunctions: true);
      final creation = _asm.assemble();

      final out = Uint8List(creation.length + runtimeBytes.length);
      out.setRange(0, creation.length, creation);
      out.setRange(creation.length, out.length, runtimeBytes);
      return out;
    }
    _generateBlock(obj.code, hoistFunctions: true);
    return _asm.assemble();
  }

  /// Generates only the **deployed** (runtime) bytecode for [obj].
  ///
  /// This is the code that ends up stored on-chain (no constructor / deploy
  /// wrapper). Returns the sub-object's bytecode, or [obj]'s own code if it has
  /// no sub-object.
  Uint8List generateDeployed(YulObject obj) => obj.subObjects.isNotEmpty
      ? YulCodeGenerator().generate(obj.subObjects.first)
      : YulCodeGenerator().generate(obj);

  // ── Block generation ────────────────────────────────────────────────────────

  void _generateBlock(YulBlock block, {bool hoistFunctions = false}) {
    // Emit function definitions (hoisted) first so they are always reachable.
    if (hoistFunctions) {
      // Record arities up front so calls — including forward references and
      // mutual recursion — know how many results each function leaves.
      for (final stmt in block.statements) {
        if (stmt is YulFunctionDefinition) {
          _functionReturnCounts[stmt.name] = stmt.returnVariables.length;
        }
      }
      for (final stmt in block.statements) {
        if (stmt is YulFunctionDefinition) _generateFunctionDefinition(stmt);
      }
    }
    for (final stmt in block.statements) {
      if (stmt is! YulFunctionDefinition) _generateStatement(stmt);
    }
  }

  // ── Statements ──────────────────────────────────────────────────────────────

  void _generateStatement(YulStatement stmt) {
    switch (stmt) {
      case YulBlock():
        _generateBlock(stmt);

      case YulFunctionDefinition():
        // Already hoisted — skip inline occurrence.
        break;

      case YulVariableDeclaration(:final variables, :final value):
        if (variables.length == 1) {
          // Single variable: produce the value, then name the slot it left on
          // top. _generateExpression already pushes one (anonymous) slot, so
          // rename it rather than pushing a second — otherwise the frame model
          // drifts from the real stack and later DUP depths are wrong.
          if (value != null) {
            _generateExpression(value);
            _frame.pop(); // drop the anonymous result slot…
            _frame.push(variables.first); // …and re-add it under its name.
          } else {
            _asm.emit(Opcode.PUSH0);
            _frame.push(variables.first);
          }
        } else {
          // Multi-variable: value must be a multi-return function call.
          // Each return value is already on the stack after _generateExpression.
          if (value != null) {
            _generateExpression(value);
            // Stack has [last_ret, ..., first_ret] after the call.
            // Name the slots in declaration order.
            for (var i = variables.length - 1; i >= 0; i--) {
              _frame.push(variables[i]);
            }
          } else {
            for (var i = variables.length - 1; i >= 0; i--) {
              _asm.emit(Opcode.PUSH0);
              _frame.push(variables[i]);
            }
          }
        }

      case YulAssignment(:final variables, :final value):
        if (variables.length == 1) {
          final name = variables.first;
          final dBefore = _frame.depthOf(name); // 1-indexed before eval
          _generateExpression(value);
          // Stack: [new_val, ..., old_name_val, ...]
          // SWAP(dBefore) swaps 0-indexed positions 0 and dBefore.
          // = EVM SWAPdBefore: swaps depth-1 with depth-(dBefore+1).
          // After swap: old_name_val at top, new_val in name's slot.
          _asm.swap(dBefore);
          _asm.pop(); // discard old value
          _frame.pop(); // remove the anonymous eval-result slot from model
        } else {
          // Multi-variable assignment: evaluate call, then assign each.
          _generateExpression(value);
          for (var i = variables.length - 1; i >= 0; i--) {
            final name = variables[i];
            // After eval, the i-th return val is at top for i==last, etc.
            // Each is assigned independently via swap+pop.
            final d = _frame.depthOf(name);
            _asm.swap(d);
            _asm.pop();
            _frame.pop();
          }
        }

      case YulExpressionStatement(:final expression):
        _generateExpression(expression);
        // Expression statements must not leave a value on the stack.
        // Yul builtins that return nothing: stop, revert, etc. — handled.
        // User-defined Yul function calls always leave return values;
        // pop them.
        _popExpressionResult(expression);

      case YulIf(:final condition, :final body):
        final endLabel = _freshLabel('if_end');
        _generateExpression(condition);
        _frame.pop(); // condition consumed
        _asm.emit(Opcode.ISZERO);
        _asm.jumpi(endLabel);
        _generateBlock(body);
        _asm.label(endLabel);

      case YulForLoop(:final pre, :final condition, :final post, :final body):
        final startLabel = _freshLabel('loop');
        final postLabel = _freshLabel('loop_post');
        final endLabel = _freshLabel('loop_end');
        _generateBlock(pre);
        _asm.label(startLabel);
        _generateExpression(condition);
        _frame.pop(); // condition consumed
        _asm.emit(Opcode.ISZERO);
        _asm.jumpi(endLabel);
        _loopStack.add(
          _LoopContext(breakLabel: endLabel, continueLabel: postLabel),
        );
        _generateBlock(body);
        _loopStack.removeLast();
        _asm.label(postLabel);
        _generateBlock(post);
        _asm.jump(startLabel);
        _asm.label(endLabel);

      case YulSwitch(:final expression, :final cases, :final defaultCase):
        final endLabel = _freshLabel('switch_end');
        for (final c in cases) {
          final nextLabel = _freshLabel('case');
          _generateExpression(expression);
          _generateExpression(c.value);
          _asm.emit(Opcode.EQ);
          _asm.emit(Opcode.ISZERO);
          _frame.pop(); // EQ result consumed by JUMPI
          _asm.jumpi(nextLabel);
          _generateBlock(c.body);
          _asm.jump(endLabel);
          _asm.label(nextLabel);
        }
        if (defaultCase != null) _generateBlock(defaultCase);
        _asm.label(endLabel);

      case YulBreak():
        if (_loopStack.isNotEmpty) {
          _asm.jump(_loopStack.last.breakLabel);
        }

      case YulContinue():
        if (_loopStack.isNotEmpty) {
          _asm.jump(_loopStack.last.continueLabel);
        }

      case YulLeave():
        _emitLeave();
    }
  }

  // ── Expressions ─────────────────────────────────────────────────────────────

  void _generateExpression(YulExpression expr) {
    switch (expr) {
      case YulLiteral(:final value, :final kind):
        switch (kind) {
          case YulLiteralKind.number:
            final n = value.startsWith('0x')
                ? BigInt.parse(value.substring(2), radix: 16)
                : BigInt.parse(value);
            if (n == BigInt.zero) {
              _asm.emit(Opcode.PUSH0);
            } else {
              _asm.push(n);
            }
          case YulLiteralKind.bool$:
            _asm.push1(value == 'true' ? 1 : 0);
          case YulLiteralKind.string:
            final bytes = value.codeUnits;
            var n = BigInt.zero;
            for (final b in bytes) {
              n = (n << 8) | BigInt.from(b);
            }
            n <<= (32 - bytes.length) * 8;
            _asm.push(n);
        }
        _frame.push(); // anonymous value

      case YulIdentifier(:final name):
        final d = _frame.depthOf(name);
        if (d == 1) {
          _asm.dup(1); // DUP1 duplicates top
        } else {
          _asm.dup(d); // DUP(d) duplicates item at depth d
        }
        _frame.push(); // anonymous duplicate on top

      case YulFunctionCall(:final name, :final arguments):
        _generateCall(name, arguments);
    }
  }

  void _generateCall(String name, List<YulExpression> arguments) {
    // Object-data references resolve to compile-time constants, not opcodes.
    if (name == 'dataoffset') {
      _asm.pushDeployedOffset();
      _frame.push();
      return;
    }
    if (name == 'datasize') {
      _asm.push(BigInt.from(_dataSize(arguments)));
      _frame.push();
      return;
    }

    final builtin = _builtinOpcodes[name];
    if (builtin != null) {
      // Push args right-to-left so arg[0] is on top.
      for (final arg in arguments.reversed) {
        _generateExpression(arg);
      }
      // Consume all arg slots from frame.
      for (var i = 0; i < arguments.length; i++) {
        _frame.pop();
      }
      _asm.emit(builtin);
      // Most builtins push 1 result; zero-output builtins (stop, revert, etc.)
      // are handled by _popExpressionResult checking the statement context.
      if (_builtinPushesResult(name)) _frame.push();
    } else {
      // User-defined Yul function call.
      // Convention: PUSH retlabel, push args right-to-left, JUMP fn_name.
      // The function leaves its M return values on the stack after returning.
      final retCount = _functionReturnCounts[name] ?? 1;
      final retLabel = _freshLabel('ret');
      _asm.pushLabel(retLabel);
      _frame.push(); // retlabel slot

      for (final arg in arguments.reversed) {
        _generateExpression(arg);
      }
      // args are on frame as anonymous slots
      _asm.jump(name);
      _asm.label(retLabel); // JUMPDEST — function has cleaned up and returned

      // After return: N+1 slots (retlabel + args) are gone; M return values remain.
      for (var i = 0; i < arguments.length + 1; i++) {
        _frame.pop();
      }
      for (var i = 0; i < retCount; i++) {
        _frame.push(); // one slot per return value (none for void functions)
      }
    }
  }

  bool _builtinPushesResult(String name) {
    return !_builtinVoidOpcodes.contains(name);
  }

  /// Pop the result of an expression used as a statement (if it produced one).
  void _popExpressionResult(YulExpression expr) {
    switch (expr) {
      case YulFunctionCall(:final name):
        final builtin = _builtinOpcodes[name];
        if (builtin != null) {
          if (_builtinPushesResult(name)) {
            _asm.pop();
            _frame.pop();
          }
        } else {
          // User function: pop each of its return values (none for void).
          final retCount = _functionReturnCounts[name] ?? 1;
          for (var i = 0; i < retCount; i++) {
            _asm.pop();
            _frame.pop();
          }
        }
      default:
        // Literals and identifiers leave a value; pop it.
        _asm.pop();
        _frame.pop();
    }
  }

  // ── Function definitions ────────────────────────────────────────────────────

  void _generateFunctionDefinition(YulFunctionDefinition fn) {
    final endLabel = _freshLabel('fn_${fn.name}_skip');

    // Jump over the function body so it doesn't fall through.
    _asm.jump(endLabel);
    _asm.label(fn.name); // JUMPDEST — the callable entry point

    // Save outer context.
    final outerFrame = _frame;
    final outerFunction = _currentFunction;
    final outerLoops = List<_LoopContext>.from(_loopStack);
    _loopStack.clear();

    // Set up function frame.
    // Stack layout on entry (top→bottom):
    //   arg0, arg1, ..., argN-1, retlabel, ...outer...
    // We push M zeros for return vars ON TOP of params:
    //   rM-1, ..., r0, arg0, ..., argN-1, retlabel, ...outer...
    //
    // Frame model (top = index 0):
    //   [rM-1, ..., r0, p0, p1, ..., pN-1, _ret_, ...outer...]
    //
    // Build model bottom-up (push inserts at index 0):
    _frame = _Frame();
    // The retlabel and outer stack are beneath us; just record '_ret_'.
    _frame.push('_ret_');
    // Params above retlabel (p0 at top, pN-1 deeper).
    for (final p in fn.parameters.reversed) {
      _frame.push(p);
    }
    // Allocate return variable slots (push zeros on the real stack).
    for (final rv in fn.returnVariables.reversed) {
      _asm.emit(Opcode.PUSH0);
      _frame.push(rv);
    }

    _currentFunction = _FunctionContext(
      paramCount: fn.parameters.length,
      returnCount: fn.returnVariables.length,
    );

    // Generate body (inner functions are hoisted within the block).
    _generateBlock(fn.body, hoistFunctions: true);

    // Implicit leave at end of function body.
    _emitLeave();

    // Restore outer context.
    _frame = outerFrame;
    _currentFunction = outerFunction;
    _loopStack
      ..clear()
      ..addAll(outerLoops);

    _asm.label(endLabel); // JUMPDEST — skip target
  }

  /// Emits the cleanup sequence for leaving a function.
  ///
  /// Stack before leave (M return vars, N params):
  ///   [rM-1, ..., r0, p0, ..., pN-1, retlabel, ...outer...]
  ///
  /// Target after leave:
  ///   [rM-1, ..., r0, ...outer...]  (jumped to retlabel)
  void _emitLeave() {
    final ctx = _currentFunction;
    if (ctx == null) {
      // Top-level leave: just stop.
      _asm.emit(Opcode.STOP);
      return;
    }
    final m = ctx.returnCount;
    final n = ctx.paramCount;

    // Locals declared in the body sit above the return-value slots. Discard
    // them so the stack is exactly [returns, params, retlabel] before cleanup.
    // (The frame model is intentionally left untouched: control-flow leaves the
    // function, but any following fall-through code keeps the same model.)
    final locals = _frame.size - (m + n + 1);
    for (var i = 0; i < locals; i++) {
      _asm.pop();
    }

    if (m == 0) {
      // No return values: pop params, then JUMP to retlabel.
      for (var i = 0; i < n; i++) {
        _asm.pop();
      }
      _asm.emit(Opcode.JUMP);
      return;
    }

    // General case for M ≥ 1 return values (requires M ≤ 16 for SWAPM).
    //
    // Stack (top→bottom): [r0, …, r(M-1), p0, …, p(N-1), retlabel, …outer].
    //
    // 1. Delete each parameter. The topmost parameter always sits at depth
    //    M+1; SWAP1..SWAPM bubble it to the top while preserving the order of
    //    the M return values above it, then POP removes it.
    for (var i = 0; i < n; i++) {
      for (var s = 1; s <= m; s++) {
        _asm.swap(s);
      }
      _asm.pop();
    }

    // 2. Now the stack is [r0, …, r(M-1), retlabel, …outer]. Rotate the
    //    (M+1)-element block down by one (SWAP1..SWAPM) so retlabel reaches the
    //    top with the return values still in order beneath it…
    for (var s = 1; s <= m; s++) {
      _asm.swap(s);
    }
    // …then JUMP consumes retlabel, leaving [r0, …, r(M-1), …outer] for the
    // caller (r0 on top), matching the multi-value call/declaration layout.
    _asm.emit(Opcode.JUMP);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _freshLabel(String prefix) => '${prefix}_${_labelCounter++}';

  /// Size in bytes of the data object named by [arguments] (a single string
  /// literal). Only the embedded deployed sub-object is currently known.
  int _dataSize(List<YulExpression> arguments) {
    if (arguments.length == 1) {
      final arg = arguments.first;
      // String-literal values keep their surrounding quotes for the printer.
      if (arg is YulLiteral && _unquote(arg.value) == _deployedName) {
        return _deployedSize;
      }
    }
    return _deployedSize;
  }

  static String _unquote(String s) =>
      (s.length >= 2 && s.startsWith('"') && s.endsWith('"'))
      ? s.substring(1, s.length - 1)
      : s;

  // ── Builtin opcode tables ────────────────────────────────────────────────────

  static const _builtinOpcodes = {
    'add': Opcode.ADD,
    'sub': Opcode.SUB,
    'mul': Opcode.MUL,
    'div': Opcode.DIV,
    'sdiv': Opcode.SDIV,
    'mod': Opcode.MOD,
    'smod': Opcode.SMOD,
    'exp': Opcode.EXP,
    'not': Opcode.NOT,
    'lt': Opcode.LT,
    'gt': Opcode.GT,
    'slt': Opcode.SLT,
    'sgt': Opcode.SGT,
    'eq': Opcode.EQ,
    'iszero': Opcode.ISZERO,
    'and': Opcode.AND,
    'or': Opcode.OR,
    'xor': Opcode.XOR,
    'byte': Opcode.BYTE,
    'shl': Opcode.SHL,
    'shr': Opcode.SHR,
    'sar': Opcode.SAR,
    'addmod': Opcode.ADDMOD,
    'mulmod': Opcode.MULMOD,
    'signextend': Opcode.SIGNEXTEND,
    'keccak256': Opcode.KECCAK256,
    'pop': Opcode.POP,
    'mload': Opcode.MLOAD,
    'mstore': Opcode.MSTORE,
    'mstore8': Opcode.MSTORE8,
    'sload': Opcode.SLOAD,
    'sstore': Opcode.SSTORE,
    'msize': Opcode.MSIZE,
    'gas': Opcode.GAS,
    'address': Opcode.ADDRESS,
    'balance': Opcode.BALANCE,
    'selfbalance': Opcode.SELFBALANCE,
    'caller': Opcode.CALLER,
    'callvalue': Opcode.CALLVALUE,
    'origin': Opcode.ORIGIN,
    'gasprice': Opcode.GASPRICE,
    'number': Opcode.NUMBER,
    'timestamp': Opcode.TIMESTAMP,
    'coinbase': Opcode.COINBASE,
    'gaslimit': Opcode.GASLIMIT,
    'chainid': Opcode.CHAINID,
    'basefee': Opcode.BASEFEE,
    'prevrandao': Opcode.PREVRANDAO,
    'calldataload': Opcode.CALLDATALOAD,
    'calldatasize': Opcode.CALLDATASIZE,
    'calldatacopy': Opcode.CALLDATACOPY,
    'codesize': Opcode.CODESIZE,
    'codecopy': Opcode.CODECOPY,
    'returndatasize': Opcode.RETURNDATASIZE,
    'returndatacopy': Opcode.RETURNDATACOPY,
    'extcodesize': Opcode.EXTCODESIZE,
    'extcodecopy': Opcode.EXTCODECOPY,
    'extcodehash': Opcode.EXTCODEHASH,
    'return': Opcode.RETURN,
    'revert': Opcode.REVERT,
    'stop': Opcode.STOP,
    'invalid': Opcode.INVALID,
    'log0': Opcode.LOG0,
    'log1': Opcode.LOG1,
    'log2': Opcode.LOG2,
    'log3': Opcode.LOG3,
    'log4': Opcode.LOG4,
    'call': Opcode.CALL,
    'callcode': Opcode.CALLCODE,
    'delegatecall': Opcode.DELEGATECALL,
    'staticcall': Opcode.STATICCALL,
    'create': Opcode.CREATE,
    'create2': Opcode.CREATE2,
    'selfdestruct': Opcode.SELFDESTRUCT,
  };

  /// Builtins that do not push a result onto the stack.
  ///
  /// Includes the terminating instructions (`return`, `stop`, …): they halt
  /// execution and leave nothing, so no result POP must follow them.
  static const _builtinVoidOpcodes = {
    'stop',
    'return',
    'revert',
    'invalid',
    'selfdestruct',
    'mstore',
    'mstore8',
    'sstore',
    'calldatacopy',
    'codecopy',
    'returndatacopy',
    'extcodecopy',
    'log0',
    'log1',
    'log2',
    'log3',
    'log4',
    'pop',
  };
}
