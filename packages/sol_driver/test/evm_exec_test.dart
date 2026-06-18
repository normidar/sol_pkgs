import 'dart:typed_data';
import 'package:sol_abi/sol_abi.dart';
import 'package:sol_driver/sol_driver.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_yul/sol_yul.dart';
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

  /// `msg.sender` returned by CALLER (overridable per test).
  BigInt caller = BigInt.parse(
    '00000000000000000000000000000000000000aa',
    radix: 16,
  );

  /// Emitted logs: each is (topics, data).
  final List<({List<BigInt> topics, Uint8List data})> logs = [];

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
        memory[offset + i] = ((value >> (8 * (31 - i))) & BigInt.from(0xff))
            .toInt();
      }
    }

    int calldataByte(int i) =>
        (i >= 0 && i < calldata.length) ? calldata[i] : 0;
    int memByte(int i) => memory[i] ?? 0;

    while (pc < code.length) {
      final op = code[pc];
      switch (op) {
        case 0x00: // STOP
          return Uint8List(0);
        case 0x01:
          push(pop() + pop());
          pc++; // ADD
        case 0x02:
          push(pop() * pop());
          pc++; // MUL
        case 0x03:
          final a = pop();
          final b = pop();
          push(a - b);
          pc++; // SUB
        case 0x04: // DIV
          final a = pop();
          final b = pop();
          push(b == BigInt.zero ? BigInt.zero : a ~/ b);
          pc++;
        case 0x05: // SDIV
          final a = _toSigned(pop());
          final b = _toSigned(pop());
          push(b == BigInt.zero ? BigInt.zero : a ~/ b);
          pc++;
        case 0x06: // MOD
          final a = pop();
          final b = pop();
          push(b == BigInt.zero ? BigInt.zero : a % b);
          pc++;
        case 0x07: // SMOD
          final a = _toSigned(pop());
          final b = _toSigned(pop());
          push(b == BigInt.zero ? BigInt.zero : a.remainder(b));
          pc++;
        case 0x0a: // EXP
          final a = pop();
          final b = pop();
          push(a.modPow(b, BigInt.one << 256));
          pc++;
        case 0x0b: // SIGNEXTEND
          final b = pop();
          final x = pop();
          if (b >= BigInt.from(32)) {
            push(x);
          } else {
            final bit = b.toInt() * 8 + 7;
            final mask = (BigInt.one << (bit + 1)) - BigInt.one;
            push(
              ((x >> bit) & BigInt.one) == BigInt.one ? x | ~mask : x & mask,
            );
          }
          pc++;
        case 0x20: // KECCAK256(offset, len)
          final off = pop().toInt();
          final len = pop().toInt();
          final bytes = [for (var i = 0; i < len; i++) memByte(off + i)];
          var h = BigInt.zero;
          for (final b in keccak256(bytes)) h = (h << 8) | BigInt.from(b);
          push(h);
          pc++;
        case 0x10:
          final a = pop();
          final b = pop();
          push(a < b ? BigInt.one : BigInt.zero);
          pc++; // LT
        case 0x11:
          final a = pop();
          final b = pop();
          push(a > b ? BigInt.one : BigInt.zero);
          pc++; // GT
        case 0x12: // SLT
          final a = _toSigned(pop());
          final b = _toSigned(pop());
          push(a < b ? BigInt.one : BigInt.zero);
          pc++;
        case 0x13: // SGT
          final a = _toSigned(pop());
          final b = _toSigned(pop());
          push(a > b ? BigInt.one : BigInt.zero);
          pc++;
        case 0x14:
          push(pop() == pop() ? BigInt.one : BigInt.zero);
          pc++; // EQ
        case 0x15:
          push(pop() == BigInt.zero ? BigInt.one : BigInt.zero);
          pc++; // ISZERO
        case 0x16:
          push(pop() & pop());
          pc++; // AND
        case 0x17:
          push(pop() | pop());
          pc++; // OR
        case 0x18:
          push(pop() ^ pop());
          pc++; // XOR
        case 0x19:
          push(~pop());
          pc++; // NOT
        case 0x1b: // SHL(shift, value)
          final shift = pop();
          final value = pop();
          push(
            shift >= BigInt.from(256) ? BigInt.zero : value << shift.toInt(),
          );
          pc++;
        case 0x1c: // SHR(shift, value)
          final shift = pop();
          final value = pop();
          push(
            shift >= BigInt.from(256) ? BigInt.zero : value >> shift.toInt(),
          );
          pc++;
        case 0x1d: // SAR(shift, value)
          final shift = pop();
          final value = _toSigned(pop());
          if (shift >= BigInt.from(256)) {
            push(value < BigInt.zero ? _mask : BigInt.zero);
          } else {
            push(value >> shift.toInt());
          }
          pc++;
        case 0x35:
          push(loadWord(calldataByte, pop().toInt()));
          pc++; // CALLDATALOAD
        case 0x36:
          push(BigInt.from(calldata.length));
          pc++; // CALLDATASIZE
        case 0x38:
          push(BigInt.from(code.length));
          pc++; // CODESIZE
        case 0x50:
          pop();
          pc++; // POP
        case 0x51:
          push(loadWord(memByte, pop().toInt()));
          pc++; // MLOAD
        case 0x52:
          final off = pop();
          final val = pop();
          storeWord(off.toInt(), val);
          pc++; // MSTORE
        case 0x33:
          push(caller);
          pc++; // CALLER
        case 0x39: // CODECOPY(destOffset, offset, len)
          final dest = pop().toInt();
          final off = pop().toInt();
          final len = pop().toInt();
          for (var i = 0; i < len; i++) {
            memory[dest + i] = (off + i) < code.length ? code[off + i] : 0;
          }
          pc++;
        case 0x54:
          push(storage[pop()] ?? BigInt.zero);
          pc++; // SLOAD
        case 0x55:
          final k = pop();
          final v = pop();
          storage[k] = v;
          pc++; // SSTORE
        case 0xa0:
        case 0xa1:
        case 0xa2:
        case 0xa3:
        case 0xa4: // LOG0..LOG4
          final off = pop().toInt();
          final len = pop().toInt();
          final topics = [for (var i = 0; i < op - 0xa0; i++) pop()];
          final data = Uint8List(len);
          for (var i = 0; i < len; i++) data[i] = memByte(off + i);
          logs.add((topics: topics, data: data));
          pc++;
        case 0x56:
          pc = _jump(pop()); // JUMP
        case 0x57: // JUMPI
          final dest = pop();
          final cond = pop();
          pc = cond != BigInt.zero ? _jump(dest) : pc + 1;
        case 0x5b:
          pc++; // JUMPDEST
        case 0x5f:
          push(BigInt.zero);
          pc++; // PUSH0
        case 0xf3: // RETURN
          final off = pop().toInt();
          final len = pop().toInt();
          final out = Uint8List(len);
          for (var i = 0; i < len; i++) out[i] = memByte(off + i);
          return out;
        case 0xfd:
          return null; // REVERT
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
            throw StateError(
              'Unsupported opcode 0x${op.toRadixString(16)} at $pc',
            );
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

  /// Interprets a masked 256-bit word as a two's-complement signed integer.
  static BigInt _toSigned(BigInt v) =>
      (v & (BigInt.one << 255)) != BigInt.zero ? v - (BigInt.one << 256) : v;
}

Uint8List _calldata(String signature, List<int> args) =>
    _calldataBig(signature, args.map(BigInt.from).toList());

Uint8List _calldataBig(String signature, List<BigInt> args) {
  final sel = selectorHex(signature).substring(2);
  final out = BytesBuilder();
  for (var i = 0; i < 4; i++) {
    out.addByte(int.parse(sel.substring(i * 2, i * 2 + 2), radix: 16));
  }
  for (final a in args) {
    final word = Uint8List(32);
    var v = a;
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

/// Reads the 32-byte return word as a two's-complement signed integer.
BigInt _asInt(Uint8List? data) {
  final v = _asUint(data);
  return v >= (BigInt.one << 255) ? v - (BigInt.one << 256) : v;
}

/// Compiles [source] and returns the runtime bytecode of contract [name].
///
/// Throws (rather than using `expect`) on any compile error so it can also be
/// called at `group` body level, not only inside a `test`.
Uint8List _runtimeOf(String source, String name) {
  return _contractOf(source, name).deployedBytecode;
}

ContractOutput _contractOf(String source, String name) {
  final result = (CompilerStack()..addSource('$name.sol', source)).compile();
  final errors = result.diagnostics.where((d) => d.isError);
  if (errors.isNotEmpty) {
    throw StateError(
      'compile errors:\n${errors.map((d) => d.message).join('\n')}',
    );
  }
  final c = result.contracts[name];
  if (c == null) throw StateError('contract "$name" not produced');
  return c;
}

/// Compiles, runs the *creation* bytecode (executing the constructor), and
/// returns a runtime [MiniEvm] whose storage carries the constructor's writes.
MiniEvm _deploy(String source, String name, {BigInt? deployer}) {
  final c = _contractOf(source, name);
  final creation = MiniEvm(c.bytecode);
  if (deployer != null) creation.caller = deployer;
  final runtimeCode = creation.call(Uint8List(0));
  if (runtimeCode == null) throw StateError('constructor reverted');
  final evm = MiniEvm(runtimeCode);
  evm.storage.addAll(creation.storage);
  return evm;
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
      final out = MiniEvm(
        code,
      ).call(_calldata('getSum(uint256,uint256)', [2, 3]));
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
      expect(
        _asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [5]))),
        BigInt.from(10),
      ); // 0+1+2+3+4
      expect(
        _asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [1]))),
        BigInt.zero,
      );
      expect(
        _asUint(MiniEvm(code).call(_calldata('sumTo(uint256)', [10]))),
        BigInt.from(45),
      );
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
      expect(
        _asUint(evm.call(_calldata('ne(uint256,uint256)', [1, 2]))),
        BigInt.one,
      );
      expect(
        _asUint(evm.call(_calldata('ne(uint256,uint256)', [2, 2]))),
        BigInt.zero,
      );
      expect(
        _asUint(evm.call(_calldata('le(uint256,uint256)', [2, 3]))),
        BigInt.one,
      );
      expect(
        _asUint(evm.call(_calldata('le(uint256,uint256)', [3, 3]))),
        BigInt.one,
      );
      expect(
        _asUint(evm.call(_calldata('le(uint256,uint256)', [4, 3]))),
        BigInt.zero,
      );
    });
  });

  group('checked arithmetic (Solidity ≥0.8 semantics)', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Math {
  function add(uint256 a, uint256 b) public pure returns (uint256) { return a + b; }
  function sub(uint256 a, uint256 b) public pure returns (uint256) { return a - b; }
  function mul(uint256 a, uint256 b) public pure returns (uint256) { return a * b; }
  function addUnchecked(uint256 a, uint256 b) public pure returns (uint256) {
    unchecked { return a + b; }
  }
}
''', 'Math');

    final maxU = (BigInt.one << 256) - BigInt.one;

    test('normal arithmetic still computes the right value', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('add(uint256,uint256)', [40, 2]))),
        BigInt.from(42),
      );
      expect(
        _asUint(MiniEvm(code).call(_calldata('mul(uint256,uint256)', [6, 7]))),
        BigInt.from(42),
      );
    });

    test('addition overflow reverts (Panic)', () {
      final out = MiniEvm(
        code,
      ).call(_calldataBig('add(uint256,uint256)', [maxU, BigInt.one]));
      expect(out, isNull, reason: 'MAX + 1 must revert');
    });

    test('subtraction underflow reverts (Panic)', () {
      final out = MiniEvm(code).call(_calldata('sub(uint256,uint256)', [3, 5]));
      expect(out, isNull, reason: '3 - 5 must revert on uint256');
    });

    test('multiplication overflow reverts (Panic)', () {
      final half = BigInt.one << 200;
      final out = MiniEvm(
        code,
      ).call(_calldataBig('mul(uint256,uint256)', [half, half]));
      expect(out, isNull, reason: '2^200 * 2^200 must revert');
    });

    test('unchecked block wraps instead of reverting', () {
      final out = MiniEvm(
        code,
      ).call(_calldataBig('addUnchecked(uint256,uint256)', [maxU, BigInt.one]));
      expect(
        _asUint(out),
        BigInt.zero,
        reason: 'MAX + 1 wraps to 0 in unchecked',
      );
    });

    test('narrow uint8 overflow reverts', () {
      final c = _runtimeOf('''
pragma solidity ^0.8.0;
contract Narrow {
  function add8(uint8 a, uint8 b) public pure returns (uint8) { return a + b; }
}
''', 'Narrow');
      expect(
        _asUint(MiniEvm(c).call(_calldata('add8(uint8,uint8)', [200, 50]))),
        BigInt.from(250),
      );
      expect(
        MiniEvm(c).call(_calldata('add8(uint8,uint8)', [200, 100])),
        isNull,
        reason: '200 + 100 overflows uint8 (max 255)',
      );
    });
  });

  group('signed integer operations', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Signed {
  function lt(int256 a, int256 b) public pure returns (bool) { return a < b; }
  function divide(int256 a, int256 b) public pure returns (int256) { return a / b; }
  function sub(int256 a, int256 b) public pure returns (int256) { return a - b; }
}
''', 'Signed');

    test('signed less-than uses SLT (negative < positive)', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('lt(int256,int256)', [-1, 1]))),
        BigInt.one,
        reason: '-1 < 1 is true with signed comparison',
      );
      expect(
        _asUint(MiniEvm(code).call(_calldata('lt(int256,int256)', [1, -1]))),
        BigInt.zero,
      );
    });

    test('signed division uses SDIV (truncates toward zero)', () {
      expect(
        _asInt(MiniEvm(code).call(_calldata('divide(int256,int256)', [-7, 2]))),
        BigInt.from(-3),
        reason: '-7 / 2 == -3 (truncated)',
      );
      expect(
        _asInt(MiniEvm(code).call(_calldata('divide(int256,int256)', [7, -2]))),
        BigInt.from(-3),
      );
    });

    test('signed subtraction yields negative results', () {
      expect(
        _asInt(MiniEvm(code).call(_calldata('sub(int256,int256)', [3, 5]))),
        BigInt.from(-2),
        reason: '3 - 5 == -2 for int256 (no revert)',
      );
    });

    test('division by zero reverts (Panic 0x12)', () {
      expect(
        MiniEvm(code).call(_calldata('divide(int256,int256)', [1, 0])),
        isNull,
      );
    });
  });

  group('require / assert / revert', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Guard {
  function mustBePositive(uint256 x) public pure returns (uint256) {
    require(x > 0, "not positive");
    return x;
  }
  function assertEven(uint256 x) public pure returns (uint256) {
    assert(x % 2 == 0);
    return x;
  }
  function always() public pure returns (uint256) {
    revert("nope");
    return 1;
  }
}
''', 'Guard');

    test('require passes when condition holds', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('mustBePositive(uint256)', [5]))),
        BigInt.from(5),
      );
    });
    test('require reverts when condition fails', () {
      expect(
        MiniEvm(code).call(_calldata('mustBePositive(uint256)', [0])),
        isNull,
      );
    });
    test('assert passes / fails correctly', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('assertEven(uint256)', [4]))),
        BigInt.from(4),
      );
      expect(MiniEvm(code).call(_calldata('assertEven(uint256)', [3])), isNull);
    });
    test('revert(reason) always reverts', () {
      expect(MiniEvm(code).call(_calldata('always()', [])), isNull);
    });
  });

  group('mappings (keccak256 storage slots)', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Token {
  mapping(address => uint256) balances;
  mapping(address => mapping(address => uint256)) allowance;
  function balanceOf(address who) public view returns (uint256) {
    return balances[who];
  }
  function mint(uint256 amount) public {
    balances[msg.sender] = balances[msg.sender] + amount;
  }
  function approve(address spender, uint256 amount) public {
    allowance[msg.sender][spender] = amount;
  }
  function allowanceOf(address owner, address spender) public view returns (uint256) {
    return allowance[owner][spender];
  }
}
''', 'Token');

    test('mint updates the caller\'s mapping entry', () {
      final evm = MiniEvm(code);
      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xaa]))),
        BigInt.zero,
      );
      evm.call(_calldata('mint(uint256)', [100]));
      evm.call(_calldata('mint(uint256)', [50]));
      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xaa]))),
        BigInt.from(150),
      );
      // A different key is independent / still zero.
      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xbb]))),
        BigInt.zero,
      );
    });

    test('nested mapping slot is keccak-composed correctly', () {
      final evm = MiniEvm(code);
      evm.call(_calldata('approve(address,uint256)', [0xbb, 777]));
      expect(
        _asUint(
          evm.call(_calldata('allowanceOf(address,address)', [0xaa, 0xbb])),
        ),
        BigInt.from(777),
      );
      // Swapped owner/spender must map to a different (empty) slot.
      expect(
        _asUint(
          evm.call(_calldata('allowanceOf(address,address)', [0xbb, 0xaa])),
        ),
        BigInt.zero,
      );
    });
  });

  group('constructor / events / custom errors', () {
    const erc20 = '''
pragma solidity ^0.8.0;
contract Mini {
  address owner;
  uint256 supply;
  mapping(address => uint256) balances;
  event Transfer(address indexed from, address indexed to, uint256 value);
  error Unauthorized(address who);

  constructor() {
    owner = msg.sender;
    supply = 1000;
    balances[msg.sender] = 1000;
  }
  function getSupply() public view returns (uint256) { return supply; }
  function getOwner() public view returns (address) { return owner; }
  function balanceOf(address a) public view returns (uint256) { return balances[a]; }
  function transfer(address to, uint256 amt) public {
    balances[msg.sender] = balances[msg.sender] - amt;
    balances[to] = balances[to] + amt;
    emit Transfer(msg.sender, to, amt);
  }
  function onlyOwner() public view {
    if (msg.sender != owner) revert Unauthorized(msg.sender);
  }
}
''';

    test('constructor initialises storage (read back through getters)', () {
      final evm = _deploy(erc20, 'Mini', deployer: BigInt.from(0xaa));
      expect(
        _asUint(evm.call(_calldata('getSupply()', []))),
        BigInt.from(1000),
      );
      expect(_asUint(evm.call(_calldata('getOwner()', []))), BigInt.from(0xaa));
      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xaa]))),
        BigInt.from(1000),
      );
    });

    test('transfer moves balance and emits Transfer with correct topics', () {
      final evm = _deploy(erc20, 'Mini', deployer: BigInt.from(0xaa));
      evm.caller = BigInt.from(0xaa);
      evm.logs.clear();
      evm.call(_calldata('transfer(address,uint256)', [0xbb, 30]));

      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xaa]))),
        BigInt.from(970),
      );
      expect(
        _asUint(evm.call(_calldata('balanceOf(address)', [0xbb]))),
        BigInt.from(30),
      );

      expect(evm.logs, hasLength(1));
      final log = evm.logs.single;
      // topic0 = keccak256("Transfer(address,address,uint256)")
      expect(
        log.topics[0],
        BigInt.parse(
          'ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
          radix: 16,
        ),
      );
      expect(log.topics[1], BigInt.from(0xaa)); // indexed from
      expect(log.topics[2], BigInt.from(0xbb)); // indexed to
      expect(_asUint(log.data), BigInt.from(30)); // non-indexed value
    });

    test('custom error reverts when unauthorised', () {
      final evm = _deploy(erc20, 'Mini', deployer: BigInt.from(0xaa));
      evm.caller = BigInt.from(0xcc); // not the owner
      expect(evm.call(_calldata('onlyOwner()', [])), isNull);
      evm.caller = BigInt.from(0xaa); // owner
      expect(evm.call(_calldata('onlyOwner()', [])), isNotNull);
    });

    test('checked transfer underflow reverts (insufficient balance)', () {
      final evm = _deploy(erc20, 'Mini', deployer: BigInt.from(0xaa));
      evm.caller = BigInt.from(0xbb); // balance 0
      expect(
        evm.call(_calldata('transfer(address,uint256)', [0xaa, 1])),
        isNull,
      );
    });
  });

  group('public state-variable getters', () {
    final src = '''
pragma solidity ^0.8.0;
contract Pub {
  uint256 public total;
  mapping(address => uint256) public balances;
  constructor() { total = 42; balances[msg.sender] = 7; }
}
''';
    test('auto-generated scalar and mapping getters return storage', () {
      final evm = _deploy(src, 'Pub', deployer: BigInt.from(0xaa));
      expect(_asUint(evm.call(_calldata('total()', []))), BigInt.from(42));
      expect(
        _asUint(evm.call(_calldata('balances(address)', [0xaa]))),
        BigInt.from(7),
      );
      expect(
        _asUint(evm.call(_calldata('balances(address)', [0xbb]))),
        BigInt.zero,
      );
    });
  });

  group('explicit type conversions', () {
    test('uint8(x) masks to the low byte', () {
      final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Cast {
  function toU8(uint256 x) public pure returns (uint8) { return uint8(x); }
}
''', 'Cast');
      expect(
        _asUint(MiniEvm(code).call(_calldata('toU8(uint256)', [0x1ff]))),
        BigInt.from(0xff),
        reason: '0x1ff truncated to uint8 == 0xff',
      );
      expect(
        _asUint(MiniEvm(code).call(_calldata('toU8(uint256)', [0x42]))),
        BigInt.from(0x42),
      );
    });
  });

  group('short-circuit && / ||', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Logic {
  function andOp(bool a, bool b) public pure returns (bool) { return a && b; }
  function orOp(bool a, bool b) public pure returns (bool) { return a || b; }
}
''', 'Logic');
    final evm = MiniEvm(code);

    test('&& true && true == true', () {
      expect(
        _asUint(evm.call(_calldata('andOp(bool,bool)', [1, 1]))),
        BigInt.one,
      );
    });
    test('&& true && false == false', () {
      expect(
        _asUint(evm.call(_calldata('andOp(bool,bool)', [1, 0]))),
        BigInt.zero,
      );
    });
    test('&& false && true == false', () {
      expect(
        _asUint(evm.call(_calldata('andOp(bool,bool)', [0, 1]))),
        BigInt.zero,
      );
    });
    test('|| false || false == false', () {
      expect(
        _asUint(evm.call(_calldata('orOp(bool,bool)', [0, 0]))),
        BigInt.zero,
      );
    });
    test('|| false || true == true', () {
      expect(
        _asUint(evm.call(_calldata('orOp(bool,bool)', [0, 1]))),
        BigInt.one,
      );
    });
    test('|| true || false == true', () {
      expect(
        _asUint(evm.call(_calldata('orOp(bool,bool)', [1, 0]))),
        BigInt.one,
      );
    });
  });

  group('exponentiation **', () {
    final code = _runtimeOf('''
pragma solidity ^0.8.0;
contract Exp {
  function pow(uint256 base, uint256 exp) public pure returns (uint256) {
    return base ** exp;
  }
  function pow8(uint8 base, uint8 exp) public pure returns (uint8) {
    return base ** exp;
  }
}
''', 'Exp');

    test('2 ** 10 == 1024', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('pow(uint256,uint256)', [2, 10]))),
        BigInt.from(1024),
      );
    });

    test('3 ** 0 == 1', () {
      expect(
        _asUint(MiniEvm(code).call(_calldata('pow(uint256,uint256)', [3, 0]))),
        BigInt.one,
      );
    });

    test('uint8 overflow on ** reverts', () {
      // 2 ** 8 = 256, which overflows uint8 (max 255)
      expect(
        MiniEvm(code).call(_calldata('pow8(uint8,uint8)', [2, 8])),
        isNull,
        reason: '2**8 = 256 overflows uint8',
      );
    });
  });

  group('constructor with parameters', () {
    test('constructor stores parameter in storage', () {
      final src = '''
pragma solidity ^0.8.0;
contract Initialized {
  uint256 value;
  constructor(uint256 v) {
    value = v;
  }
  function get() public view returns (uint256) { return value; }
}
''';
      final c = _contractOf(src, 'Initialized');
      // In the EVM, a deployment transaction passes the entire bytecode (creation
      // code + ABI-encoded constructor args) as its "calldata".  The creation code
      // calls codesize() to find where the args start.  We must therefore prepend
      // the creation bytecode to the encoded arg so that calldataload(codesize())
      // lands on the right bytes.
      final arg = Uint8List(32);
      arg[31] = 42; // ABI-encoded uint256(42)
      final fullCalldata = Uint8List.fromList([...c.bytecode, ...arg]);
      final creation = MiniEvm(c.bytecode);
      final runtimeCode = creation.call(fullCalldata);
      expect(runtimeCode, isNotNull, reason: 'constructor must not revert');
      final evm = MiniEvm(runtimeCode!);
      evm.storage.addAll(creation.storage);
      expect(_asUint(evm.call(_calldata('get()', []))), BigInt.from(42));
    });
  });

  group('dynamic array push/pop/length', () {
    final src = '''
pragma solidity ^0.8.0;
contract DynArray {
  uint256[] items;
  function push(uint256 v) public { items.push(v); }
  function pop() public { items.pop(); }
  function length() public view returns (uint256) { return items.length; }
  function get(uint256 i) public view returns (uint256) { return items[i]; }
}
''';

    test('push increments length and stores value', () {
      final evm = _deploy(src, 'DynArray');
      expect(_asUint(evm.call(_calldata('length()', []))), BigInt.zero);
      evm.call(_calldata('push(uint256)', [10]));
      evm.call(_calldata('push(uint256)', [20]));
      expect(_asUint(evm.call(_calldata('length()', []))), BigInt.from(2));
      expect(
        _asUint(evm.call(_calldata('get(uint256)', [0]))),
        BigInt.from(10),
      );
      expect(
        _asUint(evm.call(_calldata('get(uint256)', [1]))),
        BigInt.from(20),
      );
    });

    test('pop decrements length', () {
      final evm = _deploy(src, 'DynArray');
      evm.call(_calldata('push(uint256)', [5]));
      evm.call(_calldata('push(uint256)', [6]));
      evm.call(_calldata('pop()', []));
      expect(_asUint(evm.call(_calldata('length()', []))), BigInt.one);
    });

    test('pop on empty array reverts (Panic 0x31)', () {
      final evm = _deploy(src, 'DynArray');
      expect(
        evm.call(_calldata('pop()', [])),
        isNull,
        reason: 'pop on empty array should Panic',
      );
    });
  });

  group('import resolution', () {
    test('two-file compilation resolves contract from import', () {
      final libSrc = '''
pragma solidity ^0.8.0;
contract Lib {
  function double(uint256 x) public pure returns (uint256) { return x * 2; }
}
''';
      final mainSrc = '''
pragma solidity ^0.8.0;
import "Lib.sol";
contract Main {
  function run(uint256 x) public pure returns (uint256) { return x + 1; }
}
''';
      final stack = CompilerStack()
        ..addSource('Lib.sol', libSrc)
        ..addSource('Main.sol', mainSrc);
      final result = stack.compile();
      expect(result.diagnostics.where((d) => d.isError), isEmpty);
      expect(result.contracts.containsKey('Lib'), isTrue);
      expect(result.contracts.containsKey('Main'), isTrue);
    });
  });

  group('executes hand-written Yul (multi-return functions)', () {
    // Parses Yul, compiles it to bytecode and runs it, asserting on storage.
    MiniEvm runYul(String src) {
      final block = YulParser(src).parseBlock();
      final code = YulCodeGenerator().generate(YulObject('T', block, [], {}));
      final evm = MiniEvm(code);
      evm.call(Uint8List(0));
      return evm;
    }

    test('2-return function preserves value order (identity)', () {
      // x:=a, y:=b ⇒ p=3, q=4
      final evm = runYul('''
        {
          function id2(a, b) -> x, y { x := a  y := b }
          let p, q := id2(3, 4)
          sstore(0, p)
          sstore(1, q)
        }
      ''');
      expect(evm.storage[BigInt.from(0)], BigInt.from(3));
      expect(evm.storage[BigInt.from(1)], BigInt.from(4));
    });

    test('2-return function that swaps its arguments', () {
      // x:=b, y:=a ⇒ p=9, q=7
      final evm = runYul('''
        {
          function swap2(a, b) -> x, y { x := b  y := a }
          let p, q := swap2(7, 9)
          sstore(0, p)
          sstore(1, q)
        }
      ''');
      expect(evm.storage[BigInt.from(0)], BigInt.from(9));
      expect(evm.storage[BigInt.from(1)], BigInt.from(7));
    });

    test('3-return function with computation', () {
      // returns (a+b, mul(a,b), a) ⇒ (5, 6, 2)
      final evm = runYul('''
        {
          function f(a, b) -> s, p, first {
            s := add(a, b)
            p := mul(a, b)
            first := a
          }
          let x, y, z := f(2, 3)
          sstore(0, x)
          sstore(1, y)
          sstore(2, z)
        }
      ''');
      expect(evm.storage[BigInt.from(0)], BigInt.from(5));
      expect(evm.storage[BigInt.from(1)], BigInt.from(6));
      expect(evm.storage[BigInt.from(2)], BigInt.from(2));
    });

    test('multi-return with an early leave', () {
      final evm = runYul('''
        {
          function pick(c) -> x, y {
            x := 1
            y := 2
            if c { x := 100  y := 200  leave }
            x := 9
          }
          let a, b := pick(1)
          sstore(0, a)
          sstore(1, b)
        }
      ''');
      expect(evm.storage[BigInt.from(0)], BigInt.from(100));
      expect(evm.storage[BigInt.from(1)], BigInt.from(200));
    });
  });
}
