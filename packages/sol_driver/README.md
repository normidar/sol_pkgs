# sol_driver

Compiler orchestration for the `sol_pkgs` Solidity compiler.

Equivalent to solc's `CompilerStack`. Wires together all compiler phases and provides the `--standard-json` interface.

## Compilation pipeline

```
Source files
    │
    ▼ sol_lexer
Token streams
    │
    ▼ sol_parser
SourceFile ASTs
    │
    ▼ sol_sema (Resolver → TypeChecker)
Annotated ASTs
    │
    ▼ sol_codegen (IRGenerator)
Yul IR (YulObject)
    │
    ├─▶ sol_yul (YulPrinter) → Yul source text
    │
    └─▶ sol_yul (YulCodeGenerator) → EVM bytecode
              │
              └─▶ sol_abi (AbiGenerator) → ABI JSON
```

## Usage

### Programmatic

```dart
import 'package:sol_driver/sol_driver.dart';

void main() {
  final result = (CompilerStack()
    ..addSource('Adder.sol', '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
'''))
    .compile();

  if (!result.success) {
    for (final d in result.diagnostics) print(d);
    return;
  }

  final adder = result.contracts['Adder']!;
  print('ABI: ${adder.abi}');
  print('Bytecode: ${adder.bytecodeHex}');
  print('Yul IR:\n${adder.yulIr}');
}
```

### Standard-JSON

```dart
import 'dart:convert';
import 'package:sol_driver/sol_driver.dart';

void main() {
  final output = StandardJson().compile(jsonEncode({
    'language': 'Solidity',
    'sources': {
      'Adder.sol': {'content': '…'},
    },
    'settings': {
      'outputSelection': {'*': {'*': ['abi', 'evm.bytecode', 'ir']}},
    },
  }));
  print(output);
}
```

## Dependencies

All `sol_*` packages except `sol_cli`.
