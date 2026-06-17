# sol_abi

ABI JSON generation and ABI encoding/decoding for the `sol_pkgs` Solidity compiler.

## Features

| Module | Description |
|---|---|
| `AbiGenerator` | Generates the Solidity ABI JSON from a `ContractDefinition` |
| `AbiEncoder` | ABI-encodes Dart values for function calls and return data |

## ABI JSON generation

```dart
import 'package:sol_abi/sol_abi.dart';

final json = AbiGenerator().generateJson(contractAst);
print(json);
// [
//   {
//     "type": "function",
//     "name": "getSum",
//     "inputs": [{"name": "a", "type": "uint256"}, {"name": "b", "type": "uint256"}],
//     "outputs": [{"name": "", "type": "uint256"}],
//     "stateMutability": "pure"
//   }
// ]
```

## ABI encoding

```dart
import 'package:sol_abi/sol_abi.dart';
import 'package:sol_types/sol_types.dart';

final enc = AbiEncoder();
final calldata = enc.encode([
  (uint256Type, 1),
  (uint256Type, 2),
]);
// 64 bytes: 0x00…01 0x00…02
```

## Supported ABI types

| Solidity type | Status |
|---|---|
| `uint8`…`uint256`, `int8`…`int256` | ✅ |
| `bool` | ✅ |
| `address` | ✅ |
| `bytes1`…`bytes32` | ✅ |
| `bytes` | ✅ |
| `string` | ✅ |
| `T[]` / `T[N]` | ✅ |
| `tuple` (struct) | Planned |

## Dependencies

- `sol_support` — foundation
- `sol_ast` — `ContractDefinition`, `FunctionDefinition`, `Parameter`
- `sol_types` — `SolType` hierarchy for encoder
