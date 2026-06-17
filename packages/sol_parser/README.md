# sol_parser

Recursive-descent Solidity parser for the `sol_pkgs` compiler.

Converts a flat token list (from `sol_lexer`) into a typed `SourceFile` AST (from `sol_ast`).

## Features

- Full Solidity 0.8.x grammar support
- Parses `pragma`, `import`, `contract`, `interface`, `library`
- All member kinds: functions, constructors, modifiers, events, errors, structs, enums, state variables
- All statement forms: `if`/`else`, `for`, `while`, `do`/`while`, `return`, `emit`, `revert`, `assembly`
- All expression forms including ternary, assignment operators, postfix `++`/`--`, tuple expressions
- Named function arguments: `foo({a: 1, b: 2})`
- Inline assembly blocks (stored as raw Yul text for `sol_yul` to process)
- Error recovery: continues parsing after a bad token, collects all errors in one pass

## Usage

```dart
import 'package:sol_lexer/sol_lexer.dart';
import 'package:sol_parser/sol_parser.dart';
import 'package:sol_support/sol_support.dart';

void main() {
  const src = '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

  final diagnostics = DiagnosticCollector();
  final tokens = Lexer(source: src, sourceIndex: 0).tokenize();
  final ast = Parser(tokens: tokens, sourceIndex: 0, diagnostics: diagnostics).parse();

  if (diagnostics.hasErrors) {
    for (final d in diagnostics.diagnostics) print(d);
  } else {
    print('Parsed ${ast.declarations.length} contract(s)');
  }
}
```

## Grammar coverage

| Construct | Status |
|---|---|
| `pragma solidity` | ✅ |
| `import` (plain / aliased / named) | ✅ |
| `contract` / `interface` / `library` | ✅ |
| `function` with all specifiers | ✅ |
| `modifier` / `event` / `error` | ✅ |
| `struct` / `enum` | ✅ |
| State variables (visibility, mutability) | ✅ |
| All statement kinds | ✅ |
| All expression kinds | ✅ |
| `mapping(K => V)` type names | ✅ |
| Function type names | ✅ |
| `assembly { … }` | ✅ (raw capture) |

## Dependencies

- `sol_support` — diagnostics, source locations
- `sol_lexer` — token stream
- `sol_ast` — AST node types
