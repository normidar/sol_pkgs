# sol_sema

Semantic analysis for the `sol_pkgs` Solidity compiler.

This is the heaviest phase: it takes a `SourceFile` AST from `sol_parser`, resolves all names, linearises inheritance, and annotates every expression with its `SolType`.

## Passes

| Pass | Class | What it does |
|---|---|---|
| Name resolution | `Resolver` | Builds scopes, declares symbols, annotates `Identifier` nodes |
| Type checking | `TypeChecker` | Annotates expression nodes with `SolType`, emits mismatch errors |
| C3 linearisation | `c3Linearise()` | Computes method resolution order for multiple inheritance |

## Usage

```dart
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_sema/sol_sema.dart';
import 'package:sol_support/sol_support.dart';

void analyse(SourceFile ast, DiagnosticCollector diagnostics) {
  Resolver(diagnostics).resolve(ast);
  if (!diagnostics.hasErrors) {
    TypeChecker(diagnostics).visitSourceFile(ast);
  }
}
```

## C3 linearisation

```dart
import 'package:sol_sema/sol_sema.dart';

final bases = {'D': ['B', 'C'], 'B': ['A'], 'C': ['A'], 'A': []};
final mro = c3Linearise('D', (n) => bases[n]!);
// ['D', 'B', 'C', 'A']
```

## Dependencies

- `sol_support` — diagnostics
- `sol_ast` — AST visitor
- `sol_types` — type objects
