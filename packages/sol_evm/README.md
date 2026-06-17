# sol_evm

EVM opcode table, two-pass assembler, and bytecode utilities for the `sol_pkgs` compiler.

## Features

- Complete `Opcode` enum covering Shanghai + Cancun opcodes (including `TLOAD`/`TSTORE`, `MCOPY`, `BLOBHASH`, `BLOBBASEFEE`, `PUSH0`)
- Each opcode records: byte value, stack consumed/produced, base gas cost, immediate byte count
- `Assembler` class for building EVM bytecode programmatically:
  - `emit(Opcode)` — raw opcode
  - `push(BigInt)` / `push1(int)` — auto-selects `PUSHn`
  - `label(name)` / `jump(label)` / `jumpi(label)` — two-pass label resolution
  - Convenience wrappers: `add()`, `sub()`, `dup(n)`, `swap(n)`, `ret()`, `revert()` …

## Usage

```dart
import 'package:sol_evm/sol_evm.dart';

void main() {
  // Emit: PUSH1 1, PUSH1 2, ADD, PUSH0, MSTORE, PUSH1 32, PUSH0, RETURN
  final asm = Assembler()
    ..push1(1)
    ..push1(2)
    ..add()
    ..emit(Opcode.PUSH0)
    ..emit(Opcode.MSTORE)
    ..push1(32)
    ..emit(Opcode.PUSH0)
    ..ret();

  final bytecode = asm.assemble();
  print(bytecode.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
}
```

## Opcode lookup

```dart
final op = Opcode.fromByte(0x01); // Opcode.ADD
print(op?.gas);                    // 3
```

## Dependencies

- `sol_support` — foundation (not yet used directly but required by convention)
