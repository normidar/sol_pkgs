# sol_yul

Yul intermediate representation, pretty-printer, and EVM bytecode generator for the `sol_pkgs` compiler.

Yul is the official intermediate language of the Solidity compiler. It is a low-level language with explicit control flow and no implicit type conversions.

## Components

| Module | Description |
|---|---|
| `yul_ast.dart` | Sealed class hierarchy for all Yul nodes |
| `yul_printer.dart` | Pretty-prints Yul AST back to Yul source text |
| `yul_codegen.dart` | Compiles Yul AST → EVM bytecode via `sol_evm` |

## Yul node types

```
YulObject           object "Name" { code { … } object "…" { … } }
YulBlock            { … }
YulFunctionDefinition   function f(x, y) -> r { … }
YulVariableDeclaration  let x := expr
YulAssignment           x := expr
YulIf               if cond { … }
YulForLoop          for { init } cond { post } { body }
YulSwitch           switch expr case v { … } default { … }
YulFunctionCall     add(a, b)
YulLiteral          0x01, "str", true
YulIdentifier       varName
```

## Usage

```dart
import 'package:sol_yul/sol_yul.dart';

void main() {
  // Build: { let result := add(1, 2) }
  final block = YulBlock([
    YulVariableDeclaration(
      ['result'],
      YulFunctionCall('add', [
        YulLiteral('1', YulLiteralKind.number),
        YulLiteral('2', YulLiteralKind.number),
      ]),
    ),
  ]);

  // Print Yul IR
  print(YulPrinter().print(block));

  // Compile to bytecode
  final obj = YulObject('MyContract', block, [], {});
  final bytecode = YulCodeGenerator().generate(obj);
  print(bytecode.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
}
```

## Builtin functions

All EVM opcodes are available as Yul builtins: `add`, `sub`, `mul`, `div`, `sload`, `sstore`, `call`, `return`, `revert`, `keccak256`, etc.

## Dependencies

- `sol_support` — foundation
- `sol_evm` — opcode table and assembler
