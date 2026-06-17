# sol_types

Solidity type system for the `sol_pkgs` compiler.

Defines the runtime type lattice used by `sol_sema` (type checking) and `sol_abi` (ABI encoding).

## Type hierarchy

```
SolType
├── IntType          (int8…int256, uint8…uint256)
├── BoolType
├── AddressType      (address, address payable)
├── BytesNType       (bytes1…bytes32)
├── BytesType        (bytes — dynamic)
├── StringType       (string — dynamic)
├── ArrayType        (T[N] fixed, T[] dynamic)
├── MappingType      (mapping(K => V))
├── TupleType        (anonymous struct / multi-return)
├── FunctionType     (internal / external)
├── TypeType         (type(X) expressions)
└── ErrorType        (sentinel for unresolved types)
```

## Key functions

| Function | Description |
|---|---|
| `isImplicitlyConvertible(from, to)` | Widening / covariance rules |
| `isExplicitlyConvertible(from, to)` | Cast rules |
| `commonType(a, b)` | Least upper bound for binary ops |

## Usage

```dart
import 'package:sol_types/sol_types.dart';

void main() {
  const a = IntType(8, signed: false);   // uint8
  const b = IntType(256, signed: false); // uint256
  print(isImplicitlyConvertible(a, b)); // true
  print(commonType(a, b));              // uint256
}
```

## Dependencies

- `sol_support` — foundation (no type-level dep, but shares diagnostics pattern)
