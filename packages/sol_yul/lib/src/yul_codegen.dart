import 'dart:typed_data';
import 'package:sol_evm/sol_evm.dart';
import 'yul_ast.dart';

/// Compiles a [YulObject] to EVM bytecode.
///
/// This is a simple non-optimising code generator.  The optimiser pipeline
/// (SSA, DCE, inline, …) will be layered on top in a later iteration.
class YulCodeGenerator {
  final Assembler _asm = Assembler();
  int _labelCounter = 0;

  Uint8List generate(YulObject obj) {
    _generateBlock(obj.code);
    return _asm.assemble();
  }

  void _generateBlock(YulBlock block) {
    for (final stmt in block.statements) {
      _generateStatement(stmt);
    }
  }

  void _generateStatement(YulStatement stmt) {
    switch (stmt) {
      case YulBlock():
        _generateBlock(stmt);

      case YulExpressionStatement(:final expression):
        _generateExpression(expression);
        // Yul expression statements consume their result if any
        // For function calls the result is intentionally left on stack
        // or discarded; the Yul type system handles this.

      case YulVariableDeclaration(:final variables, :final value):
        if (value != null) {
          _generateExpression(value);
        } else {
          _asm.emit(Opcode.PUSH0);
        }
        // Variables are tracked by position; for now just comment their name.
        // A proper implementation would use a variable → stack-slot map.
        if (variables.length > 1) {
          // multi-assign: value must be a multi-return function call
          // leave stack values in order
        }

      case YulAssignment(:final value):
        _generateExpression(value);
        // TODO: pop into variable slot

      case YulIf(:final condition, :final body):
        final elseLabel = _freshLabel('if_end');
        _generateExpression(condition);
        _asm.emit(Opcode.ISZERO);
        _asm.jumpi(elseLabel);
        _generateBlock(body);
        _asm.label(elseLabel);

      case YulForLoop(:final pre, :final condition, :final post, :final body):
        final loopStart = _freshLabel('loop');
        final loopEnd = _freshLabel('loop_end');
        _generateBlock(pre);
        _asm.label(loopStart);
        _generateExpression(condition);
        _asm.emit(Opcode.ISZERO);
        _asm.jumpi(loopEnd);
        _generateBlock(body);
        _generateBlock(post);
        _asm.jump(loopStart);
        _asm.label(loopEnd);

      case YulSwitch(:final expression, :final cases, :final defaultCase):
        final endLabel = _freshLabel('switch_end');
        for (final c in cases) {
          final nextLabel = _freshLabel('case');
          _generateExpression(expression);
          _generateExpression(c.value);
          _asm.emit(Opcode.EQ);
          _asm.emit(Opcode.ISZERO);
          _asm.jumpi(nextLabel);
          _generateBlock(c.body);
          _asm.jump(endLabel);
          _asm.label(nextLabel);
        }
        if (defaultCase != null) _generateBlock(defaultCase);
        _asm.label(endLabel);

      case YulFunctionDefinition():
        // Function definitions are hoisted; stubs only for now.
        break;

      case YulBreak():
        // Handled by loop context; requires label threading.
        break;

      case YulContinue():
        break;

      case YulLeave():
        _asm.ret();
    }
  }

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
            // String literals in Yul are padded to 32 bytes (left-aligned).
            final bytes = value.codeUnits;
            var n = BigInt.zero;
            for (final b in bytes) {
              n = (n << 8) | BigInt.from(b);
            }
            n <<= (32 - bytes.length) * 8;
            _asm.push(n);
        }

      case YulIdentifier():
        // Variable reference — push from stack slot; stub for now.
        _asm.emit(Opcode.PUSH0);

      case YulFunctionCall(:final name, :final arguments):
        // Evaluate arguments right-to-left (EVM convention).
        for (final arg in arguments.reversed) {
          _generateExpression(arg);
        }
        _generateBuiltin(name, arguments.length);
    }
  }

  void _generateBuiltin(String name, int arity) {
    final op = _builtinOpcodes[name];
    if (op != null) {
      _asm.emit(op);
      return;
    }
    // User-defined function call: PUSH2 target + JUMP
    _asm.jump(name);
  }

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
    'caller': Opcode.CALLER,
    'callvalue': Opcode.CALLVALUE,
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

  String _freshLabel(String prefix) => '${prefix}_${_labelCounter++}';
}
