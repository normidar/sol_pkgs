# sol_lexer

Solidity tokeniser (scanner) for the `sol_pkgs` compiler.

## Features

- All Solidity keywords including `pure`, `view`, `payable`, `assembly`, `yul`
- Sized integer/bytes types: `uint8`…`uint256`, `int8`…`int256`, `bytes1`…`bytes32`
- Numeric literals: decimal, hex (`0x…`), scientific notation
- String literals: plain `"…"`, `unicode"…"`, `hex"…"`
- All operators including `**`, `>>>`, `<<=`, `>>>=`
- Single-line `//` and block `/* … */` comments
- Trivia (whitespace/comments) skipped by default; available via `includeTrivia: true`

## Usage

```dart
import 'package:sol_lexer/sol_lexer.dart';

void main() {
  const src = 'function getSum(uint256 a, uint256 b) public pure returns (uint256) { return a + b; }';
  final tokens = Lexer(source: src, sourceIndex: 0).tokenize();
  for (final tok in tokens) {
    print(tok);
  }
}
```

## Token kinds

Key categories in `TokenKind`:

| Category | Examples |
|---|---|
| Keywords | `kContract`, `kFunction`, `kPure`, `kPublic`, `kReturn` … |
| Sized types | `UintN` (width 8–256), `IntN` (width 8–256), `BytesN` (width 1–32) |
| Literals | `NumberLiteral`, `StringLiteral`, `UnicodeStringLiteral`, `HexStringLiteral` |
| Operators | `Plus`, `StarStar`, `GtGtGt`, `PlusEq` … |
| Delimiters | `LParen`, `LBrace`, `Semicolon`, `Comma` … |
| Special | `Eof`, `Error`, `Comment`, `Whitespace` |

## Dependencies

- `sol_support` — `SourceLocation`
