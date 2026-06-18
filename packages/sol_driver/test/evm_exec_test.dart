import 'dart:typed_data';
import 'package:sol_abi/sol_abi.dart';
import 'package:sol_driver/sol_driver.dart';
import 'package:test/test.dart';

/// A deliberately small EVM interpreter — just enough opcodes to *execute* the
/// runtime bytecode our compiler emits and assert on real behaviour. This turns
/// "compiles without error" into "actually computes the right answer".
class MiniEvm {
  MiniEvm(this.code) {
    // Pre-compute valid JUMPDEST positions, skipping PUSH immediate data.
    for (var i = 0; i < code.length;) {
      final op = code[i];
      if (op == 0x5b) jumpdests.add(i);
      if (op >= 0x60 && op <= 0x7f) {
        i += 1 + (op - 0x5f); // PUSH1..PUSH32 immediate width
      } else {
        i += 1;
      }
    }
  }

  final Uint8List code;
  final Set<int> jumpdests = {};
  final Map<BigInt, BigInt> storage = {};

  static final BigInt _mask = (BigInt.one << 256) - BigInt.one;

  /// Runs [calldata]; returns the RETURN data, or null on REVERT.
  Uint8List? call(Uint8List calldata) {
    final stack = <BigInt>[];
    final memory = <int, int>{}; // byte address → value
    var pc = 0;

    BigInt pop() => stack.removeLast();
    void push(BigInt v) => stack.add(v & _mask);

    BigInt loadWord(int Function(int) byteAt, int offset) {
      var v = BigInt.zero;
      for (var i = 0; i < 32; i++) {
        v = (v << 8) | BigInt.from(byteAt(offset + i) & 0xff);
      }
      return v;
    }

    void storeWord(int offset, BigInt value) {
      for (var i = 0; i < 32; i++) {
        memory[offset + i] = ((value >> (8 * (31 - i))) & BigInt.from(0xff)).toInt();
      }
    }

    int calldataByte(int i) => (i >= 0 && i < calldata.length) ? calldata[i] : 0;
    int memByte(int i) => memory[i] ?? 0;

    while (pc < code.length) {
      final op = code[pc];
      switch (op) {
        case 0x00: // STOP
          return Uint8List(0);
        case 0x01: push(pop() + pop()); pc++; // ADD
        case 0x02: push(pop() * pop()); pc++; // MUL
        case 0x03: final a = pop(); final b = pop(); push(a - b); pc++; // SUB
        case 0x04: // DIV
          final a = pop(); final b = pop();
          push(b == BigInt.zero ? BigInt.zero : a ~/ b); pc++;
        case 0x06: // MOD
          final a = pop(); final b = pop();
          push(b == BigInt.zero ? BigInt.zero : a % b); pc++;
        case 0x0a: // EXP
          final a = pop(); final b = pop();
          push(a.modPow(b, BigInt.one << 256)); pc++;
        case 0x10: final a = pop(); final b = pop(); push(a < b ? BigInt.one : BigInt.zero); pc++; // LT
        case 0x11: final a = pop(); final b = pop(); push(a > b ? BigInt.one : BigInt.zero); pc++; // GT
        case 0x14: push(pop() == pop() ? BigInt.one : BigInt.zero); pc++; // EQ
        case 0x15: push(pop() == BigInt.zero ? BigInt.one : BigInt.zero); pc++; // ISZERO
        case 0x16: push(pop() & pop()); pc++; // AND
        case 0x17: push(pop() | pop()); pc++; // OR
        case 0x18: push(pop() ^ pop()); pc++; // XOR
        case 0x19: push(~pop()); pc++; // NOT
        case 0x1b: // SHL(shift, value)
          final shift = pop(); final value = pop();
          push(shift >= BigInt.from(256) ? BigInt.zero : value << shift.toInt()); pc++;
        case 0x1c: // SHR(shift, value)
          final shift = pop(); final value = pop();
          push(shift >= BigInt.from(256) ? BigInt.zero : value >> shift.toInt()); pc++;
        case 0x35: push(loadWord(calldataByte, pop().toInt())); pc++; // CALLDATALOAD
        case 0x50: pop(); pc++; // POP
        case 0x51: push(loadWord(memByte, pop().toInt())); pc++; // MLOAD
        case 0x52: final off = pop(); final val = pop(); storeWord(off.toInt(), val); pc++; // MSTORE
        case 0x54: push(storage[pop()] ?? BigInt.zero); pc++; // SLOAD
        case 0x55: final k = pop(); final v = pop(); storage[k] = v; pc++; // SSTORE
        case 0x56: pc = _jump(pop()); // JUMP
        case 0x57: // JUMPI
          final dest = pop(); final cond = pop();
          pc = cond != BigInt.zero ? _jump(dest) : pc + 1;
        case 0x5b: pc++; // JUMPDEST
        case 0x5f: push(BigInt.zero); pc++; // PUSH0
        case 0xf3: // RETURN
          final off = pop().toInt(); final len = pop().toInt();
          final out = Uint8List(len);
          for (var i = 0; i < len; i++) out[i] = memByte(off + i);
          return out;
        case 0xfd: return null; // REVERT
        default:
          if (op >= 0x60 && op <= 0x7f) {
            final n = op - 0x5f; // PUSH1..PUSH32
            var v = BigInt.zero;
            for (var i = 0; i < n; i++) {
              v = (v << 8) | BigInt.from(code[pc + 1 + i] & 0xff);
            }
            push(v);
            pc += 1 + n;
          } else if (op >= 0x80 && op <= 0x8f) {
            final n = op - 0x7f; // DUP1..DUP16
            push(stack[stack.length - n]);
            pc++;
          } else if (op >= 0x90 && op <= 0x9f) {
            final n = op - 0x8f; // SWAP1..SWAP16
            final top = stack.length - 1;
            final tmp = stack[top];
            stack[top] = stack[top - n];
            stack[top - n] = tmp;
            pc++;
          } else {
            throw StateError('Unsupported opcode 0x${op.toRadixString(16)} at $pc');
          }
      }
    }
    return Uint8List(0);
  }

