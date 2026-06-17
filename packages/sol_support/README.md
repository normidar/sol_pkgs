# sol_support

Universal foundation library for the `sol_pkgs` Solidity compiler.

Every other package in the monorepo depends on this one.

## Features

| Module | Description |
|---|---|
| `SourceLocation` | Byte-offset + length span in a source file |
| `SourceMap` | Fast binary-search conversion from offset → `(line, column)` |
| `SourceUnit` / `SourceUnitRegistry` | Tracks all source files in a compilation |
| `Diagnostic` / `DiagnosticCollector` | Error/warning/info collection with fatal-error short-circuit |
| `ImportRemapping` / `ImportRemapper` | `[context:]prefix=target` path rewriting (Foundry / Hardhat style) |

## Usage

```dart
import 'package:sol_support/sol_support.dart';

void main() {
  final registry = SourceUnitRegistry();
  final unit = registry.add('Adder.sol', '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''');

  final lc = unit.locationOf(24);
  print(lc); // e.g. 3:1

  final diagnostics = DiagnosticCollector();
  diagnostics.warning('unused variable', location: SourceLocation(
    sourceIndex: unit.index,
    offset: 24,
    length: 3,
  ));
  print(diagnostics.diagnostics.first);
}
```

## Diagnostic severity levels

| Severity | Meaning |
|---|---|
| `info` | Informational note |
| `warning` | Non-fatal, compilation continues |
| `error` | Compilation fails at end of phase |
| `fatalError` | Throws `FatalErrorException` immediately |

## Dependencies

None (this is the root of the dependency graph).