  int _jump(BigInt dest) {
    final d = dest.toInt();
    if (!jumpdests.contains(d)) throw StateError('Invalid jump destination $d');
    return d;
  }
}

Uint8List _calldata(String signature, List<int> args) {
  final sel = selectorHex(signature).substring(2);
  final out = BytesBuilder();
  for (var i = 0; i < 4; i++) {
    out.addByte(int.parse(sel.substring(i * 2, i * 2 + 2), radix: 16));
  }
  for (final a in args) {
    final word = Uint8List(32);
    var v = BigInt.from(a);
    for (var i = 31; i >= 0; i--) {
      word[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    out.add(word);
  }
  return out.toBytes();
}

BigInt _asUint(Uint8List? data) {
  expect(data, isNotNull, reason: 'call reverted');
  var v = BigInt.zero;
  for (final b in data!) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _runtimeOf(String source, String name) {
  final result = (CompilerStack()..addSource('$name.sol', source)).compile();
  expect(result.diagnostics.where((d) => d.isError), isEmpty,
      reason: result.diagnostics.map((d) => d.message).join('\n'));
  final c = result.contracts[name];
  expect(c, isNotNull);
  return c!.deployedBytecode;
}

void main() {
  group('executes compiled bytecode', () {
    test('Adder.getSum(2, 3) == 5', () {
      final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''', 'Adder');
      final out = MiniEvm(code).call(_calldata('getSum(uint256,uint256)', [2, 3]));
      expect(_asUint(out), BigInt.from(5));
    });

    test('Counter storage round-trips across calls', () {
      final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Counter {
  uint256 count;
  function increment() public { count = count + 1; }
  function setTo(uint256 x) public { count = x; }
  function get() public view returns (uint256) { return count; }
}
''', 'Counter');
      final evm = MiniEvm(code); // shared storage across calls

      expect(_asUint(evm.call(_calldata('get()', []))), BigInt.zero);
      evm.call(_calldata('setTo(uint256)', [7]));
      expect(_asUint(evm.call(_calldata('get()', []))), BigInt.from(7));
      evm.call(_calldata('increment()', []));
      evm.call(_calldata('increment()', []));
      expect(_asUint(evm.call(_calldata('get()', []))), BigInt.from(9));
    });

    test('Loop sumTo(n) computes 0+1+…+(n-1)', () {
      final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Loop {
  function sumTo(uint256 n) public pure returns (uint256) {
    uint256 s = 0;
    for (uint256 i = 0; i < n; i++) {
      s = s + i;
    }
    return s;
  }
}
''', 'Loop');
      expect(_asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [5]))),
          BigInt.from(10)); // 0+1+2+3+4
      expect(_asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [1]))),
          BigInt.zero);
      expect(_asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [10]))),
          BigInt.from(45));
    });

    test('comparison operators', () {
      final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Cmp {
  function ne(uint256 a, uint256 b) public pure returns (bool) { return a != b; }
  function le(uint256 a, uint256 b) public pure returns (bool) { return a <= b; }
}
''', 'Cmp');
      final evm = MiniEvm(code);
      expect(_asUint(evm.call(_calldata('ne(uint256,uint256)', [1, 2]))), BigInt.one);
      expect(_asUint(evm.call(_calldata('ne(uint256,uint256)', [2, 2]))), BigInt.zero);
      expect(_asUint(evm.call(_calldata('le(uint256,uint256)', [2, 3]))), BigInt.one);
      expect(_asUint(evm.call(_calldata('le(uint256,uint256)', [3, 3]))), BigInt.one);
      expect(_asUint(evm.call(_calldata('le(uint256,uint256)', [4, 3]))), BigInt.zero);
    });
  });
}
